# Extraction run — 2026-09-06

Ran all five uploaded AOA2 clips through the pipeline. Summary below;
full draft JSON + source frames for each are in the matching subfolder.

| Clip | Type | Frames picked | Detection result |
|---|---|---|---|
| Katatedori Tenkan | 2-person grip throw | Grepp, Kuzushi, Kake | Grepp/Kuzushi both figures OK. Kake: tori missed (bodies fully overlapping at throw moment) |
| Jonage | 2-person, jo staff | Grepp, Kuzushi, Kake | Grepp/Kake both OK. Kuzushi: tori missed (blended/overlapping) |
| Jo to Jo paired kata | 2-person, weapon-to-weapon (no grip) | 4 positions across the kata | 3/4 positions full pair OK; 1 position both missed (raised-weapon pose confused detection) |
| Bokken Kumitachi 1 | 2-person, weapon-to-weapon (no grip) | 4 positions across the kata | 4/4 full pair OK — bodies stay well-separated left/right throughout, best hit rate of the two-person clips |
| Kenko Taiso Hitori | Solo warmup, ~18 min | 8 sampled exercises across the clip | 7/8 OK. 1 missed (forward bow with head down — unusual silhouette) |

## Pattern confirmed across all clips

Detection succeeds reliably whenever the two figures stay left/right-separated
in frame. It fails specifically at the moment of body-to-body contact/overlap
— which for throws is usually the Kake/completion phase, i.e. exactly the
most important frame for the handout. This isn't a bug in the scripts; it's
the known occlusion limit of monocular single-person pose models discussed
earlier. Two practical implications going forward:

1. For contact-heavy phases, expect to pose that frame from scratch in
   Godot rather than starting from MediaPipe numbers — budget for that
   rather than being surprised by it later.
2. The weapon-to-weapon kata (Jo/Jo, Bokken Kumitachi) had much better hit
   rates than the grip throws, because the partners' bodies never actually
   overlap — worth extracting more of these first, since they're the
   "easy mode" case for this pipeline and can validate the Godot import
   step while the harder grip techniques are being hand-posed anyway.

## Not yet processed

Kenko Taiso Hitori is ~18 minutes long; only 8 exercises were sampled as a
spot-check. The full clip almost certainly contains most/all of the
Hitoriwaza items named in the 5/4/3 kyu documents (Udefuri, Sayu, Tenkan,
Zengo, Happo, Funakogi, etc.) — worth a dedicated pass, going exercise by
exercise, once the grading document's Hitoriwaza list is being finalized.

## Update — toitsu.de cross-reference pass

Fetched toitsu.de's kyu syllabus (exams_aikidokyu_en.html) and terminology glossary (vocs_en.html)
and used them to improve the drafts:

- **Katatedori Tenkan**: filled in the missing Kake-phase tori pose manually (qualitative, from the
  frame + technique knowledge), and corrected the grip direction in `grip_attachment` — toitsu.de
  confirms *katatedori* means uke grabs tori's wrist, not the reverse. Also flagged a real naming
  discrepancy: the clip is titled "Tenkan" but toitsu.de's 5th kyu syllabus lists "Katatedori
  **Tenshin** Kokyunage" — tenkan and tenshin are different footwork terms per the glossary. Worth
  confirming which one this clip actually shows before it becomes reference material.
- **Jonage**: filled in the missing Kuzushi-phase tori pose. Flagged that Jonage isn't in toitsu.de's
  kyu syllabus at all — it's Yondan-level (Tsuzukiwaza 20) per the main exam document. Good pipeline
  validation footage, out of scope for the kyu handout itself.
- **Jo-to-Jo kata and Bokken Kumitachi**: corrected `grip_attachment` — these are weapon-to-weapon
  contact (toitsu.de: kumitachi = "practising sword with partner"), not hand grips. Godot's
  bone-grip-follow system probably doesn't apply directly; needs a weapon-contact-point approach
  instead.
- **Kenko Taiso Hitori**: walked back the original 8 phase labels, which were guessed from thumbnails
  without checking them against toitsu.de's actual 9-item Kenko Taiso list or the Hitoriwaza name
  list — several were likely wrong (e.g. "TorsoTwist" was probably just the instructor standing
  between exercises). Replaced with honest confidence-graded descriptions instead of confident
  wrong names.

**Bigger finding:** this clip has an audio track (AAC), which almost certainly has the instructor
naming/counting each exercise — that's the real fix for identifying which segment is which, far
better than guessing from still frames. Couldn't transcribe it here: speech-to-text tooling isn't
installed and the models all need weights from domains (huggingface.co, openaipublic storage) this
sandbox can't reach. If you can run Whisper (or similar) locally on the audio and share a transcript
with timestamps, that would let this whole clip be labeled properly instead of guessed at.

## Second-repetition attempt (Katatedori Tenkan) — inconclusive, abandoned

Tried extracting a second, later repetition (~55s into the clip) to get a mirrored-side data
point, since gradings typically expect both sides. The segment boundary picked from the coarse
1fps overview wasn't precise — the extracted window opens mid-throw (tail end of an earlier
rep already in progress), not at a clean approach/grab start. Rather than keep guessing at
timestamps, abandoned this rather than produce a shakily-labeled second rep. If a second-side
reference pose is wanted, the reliable way to get it is to open the source video in a normal
player, note the timestamp of a clean rep by eye, and extract from there — much faster than
guessing from thumbnails.

## Kenko Taiso re-pass — silence-detection-based resampling

Replaced the original blind-40s-interval sampling with a real structural signal: ran `ffmpeg
silencedetect` on the clip's audio track and found 25 pauses longer than 2.5s across the 18.5
minutes (vs. hundreds of short 0.6-1.5s pauses, which look like the instructor's counting
cadence within a held exercise, not transitions between exercises).

Extracted a frame just after each long pause and reviewed as a contact sheet — the grouping is
visibly much cleaner than the original 8 arbitrary samples: e.g. 10 of the 25 points (147-297s)
all show the same held arms-behind-head position, correctly reflecting that this is one exercise
photographed repeatedly across its counted repetitions, not 10 different exercises. Consolidated
into 9 representative points across 7 visually distinct blocks (some blocks span multiple pause
points, kept as one representative each; block 7's three points may or may not be the same
exercise -- not visually conclusive, kept separate rather than guessed together).

New files: `kenko_taiso_v2_draft_resampled.json`, `kenko_taiso_v2_godot_schema_resampled.json`.
Real transition timing included (measured from actual timestamps, not guessed).

**Still unresolved:** exercise names. This pass fixes *where* the boundaries are, not *what* is
being named at each one -- that's still blocked on speech-to-text (see PROJECT_STATUS.md). But
"9 real, well-separated blocks with correct groupings, honestly unnamed" is meaningfully more
usable than "8 arbitrary samples with guessed labels," so treating this as the current best
version of the Kenko Taiso data rather than a replacement that needs the same caveats repeated.

## Terminology correction — uchidachi/shidachi, not partner_a/partner_b

Following up on the tori/uke role-labeling fix: for the two paired-weapons kata (Jo-to-Jo,
Bokken Kumitachi), the earlier "neutral" partner_a/partner_b relabeling undersold it — there IS
a real, named role structure for kata, just a different one than throwing techniques. Confirmed:
uchidachi (打太刀, initiates the attack, traditionally the senior/teaching role) and shidachi
(仕太刀, receives and executes the technique). Renamed accordingly in both kata files. Assignment
(which screen-position crop is which) remains unverified, flagged the same way tori/uke was
before the fix.

## Perfecting pass — fixed real gaps found on QA review

1. **Katatedori Tenkan Kake grip_attachment was never actually filled in** — still had the
   original step-3 placeholder despite earlier claims of being "handled." Zoomed into the hand
   region: grip does NOT look maintained through the throw (tori's hand appears to move toward
   uke's head/shoulder, uke's hand looks open) — written up as a genuine either/or with both
   readings explained, not forced to one answer.

2. **Jonage had the SAME tori/uke role bug as Katatedori Tenkan** — missed on the first pass
   despite fixing the identical issue on the other clip. Re-checked: the jo is wielded by the
   LEFT figure (uke, attacker), thrown by the RIGHT figure (tori) — confirmed at both the
   strike (frame ~31) and the throw completion (frame ~41). Swapped all figure data to correct.

3. **Added fallback-retry to `02_extract_pose.py`** — default confidence (0.4) was leaving
   genuinely-visible people undetected (confirmed: Jo-to-Jo Position_B, both figures clearly
   visible, unoccluded, just missed). Now retries at 0.25 and 0.15 before giving up, and flags
   which confidence level was actually used. Recovered: Jonage's Kuzushi gap entirely (now real
   data, manual estimate no longer needed), Jo-to-Jo's Position_D tori. Position_B (Jo-to-Jo)
   still fails at all three levels even directly cropped — likely the crop boundary itself
   cutting the figure awkwardly, not just a confidence issue; filled manually instead, with the
   likely cause noted.

4. **uchidachi/shidachi role verification attempted** on both weapon kata: Jo-to-Jo got a
   moderate-confidence positive read (left figure clearly winds up to strike first). Bokken
   Kumitachi: checked, genuinely couldn't tell from the sampled stills, left honestly unverified.

5. **Kenko Taiso v1 explicitly marked superseded** by the v2 (audio-pause-based) resample,
   rather than leaving two versions of ambiguous relative quality sitting side by side.

Net effect: Katatedori Tenkan and Jonage (the two in-scope files) are now as complete and
internally consistent as this pipeline can make them without new footage or human verification
against the source video at full resolution.

## Hakama caveat added across all files

Person asked about gi/clothing. Two separate answers:
- Godot tool itself: non-issue, spec explicitly calls for gi-less mannequins (clothing sim is
  out of scope, section 2.2).
- This pipeline's leg data: real accuracy concern, NOT caught by existing confidence flagging.
  Checked arm vs leg low-confidence rates (26% legs vs 35% arms) -- doesn't show legs as worse,
  but that's likely a false reassurance: MediaPipe confidently fits to the hakama's fabric
  silhouette, not the actual leg underneath, so a joint can look "confident" while still being
  wrong. Added a standing hakama_caveat field to all 12 pose files recommending arm data be
  trusted more than leg data, and source frames be checked directly for stance/foot position
  rather than relying on numeric leg angles.
