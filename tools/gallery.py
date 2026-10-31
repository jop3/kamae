#!/usr/bin/env python3
"""Builds a browsable page of every technique script: techniques/build/gallery/index.html with
its media beside it (the video, a poster still, the contact sheet, and the video comparison where
a script was built against a clip). Run after tools/technique.sh has built the techniques:

    python3 tools/gallery.py            # -> techniques/build/gallery/

The page is self-contained (relative links only), so it opens from disk or can be published as is.
Needs ffmpeg for the posters and the smaller contact sheets.
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TECH = os.path.join(ROOT, "techniques")
BUILD = os.path.join(TECH, "build")
OUT = os.path.join(BUILD, "gallery")
ATTACKS = json.load(open(os.path.join(ROOT, "data", "attacks.json")))["attacks"]


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def phase_starts(seq):
    """When each step is fully reached, as Sequence.step_start does."""
    starts, t = [], 0.0
    for i, step in enumerate(seq["steps"]):
        if i > 0:
            t += float(step.get("transition", 0.0))
        starts.append(t)
        t += float(step.get("hold", 0.0))
    return starts


def attack_of(script):
    for phase in script.get("phases", []):
        for move in phase.get("do", []):
            if "attack" in move:
                entry = ATTACKS.get(move["attack"], {})
                return entry.get("names", {}).get("short", move["attack"]), entry.get("names", {}).get("english", "")
    return "", ""


def collect():
    items = []
    for name in sorted(os.listdir(TECH)):
        if not name.endswith(".json"):
            continue
        script = json.load(open(os.path.join(TECH, name)))
        s = slug(script.get("name", name[:-5]))
        build = os.path.join(BUILD, s)
        video = os.path.join(build, s + ".mp4")
        seq_path = os.path.join(build, "sequences", s + ".json")
        if not (os.path.exists(video) and os.path.exists(seq_path)):
            print("skipped (not built with video):", name, file=sys.stderr)
            continue
        seq = json.load(open(seq_path))
        saved = [p for p in script["phases"] if p.get("save", True)]
        starts = phase_starts(seq)
        stills = os.path.join(build, "stills")
        view = "view" if os.path.exists(os.path.join(stills, f"{s}_{slug(saved[0]['name'])}_view.png")) else "side"
        # The poster is the phase where the technique happens: the kake if there is one.
        key = next((p for p in saved if p["name"].lower() in ("kake", "osae")), saved[len(saved) // 2])
        items.append({
            "slug": s, "script": script, "file": name, "build": build, "video": video,
            "phases": [(p["name"], starts[i] if i < len(starts) else 0.0) for i, p in enumerate(saved)],
            "duration": starts[-1] + float(seq["steps"][-1].get("hold", 0.0)),
            "poster": os.path.join(stills, f"{s}_{slug(key['name'])}_{view}.png"),
            "sheet": os.path.join(build, "contact_sheet.png"),
            "compare": os.path.join(build, "compare_with_video.png"),
            "attack": (script["label"], "") if script.get("label") else attack_of(script),
            "ukemi": name.startswith("ukemi_"),
        })
    # The falls first (Uke on his own, every kind the techniques use), then the techniques.
    return [it for it in items if it["ukemi"]] + [it for it in items if not it["ukemi"]]


def build_media(items):
    media = os.path.join(OUT, "media")
    os.makedirs(media, exist_ok=True)
    for it in items:
        s = it["slug"]
        shutil.copyfile(it["video"], os.path.join(media, s + ".mp4"))
        ffmpeg("-i", it["poster"], "-vf", "scale=960:-2", "-q:v", "4", os.path.join(media, s + "_poster.jpg"))
        ffmpeg("-i", it["sheet"], "-vf", "scale=900:-2", "-q:v", "5", os.path.join(media, s + "_sheet.jpg"))
        it["has_compare"] = os.path.exists(it["compare"])
        if it["has_compare"]:
            ffmpeg("-i", it["compare"], "-vf", "scale=900:-2", "-q:v", "5", os.path.join(media, s + "_compare.jpg"))


def page(items):
    e = html.escape
    cards = []
    for n, it in enumerate(items):
        sc = it["script"]
        s = it["slug"]
        chips = "".join(
            f'<li><button type="button" class="phase" data-t="{t:.2f}"><span class="num">{i + 1}</span>'
            f'<span class="pname">{e(p)}</span><span class="pt">{t:.1f}s</span></button></li>'
            for i, (p, t) in enumerate(it["phases"]))
        attack, english = it["attack"]
        source = sc.get("source", "")
        extra = ""
        if it.get("has_compare"):
            extra += (f'<figure class="sheet"><img src="media/{s}_compare.jpg" loading="lazy" '
                      f'alt="Each phase of {e(sc["name"])} beside the matching frame of the source video">'
                      f'<figcaption>Left: the source clip at each phase\'s time. Right: the render.</figcaption></figure>')
        known = f'<p class="known"><span>Known</span> {e(sc["known"])}</p>' if sc.get("known") else ""
        if n == 0 or it["ukemi"] != items[n - 1]["ukemi"]:
            cards.append(f'<h2 class="section" id="{"ukemi" if it["ukemi"] else "techniques"}">'
                         f'{"Ukemi — falling and rolling" if it["ukemi"] else "Techniques"}</h2>')
        cards.append(f'''
<article class="tech" id="{s}">
  <div class="media">
    <video id="v-{s}" src="media/{s}.mp4" poster="media/{s}_poster.jpg" controls muted playsinline preload="metadata"></video>
  </div>
  <div class="text">
    <p class="attack">{e(attack)}{(" · " + e(english)) if english else ""}</p>
    <h2>{e(sc["name"])}</h2>
    <ol class="phases" data-video="v-{s}">{chips}</ol>
    <p class="desc">{e(sc.get("description", ""))}</p>
    {known}
    <p class="meta"><code>techniques/{e(it["file"])}</code> · {it["duration"]:.1f} s · {len(it["phases"])} phases{(" · " + e(source)) if source and not source.startswith("written from") else ""}</p>
    <details>
      <summary>Every phase, front and {"chosen view" if "view" in sc else "side"}</summary>
      <figure class="sheet"><img src="media/{s}_sheet.jpg" loading="lazy" alt="Contact sheet of every phase of {e(sc["name"])}"></figure>
      {extra}
    </details>
  </div>
</article>''')
    index = "".join(f'<li><a href="#{it["slug"]}">{e(it["script"]["name"])}</a></li>' for it in items)
    falls = sum(1 for it in items if it["ukemi"])
    count = f"{len(items) - falls} techniques" + (f" · {falls} ukemi" if falls else "")
    return TEMPLATE.replace("{{COUNT}}", count).replace("{{INDEX}}", index).replace("{{CARDS}}", "".join(cards))


TEMPLATE = r'''<title>Kamae Technique Library</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Shippori+Mincho:wght@500;700&family=Zen+Kaku+Gothic+New:wght@400;500;700&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
/* Layout: a single reading column of techniques, each a video beside its phases, like a
   handout page; the phases are the technique's own sequence and seek the video. */
:root {
  --ground: #f1f3ee;      /* tatami-pale */
  --paper: #fbfcf9;
  --ink: #1b2130;         /* hakama indigo-black */
  --muted: #5c6472;
  --rule: #d6dbcf;
  --accent: #2c4a7c;      /* aizome */
  --belt: #b5801c;        /* the belt colour cue */
  --display: "Shippori Mincho", "Hiragino Mincho ProN", Georgia, serif;
  --body: "Zen Kaku Gothic New", "Hiragino Sans", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --ground: #11141a; --paper: #181c24; --ink: #e8eae4; --muted: #9aa1ad; --rule: #2a303b;
  --accent: #8fb0e6; --belt: #e0b04c; color-scheme: dark } }
:root[data-theme="dark"] {
  --ground: #11141a; --paper: #181c24; --ink: #e8eae4; --muted: #9aa1ad; --rule: #2a303b;
  --accent: #8fb0e6; --belt: #e0b04c; color-scheme: dark }
body { background: var(--ground); color: var(--ink); font: 400 15px/1.6 var(--body); }
.wrap { max-width: 1120px; margin: 0 auto; padding-block: 40px 64px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
header { display: grid; gap: 12px; padding-bottom: 28px; border-bottom: 1px solid var(--rule); }
header .kicker { font: 500 12px/1 var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--belt); margin: 0; }
h1 { font: 700 clamp(30px, 5vw, 46px)/1.1 var(--display); margin: 0; text-wrap: balance; }
header p { margin: 0; max-width: 64ch; color: var(--muted); }
nav ul { list-style: none; padding: 0; margin: 8px 0 0; display: flex; flex-wrap: wrap; gap: 6px 14px; }
nav a { color: var(--accent); text-decoration: none; font-size: 14px; }
nav a:hover, nav a:focus-visible { text-decoration: underline; }
.section { font: 700 clamp(22px, 3vw, 30px)/1.2 var(--display); margin: 40px 0 0; padding-bottom: 8px;
  border-bottom: 2px solid var(--ink); scroll-margin-top: 16px; }
.tech { display: grid; grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr); gap: 28px;
  padding-block: 36px; border-bottom: 1px solid var(--rule); scroll-margin-top: 16px; }
.media video { width: 100%; max-width: 100%; aspect-ratio: 16 / 9; background: #000; border-radius: 4px; display: block; }
.text { min-width: 0; display: grid; gap: 12px; align-content: start; }
.attack { margin: 0; font: 500 12px/1.3 var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--belt); }
h2 { font: 700 26px/1.15 var(--display); margin: 0; text-wrap: balance; }
.phases { list-style: none; padding: 0; margin: 0; display: flex; flex-wrap: wrap; gap: 6px; }
.phase { display: inline-flex; align-items: baseline; gap: 6px; padding: 5px 10px; border: 1px solid var(--rule);
  border-radius: 999px; background: var(--paper); color: var(--ink); font: 500 13px/1.2 var(--body); cursor: pointer; }
.phase:hover { border-color: var(--accent); }
.phase:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.phase .num { font: 500 11px/1 var(--mono); color: var(--muted); }
.phase .pt { font: 400 11px/1 var(--mono); color: var(--muted); font-variant-numeric: tabular-nums; }
.phase.on { border-color: var(--accent); color: var(--accent); }
.desc { margin: 0; max-width: 62ch; }
.known { margin: 0; font-size: 13px; color: var(--muted); max-width: 62ch; }
.known span { font: 500 11px/1 var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--belt); margin-right: 6px; }
.meta { margin: 0; font-size: 12px; color: var(--muted); }
.meta code { font: 400 12px/1 var(--mono); color: var(--ink); }
details summary { cursor: pointer; color: var(--accent); font-size: 14px; }
details summary:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.sheet { margin: 12px 0 0; }
.sheet img { width: 100%; border-radius: 3px; border: 1px solid var(--rule); }
.sheet figcaption { font-size: 12px; color: var(--muted); margin-top: 4px; }
footer { padding-top: 24px; font-size: 13px; color: var(--muted); max-width: 70ch; }
@media (max-width: 760px) { .tech { grid-template-columns: minmax(0, 1fr); gap: 16px; } }
@media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; } }
</style>
<div class="wrap">
  <header>
    <p class="kicker">Kamae · {{COUNT}}</p>
    <h1>Technique library</h1>
    <p>Each technique is a short script of moves, built into poses and filmed by the Kamae posing engine. Tori wears the hakama, Uke the gi with the coloured belt. The falls come first: every kind of ukemi the techniques use, Uke on his own. Click a phase to jump the video to it.</p>
    <nav aria-label="Techniques"><ul>{{INDEX}}</ul></nav>
  </header>
  {{CARDS}}
  <footer>Rendered with Kamae from the scripts in <code>techniques/</code>. These are drafts written from descriptions and a few clips; an instructor's corrections go into the scripts.</footer>
</div>
<script>
for (const list of document.querySelectorAll('.phases')) {
  const video = document.getElementById(list.dataset.video);
  const buttons = [...list.querySelectorAll('.phase')];
  for (const b of buttons) b.addEventListener('click', () => {
    video.currentTime = parseFloat(b.dataset.t);
    video.pause();
  });
  video.addEventListener('timeupdate', () => {
    let current = 0;
    buttons.forEach((b, i) => { if (video.currentTime + 0.05 >= parseFloat(b.dataset.t)) current = i; });
    buttons.forEach((b, i) => b.classList.toggle('on', i === current));
  });
}
</script>
'''


def main():
    items = collect()
    if not items:
        sys.exit("nothing built yet: run tools/technique.sh on the scripts first")
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    build_media(items)
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(page(items))
    print(os.path.join(OUT, "index.html"), len(items), "techniques")


if __name__ == "__main__":
    main()
