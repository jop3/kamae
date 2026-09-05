# Aikido Posing Machine — Build Specification

**Status:** Draft v1 — ready for implementation planning
**Target engine:** Godot 4.6+ (requires the `SkeletonModifier3D` / `TwoBoneIK3D` IK stack introduced in 4.6)
**Audience for this document:** an engineering agent (Claude Code) building the tool from scratch
**Owner / domain expert:** the person commissioning this — a Ki-Aikido instructor documenting grading techniques for children, who will be the primary user and QA tester of the finished tool

---

## 1. Background and purpose

We are building reference material (a printable handout, currently in Word/docx) that teaches children the Aikido techniques required for their 5th, 4th, and 3rd kyu grading exams (Ki-Aikido, Ki no Kenkyukai / Yoshigasaki lineage). Each technique currently has a short text description and an abstract flowchart-style diagram. Both were judged **not detailed enough**: they describe *that* something happens but not exactly *how two bodies are positioned and moving in space* — grip location, body orientation, footwork, and the shape of the throw or pin.

Photographs from a real dojo are not usable for a general, redistributable handout (identifiable people, inconsistent lighting/angles, no ability to add clean annotation). We need a way to generate **our own clean, consistent, annotatable images and short video clips of two neutral human figures performing each technique**, posed accurately by the domain expert (not auto-generated or guessed by an AI).

This is why we're building a small internal tool — not a game — that lets the instructor:

1. Load two humanoid figures ("Tori", the person performing the technique, and "Uke", the person attacking / being thrown).
2. Pose each figure's whole body, including individual fingers, by hand, with IK assistance for natural-looking limb movement.
3. Ensure that when Tori grips part of Uke (or vice versa), that grip point stays physically attached as either figure moves — this is the single hardest and most important feature, because nearly every Aikido technique starts with a grab.
4. Save a pose as a named keyframe (e.g. "Katatedori Ikkyo — Kake").
5. Sequence several keyframes for one technique and preview/export the interpolated motion between them.
6. Export a clean still image (transparent or plain background) per keyframe, and/or a short rendered video of the full sequence.

The tool's users are: the instructor (primary), and potentially this Claude Code agent as it's being built and tested. It is **not** intended for distribution to end users (parents/children) — it's an authoring tool, like a lightweight stop-motion camera, not a training app.

---

## 2. Scope

### 2.1 In scope
- A Godot 4.6+ project, runnable both in the editor and as a standalone build, that presents a 3D scene with two rigged humanoid characters and a custom in-app posing UI (not reliant on the Godot editor's own gizmos, since the end user should not need to open or understand the Godot editor to use the finished tool).
- Full-body posing of both characters via FK (forward kinematics — direct bone rotation) for the spine, head, and legs, and IK (inverse kinematics, using Godot 4.6's `TwoBoneIK3D`) for arms reaching to a target, including reaching to grip a specific point on the other character.
- Individual finger posing (at minimum: a simple open/closed curl control per finger, per hand; see §5.4 for the fidelity bar).
- A "grip attachment" system: the ability to designate that Tori's hand (or Uke's hand) is gripping a specific bone/point on the other character, after which that hand's IK target automatically follows that point if the gripped limb moves.
- A pose library: named, savable, loadable poses (full state of both skeletons + camera + grip attachments).
- A technique sequence system: an ordered list of poses (by name) that can be previewed as an interpolated animation and exported as a short video.
- Still image export (per single pose) and video export (per sequence), see §6.
- A small number of camera presets (see §5.6) plus free orbit/zoom for manual framing.
- The three worked test cases in §8, fully built out as saved technique sequences, used as acceptance tests for the whole tool.

### 2.2 Out of scope (explicitly do not build)
- Any physics simulation of the throw itself (no ragdoll, no rigid-body contact resolution). All motion is authored by hand, pose to pose.
- Automatic or AI-assisted pose generation from text/video ("generate the pose for X technique"). The instructor poses everything manually; the tool only assists with IK and grip-following.
- Motion capture input of any kind.
- Clothing/gi simulation (cloth physics). A plain, low-poly humanoid body is sufficient — see §5.1.
- Multiplayer, networking, or any cloud component. Fully local, single-user, offline tool.
- Mobile or web export. Desktop (Linux/Windows/macOS, whichever Godot supports out of the box) only.
- A "correctness checker" that validates whether a pose is biomechanically valid Aikido — the instructor is the sole judge of correctness. The tool's job is to let them realize what they already know how to do, not to know Aikido itself.

---

## 3. Key design decisions already made

These were decided in prior discussion and should be treated as constraints, not open questions:

- **Engine:** Godot, not Blender. Rationale: the instructor wants a reusable *interactive* tool they (or others) can open and pose in directly, not a one-off authoring pipeline requiring 3D-software expertise.
- **Base character rig:** Use Mixamo's stock rigged characters (e.g. "X Bot" / "Y Bot") rather than a custom mesh run through an auto-rigger. Mixamo's own stock characters ship with a complete, clean per-finger skeleton already built in. Custom meshes run through Mixamo's auto-rigger are known to frequently produce broken/missing finger bones because closely-spaced fingers confuse its auto-detection — we are deliberately avoiding that failure mode by not going through auto-rigging at all.
- **IK approach:** Godot 4.6's new `SkeletonModifier3D`-based IK stack (specifically `TwoBoneIK3D` for arm/leg reaching). Earlier Godot IK (`SkeletonIK3D`) is deprecated and should not be used. If for any reason the build environment is pinned to an earlier Godot version, stop and flag this back rather than silently falling back to a weaker/deprecated IK path.
- **Export mechanism:** Godot's built-in Movie Maker mode for video (deterministic, frame-perfect, no dropped frames — this is a real advantage over screen-capture tools for our case since we care about clean, repeatable output, not real-time capture) and a viewport screenshot for stills.
- **Two-body grip is the hard, must-solve problem.** Everything else in this spec is in service of getting that one mechanic right. See §5.3 for the detailed design.

---

## 4. Non-negotiable UX principle

**The instructor is not a 3D artist or a programmer.** Every interaction in the finished tool must be doable with mouse + a small number of clearly-labeled on-screen controls, without reading Godot documentation or understanding bones/skeletons/nodes conceptually. Concretely:

- No requirement to ever open the Godot editor to use the finished tool day-to-day (only to build/modify it).
- Bone selection should work by **clicking on the body part in the 3D view**, not by picking a bone name from a technical list (a technical list can exist as a secondary/advanced option, but click-to-select is the primary interaction).
- Rotating a selected joint should work via an on-screen gizmo (visual, mouse-draggable), with the option of numeric sliders for fine adjustment — not by typing rotation values as the only option.
- All destructive actions (deleting a saved pose, overwriting a technique sequence) require a confirmation step.

---

## 5. Functional requirements in detail

### 5.1 Characters
- Two independent character instances in the scene at all times, referred to internally as `Tori` and `Uke`. Visually distinguish them (e.g. different flat shading color — teal for Tori, amber for Uke — matching the color scheme already used in the existing handout's diagrams, for visual continuity when these renders eventually sit next to the diagrams).
- Plain, low-poly, gi-less humanoid mesh (a bald, featureless mannequin is fine and arguably preferable — no clothing, no face detail, nothing that reads as a specific identifiable person or gender). If the Mixamo stock character's default appearance is too detailed/branded-looking, a simple flat-shaded recolor is an acceptable and expected modification.
- Both characters must load with the same skeleton structure so that pose data (see §5.5) is interchangeable between them if ever needed (e.g. mirroring a pose from Tori to Uke).

### 5.2 Posing — body
- Every major joint (spine, neck/head, shoulders, elbows, hips, knees, ankles) must be selectable and rotatable.
- Arms: default to IK mode (drag a hand target in 3D space; the shoulder/elbow solve naturally via `TwoBoneIK3D`). Provide a toggle to switch a given arm to FK (direct rotation of shoulder/elbow/wrist independently) for cases where IK produces an awkward pose the instructor wants to hand-correct.
- Legs: same IK/FK toggle, using `TwoBoneIK3D` for hip/knee/ankle.
- Spine/torso and head: FK only (a chain of a small number of rotatable segments is sufficient — full per-vertebra articulation is not needed).
- Provide an undo/redo stack for pose edits within a session (does not need to persist across app restarts).

### 5.3 Posing — grip attachment (the critical feature)
This is the mechanic that makes the tool actually useful for Aikido specifically, so it gets its own detailed spec.

**Concept:** In real technique, one person's hand (or both hands) stay locked onto a specific point on the other person's body (wrist, shoulder, lapel, etc.) through the whole technique, even as both bodies move and rotate. We need to author that once, then move bodies freely afterward and have the grip visually hold.

**Required behavior:**
1. The instructor can select a bone on one character (e.g. Uke's right forearm, near the wrist) as an "attachment point."
2. The instructor can then select a hand on the other character (e.g. Tori's right hand) and "attach" it to that point.
3. Once attached, that hand's IK target is driven by the attachment point's world transform every frame — i.e., if Uke's arm moves, Tori's gripping hand moves with it automatically, maintaining the grip, without the instructor having to re-pose Tori's hand at every keyframe.
4. The instructor can detach a grip at any point (e.g. mid-technique, when the throw releases) and resume manually posing that hand freely.
5. Multiple simultaneous attachments must be supported (e.g. both of Uke's hands gripping both of Tori's wrists, as in `Ushiro Ryotedori Zenponage` — see test case in §8.2).
6. Attachments must be stored as part of a saved pose (§5.5) — i.e., "this pose has Tori's right hand attached to Uke's right wrist" is itself saved data, not just a transient editor state.

**Suggested implementation approach** (the agent should validate/refine this, not treat it as gospel): use a `BoneAttachment3D` node parented under the "gripped" bone on the source skeleton to expose a stable world-space transform for that point; the "gripping" hand's `TwoBoneIK3D` target node then has its global transform continuously set (via script, each `_process`/`_physics_process` tick, or via the modifier stack ordering) to match that `BoneAttachment3D`'s global transform. Confirm this is compatible with Godot 4.6's `SkeletonModifier3D` execution order (modifiers run in a defined per-frame order; make sure the attachment-follow logic runs before the IK solve consumes the target position, not after).

### 5.4 Posing — fingers
- Fidelity bar: **not** full per-phalanx IK. A simple **curl slider per finger** (thumb, index, middle, ring, pinky), 0 (fully open/flat) to 1 (fully closed/fist), driving all phalanx joints of that finger proportionally, is sufficient. This matches the actual need: showing "hand grips wrist" vs. "hand is open/flat for a strike," not photorealistic hand acting.
- Both hands need independent finger controls.
- If time/complexity allows, a "grip preset" button (sets a natural-looking grasping curl across all fingers in one click) is a nice-to-have, not a requirement.

### 5.5 Pose and sequence data model
- **Pose:** a named, savable unit containing: full bone-rotation state for both skeletons (including finger curls), any active grip attachments (which bone attached to which, on which character), and optionally a saved camera transform. Suggest storing as a Godot `Resource` (`.tres`) for editor-friendliness, or plain JSON if the agent judges that simpler to implement/debug — agent's choice, but must be human-readable enough to diff/inspect in a text editor for debugging.
- **Technique sequence:** a named, ordered list of pose references, each with a "hold/transition duration" (how long to interpolate into that pose from the previous one, and optionally how long to hold before moving to the next). E.g. `Katatedori Ikkyo = [Grepp (hold 0.5s), Kuzushi (transition 0.6s, hold 0.3s), Kake (transition 0.6s, hold 1.0s)]`.
- Naming convention: reuse the exact Swedish phase names already established for the handout — **Grepp**, **Kuzushi**, **Kake** — as the standard 3-phase structure per technique, matching the "phase name upgrade" already agreed for the written material. Not every technique will cleanly fit exactly 3 phases; the data model must support 2–5 poses per sequence, but 3 (Grepp/Kuzushi/Kake) is the expected default and should be the pre-filled suggestion in the UI when creating a new technique sequence.
- All poses and sequences must persist to disk (local files) and reload correctly on next app launch.

### 5.6 Camera
- Free orbit/pan/zoom via mouse, at all times.
- At least two one-click presets: **"Front"** (camera on the line uke→tori, i.e. how a photo in the existing dojo grading photos is framed — see the reference images already in the project, e.g. the 7:e Kyu / 9:e Kyu sheets) and **"Side"** (camera perpendicular to that line — closer to how classic printed Aikido manuals like Shioda's frame technique photos, showing body rotation and footwork more clearly than a front view does).
- Camera transform is saveable per-pose (§5.5) so a technique sequence can also carry a small camera move if desired, but a fixed camera for the whole sequence must also be supported (default behavior) — don't force the instructor to set a camera per pose if they just want one static shot.

### 5.7 Export
- **Still image:** export the current view as a PNG. Background must be either a plain flat color or transparent (instructor's choice via a setting) so the image can be dropped directly into the Word document without a distracting background.
- **Video:** export the current technique sequence (interpolated per §5.5 durations) as a video file via Movie Maker mode. Reasonable defaults: 1080p, 30fps, H.264/MJPEG (whichever Movie Maker supports natively — do not add a third-party video encoding dependency). Output should also, ideally, be able to render each keyframe as a still automatically as a side effect of building a sequence (so the instructor doesn't have to separately re-export each pose that's already part of a sequence) — nice-to-have, not required for v1.
- Exported filenames should be predictable and derived from the pose/sequence name (e.g. `katatedori_ikkyo_grepp.png`, `katatedori_ikkyo.mp4`), not generic/timestamped, so they drop cleanly into the existing docx-generation pipeline used for the handout.

---

## 6. Non-functional requirements
- Must run on a normal laptop without a dedicated GPU at usable interactive framerates (this is a two-character, low-poly scene — should not be demanding).
- Startup to "ready to pose" should be a few seconds, not a long load.
- No internet connection required at runtime (all assets local).
- Godot version pinned and documented in the project README (target: 4.6.x). If a newer Godot minor version breaks the IK APIs used, that's a maintenance issue to flag, not silently work around.

---

## 7. Suggested build order (milestones)

Structured so that each milestone produces something demonstrably testable, and the hardest risk (grip attachment) is tackled early rather than last.

1. **M1 — Single character, manual pose, still export.** One Mixamo stock character loaded, full FK posing of body via click-to-select + gizmo, PNG export of current view. No IK yet, no fingers, no second character. *Goal: prove the basic posing loop works end to end.*
2. **M2 — IK arms/legs + finger curls.** Add `TwoBoneIK3D` for arms and legs with FK toggle; add per-finger curl sliders. Still single character.
3. **M3 — Second character + grip attachment.** Add Uke. Build the `BoneAttachment3D`-driven grip-follow system from §5.3. This is the highest-risk milestone — budget the most time/investigation here, and validate against at least the `Katatedori Ikkyo` grip (§8.1) before moving on.
4. **M4 — Pose save/load.** Implement the data model from §5.5 for single poses (no sequencing yet). Confirm a saved pose reloads bit-for-bit identical (including grip attachment state).
5. **M5 — Sequencing + interpolated preview + video export.** Build technique sequences, interpolate between saved poses, preview in-app, export via Movie Maker.
6. **M6 — Camera presets + background/export polish.** Front/Side presets, transparent/flat background export option, filename conventions.
7. **M7 — Acceptance pass on all three test cases (§8).** Build out all three worked techniques fully, export their stills and video, and check them against the acceptance criteria listed for each.

Do not skip ahead to M5+ polish while M3 (grip attachment) is still shaky — it is the load-bearing feature of the whole tool.

---

## 8. Worked test cases

These three techniques are drawn from the real grading syllabus (5th/4th/3rd kyu, Ki-Aikido / Ki no Kenkyukai lineage) and are chosen to exercise different parts of the system: a simple front grip-and-pin, a from-behind two-hand grip-and-throw, and a full-body rotational throw. Build all three as real, saved technique sequences and use them as the acceptance test for the whole tool — if these three can be posed, saved, sequenced, and exported cleanly, the tool is fit for purpose.

### 8.1 Test case 1 — Katatedori Ikkyo (4th kyu)
*Chosen because: simplest case, single grip, tests the core grip-attachment mechanic in isolation.*

**Setup:** Tori and Uke stand facing each other, roughly one arm's length apart, both in a natural standing stance (feet shoulder-width, weight even).

**Grip:** Uke's right hand grips Tori's right wrist, from above (Uke's palm down over Tori's forearm, thumb and fingers wrapping the wrist).

**Phase — Grepp** (starting pose):
- Both figures standing upright, facing each other squarely.
- Uke's right arm extended forward, gripping Tori's right wrist as described above.
- Tori's right arm relaxed/extended toward Uke, being held. Tori's left arm neutral at the side.

**Phase — Kuzushi** (entering / balance-break):
- Tori steps forward-in with the same-side foot (right foot forward, closing distance), rotating the torso slightly.
- Tori's right hand (still gripped by Uke) rises to roughly shoulder height, leading Uke's captured arm upward and forward, breaking Uke's balance upward/forward.
- Uke's posture shows the balance break: weight forward onto the toes/forward foot, torso tipping slightly forward, head/gaze drawn upward following the captured arm. Uke's grip on Tori's wrist remains attached throughout (grip-follow system must keep this visually correct as both bodies move).
- Tori's left hand comes up to support/control near Uke's captured elbow (does not need its own grip-attachment to a bone — a manually posed FK position near the elbow is sufficient, no attachment mechanic required here since this is a support/guide contact, not a fixed grip).

**Phase — Kake** (finish / pin):
- Uke is lowered to the ground, face-down, with the captured (right) arm extended straight and pinned along the ground, elbow locked straight, hand near Uke's own head.
- Tori kneels or stands over Uke's extended arm maintaining control at wrist and near the elbow, right arm/wrist grip from Uke still attached per §5.3 (Uke is still nominally "gripping" — in real technique the grip may release here, but for this reference pose keep it attached unless the instructor decides otherwise when actually posing it).
- Tori's posture is stable and low, weight settled, not leaning or off-balance.

**Acceptance criteria:**
- The grip point (Uke's hand on Tori's wrist) visibly and continuously tracks Tori's wrist across all three phases without manual re-adjustment of Uke's hand position between phases — i.e., moving/saving Tori's arm pose alone should be enough to keep the grip visually correct.
- Uke's captured arm is fully straight (locked elbow) in the Kake phase.
- Exported stills for all three phases are clean (no clipping/intersecting geometry at the grip point) and a 3-phase video plays as one continuous, readable motion at the durations specified in §5.5's example.

### 8.2 Test case 2 — Ushiro Ryotedori Zenponage (4th kyu)
*Chosen because: attack from behind, two simultaneous grip attachments, tests multi-grip support and behind-the-body posing/camera framing.*

**Setup:** Tori stands facing away from Uke (Uke approaches and stands directly behind Tori).

**Grip:** Uke's both hands grip both of Tori's wrists from behind (Uke's right hand on Tori's right wrist, Uke's left hand on Tori's left wrist) — **two simultaneous grip attachments**, both active at once.

**Phase — Grepp:**
- Uke stands close behind Tori, both hands gripping both of Tori's wrists as described. Tori's arms are down/relaxed at the sides (being held from behind), Tori facing forward, Uke facing Tori's back.

**Phase — Kuzushi:**
- Tori raises both arms upward and outward (like raising antlers — the mental image already used in the written handout for this technique), which — because Uke's grip is attached — drags Uke's arms upward too, breaking Uke's balance forward onto the toes and pulling Uke's torso in close behind/against Tori.
- Tori's stance widens/lowers slightly for a stable base as the arms rise.

**Phase — Kake:**
- Tori continues the arm-raise into a forward throwing motion, rotating Tori's torso and driving both arms forward and down, throwing Uke forward over/past Tori's shoulder line.
- Uke's pose shows the throw in progress or just completing: body pitched forward past horizontal, feet leaving/having left the ground is acceptable to depict as a mid-air moment (do not attempt to depict Uke's ukemi/landing roll — that's a separate breakfall technique, out of scope for this sequence).
- Both grip attachments may be released at this phase if the instructor judges that's the correct moment (in real technique the throw releases the grip); if kept attached, the grip-follow system must still resolve to a physically plausible (non-glitching) hand position given how far Uke has moved — flag to the instructor if this produces visibly broken IK stretching, since that's a legitimate case for manual grip release rather than a bug to silently mask.

**Acceptance criteria:**
- Both of Uke's hand attachments track their respective Tori wrists correctly and independently through Grepp and Kuzushi (i.e., the system supports ≥2 concurrent attachments between the same pair of characters without interference).
- Camera default for this technique should be the **Side** preset (§5.6) — a Front view would have Uke mostly hidden behind Tori for the Grepp/Kuzushi phases, which is not useful for the handout.
- The "from behind" starting arrangement is achievable through the normal posing UI without special-casing — i.e., positioning Uke behind Tori is just normal whole-body/root positioning, not a separate code path.

### 8.3 Test case 3 — Katatedori Shihonage, Irimi version (3rd kyu)
*Chosen because: large range of motion, full ~180° body rotation of Tori, tests whether the grip-attachment system remains stable through a large, fast rotational move (the "four-direction throw").*

**Setup:** Tori and Uke face each other, similar starting distance to test case 1.

**Grip:** Uke's right hand grips Tori's right wrist (single grip, same style as test case 1 — reuse the same attachment approach, different subsequent motion).

**Phase — Grepp:** Same starting arrangement as 8.1's Grepp phase (facing, single wrist grip) — this pose can plausibly be shared/copied from test case 1 as a starting point, which is itself a useful validation that pose data is reusable/composable.

**Phase — Kuzushi (entering under the arm):**
- Tori steps forward and turns the captured arm/wrist so that Tori's own arm and body pass under/across the gripped arm, ending with Tori standing beside/slightly in front of Uke, both now roughly facing the same general direction, Uke's captured arm raised alongside Uke's own head.
- This is the "irimi" (entering) version specifically — Tori's entry step goes forward past Uke's side, not backward/turning away (that would be the alternative "tenshin" version, not this test case).

**Phase — Kake (the four-direction turn and throw):**
- Tori rotates a full half-turn (~180°) while keeping hold of Uke's wrist/hand with Tori's own two hands (both of Tori's hands now on Uke's one wrist/hand — grip direction has flipped from "Uke grips Tori" in Grepp to "Tori grips Uke" by this phase, since Shihonage ends with Tori controlling Uke's arm, not the reverse). **This means the grip-attachment direction itself changes partway through the sequence** — Grepp/Kuzushi have Uke's hand attached to Tori's wrist bone; Kake should instead have (one or both of) Tori's hands attached to Uke's wrist/hand bone. The data model and UI must support a grip attachment being added, removed, or having its direction reversed at different poses within the same sequence, not just a single fixed attachment for the whole technique.
- The rotation ends with Uke thrown/lowered to the ground on their back, arm extended overhead, Tori standing over Uke maintaining the wrist/hand control, having completed the turn.

**Acceptance criteria:**
- The tool supports changing which character's hand is attached to which bone at different points within a single saved sequence (not just once per whole technique) — this is the specific new capability this test case is validating that 8.1/8.2 don't require.
- Tori's ~180° rotation between Kuzushi and Kake interpolates as a plausible turning motion when previewed/exported as video (does not need to be biomechanically perfect — the instructor will hand-adjust intermediate poses if the straight interpolation looks bad — but it should not produce nonsensical results like limbs passing through the torso in an obviously broken way for the whole duration).
- Final Kake pose has Uke's whole body on the ground (back), arm extended overhead, distinctly different footprint/floor-contact from test cases 1 and 2's Kake poses — confirming the tool isn't implicitly assuming every technique ends in the same generic "pin" shape.

---

## 9. Open questions for the instructor (do not guess — ask)

The implementing agent should surface these back rather than silently deciding, since they affect the tool's usefulness for its actual purpose:

1. Should exported stills default to transparent background or a plain flat color? (Affects §5.7.) Plain color is simpler to implement and preview reliably; transparent is more flexible for the docx pipeline but harder to get artifact-free at mesh edges.
2. For techniques where grip direction changes mid-sequence (test case 8.3), is it acceptable for the instructor to manually add/remove attachments at each affected pose (i.e., a slightly manual workflow), or is an automatic "detect and suggest" affordance actually expected? (The spec as written assumes manual is fine — this should be confirmed, not assumed to need automation.)
3. Confirm the target Godot version available in the actual build/runtime environment before starting — this entire IK approach depends on 4.6's modifier stack existing.
4. Should the finished tool be a one-off local build for the instructor's own machine, or does it need to be packaged/documented well enough for another instructor at a different Ki-Aikido club to install and use independently? (Affects how much onboarding/README polish is warranted.)

---

## 10. Reference material already produced (for context, not for the agent to re-derive)

The following existing artifacts describe the same techniques in text/simple-diagram form and should be treated as the source of truth for technique names, phase naming (Grepp/Kuzushi/Kake), and pedagogical intent — the posing tool is producing *visual* material to sit alongside this, not replacing or reinterpreting it:

- A Swedish-language printable grading handout (Word document) covering all 5th/4th/3rd kyu Hitoriwaza and Kumiwaza, including the three test-case techniques above, each with a "vanligt misstag" (common mistake) note.
- The official 2016 Ki-Aikido examination criteria document (technique names and grade groupings).
- A Swedish-language description sheet of Hitoriwaza (solo exercises).

If useful during implementation, ask the instructor for these directly rather than assuming their content.
