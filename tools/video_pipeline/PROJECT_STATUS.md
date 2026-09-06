# Video-to-pose pipeline — status as of this session

## What's built

Four scripts in `/mnt/user-data/outputs/pose_pipeline/`, run in order per clip:

1. `01_extract_frames.py` — ffmpeg wrapper, video → JPEG frames at a chosen fps
2. `02_extract_pose.py` — MediaPipe Pose (pinned to `0.10.14`, see README for why) on frames,
   with `--bbox` to separate two people in frame → raw landmark JSON
3. `03_build_pose_json.py` — landmarks + your Grepp/Kuzushi/Kake frame picks → draft pose JSON
4. `04_to_godot_sequence.py` — draft JSON → the actual schema the Godot build spec calls for
   (per-bone direction vectors, explicit `grip_attachment` fields, real transition timing
   measured from source video fps rather than guessed)

All four are tested and working on real footage, not just synthetic smoke tests.

## What's been processed

Five clips uploaded and run through the full pipeline:

| Clip | Godot-schema output | Scope for kyu handout |
|---|---|---|
| **Katatedori Tenkan** | `katatetori_tenkan_demo/katatetori_tenkan_godot_schema.json` | **In scope** — confirmed against Johan's own 5Kyu.odt (exact name match) |
| **Jo-to-Jo paired kata** | `jobokken_demo/jo_to_jo_godot_schema.json` | **In scope** — confirmed against Johan's own 3Kyu.odt (exact name match) |
| Jonage | `jonage_demo/jonage_godot_schema.json` | Out of scope — Yondan-level, confirmed absent from all six kyu docs |
| Bokken Kumitachi 1 | `kumitachi_demo/bokken_kumitachi_godot_schema.json` | Out of scope — Shodan-level, confirmed absent from all six kyu docs |
| Kenko Taiso Hitori (solo, 18 min) | `kenkotaiso_demo/kenko_taiso_v2_godot_schema_resampled.json` (supersedes the original `kenko_taiso_godot_schema.json`) | Partially in scope (Kenko Taiso itself is Ki-exam material used across grades). Re-sampled around 25 real audio-detected pauses instead of blind time intervals — 9 well-separated, correctly-grouped blocks, still honestly unnamed pending transcription — see below |

The two in-scope clips are the real deliverables here — full Grepp/Kuzushi/Kake sequences with
corrected role data, real timing, and toitsu.de/Johan's-own-document cross-references. The other
three were useful for stress-testing the pipeline (and Bokken Kumitachi in particular had the
best MediaPipe detection rate of any two-person clip, since weapon kata never has body-to-body
overlap) but aren't handout material.

## Key corrections made during this session (worth remembering)

- **mediapipe version pin**: 0.10.14, not latest — see README, newer versions need a model
  download from a blocked domain.
- **Role labeling bug, found and fixed**: bounding boxes were originally labeled `tori`/`uke` by
  screen position (left/right), not by who actually grabs vs. performs. This produced a fully
  self-consistent but backwards dataset for Katatedori Tenkan — caught by re-watching the
  approach frame, confirmed uke initiates the grab (left side) and gets thrown, tori is on the
  right. All figure data in that file has been swapped to correct this. The other clips' role
  labels are flagged unverified rather than guessed at.
- **Weapon kata isn't tori/uke at all, but it isn't roleless either.** Jo-to-Jo and Bokken
  Kumitachi are paired weapons practice with their own correct terminology: **uchidachi**
  (打太刀, initiates the attack) and **shidachi** (仕太刀, receives/executes). Confirmed on the
  Jo-to-Jo footage (moderate confidence: left figure clearly winds up to strike first at the
  kata's opening) — role assignment for Bokken Kumitachi could not be confidently determined
  from the sampled stills and is left honestly unverified rather than guessed.
- **Occlusion pattern, confirmed on real footage across all clips**: MediaPipe detects both
  people reliably when they're screen-separated, and fails specifically at body-to-body overlap
  — which for a throw is usually the Kake/completion phase, exactly the moment that matters
  most for a technique's finishing image. Not a bug in these scripts; a known limit of
  monocular single-person pose models. Missing frames were filled by manual qualitative
  description grounded in technique mechanics, clearly flagged as such (not MediaPipe data).
- **Terminology resolved, not just flagged**: the Katatedori Tenkan clip's naming initially
  looked like it might conflict with toitsu.de's "Tenshin" variant — resolved by checking
  Johan's own 5Kyu.odt, which uses "Tenkan" too. Not an error; a dojo/lineage naming variant.

## Open items — genuinely blocked, need a human or a different environment

- **Kenko Taiso Hitori exercise names.** Upgraded the segment *boundaries* using
  `ffmpeg silencedetect` on the audio track (found 25 real pauses >2.5s, resampled around
  those instead of blind 40s intervals — see `kenko_taiso_v2_*` files and coverage_log.md for
  the methodology). This fixed *where* one exercise ends and another begins, confirmed by much
  cleaner visual groupings on review. It did NOT solve *what each exercise is called* — that
  needs actual speech content, not just pause timing, and speech-to-text isn't available in
  this sandbox (no model weights reachable on any allowed domain). **If you can run Whisper or
  similar locally on the audio and share a timestamped transcript, the 9 well-separated blocks
  already identified could be named properly** rather than left as honestly-unnamed visual
  clusters.
- **Second-side repetition** for Katatedori Tenkan was attempted and abandoned — see
  coverage_log.md. Doable, just needs a human eye on the source video to pick a clean timestamp
  rather than more thumbnail-guessing.

## Recommended next steps

1. If more grading-relevant footage exists for other 5th/4th/3rd kyu techniques not yet covered
   (the kyu docs list several beyond Katatedori Tenkan and the Jo-to-Jo kata — e.g. Katate
   Kosadori Kokyunage, Zagi Ryotedori Kokyunage for 5th kyu; Katatedori Ikkyo, Ushiro Ryotedori
   Zenponage for 4th kyu, which are also the Godot spec's own acceptance-test techniques), upload
   it and it can go through the same four-step pipeline.
2. Once there's a small library of Godot-schema sequence files like the two in-scope ones here,
   handing both the `godot_posing_machine_spec.md` build spec AND this pipeline's output to
   Claude Code together would let it validate the grip-attachment system design against real
   (if rough) pose data, rather than only against the spec's hypothetical worked examples.
3. The bone-direction-vector data in the Godot-schema files is explicitly NOT literal
   `bone.rotation` values (see script docstring) — whoever builds the Godot importer needs to
   do the actual rig-space conversion against the real Mixamo skeleton's bind pose.
