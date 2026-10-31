# Technique scripts

A technique is a JSON file in `techniques/`: who is in it, how they are dressed, and a list of
**phases**. Each phase is a list of **moves**, and ends in a saved pose; the phases in order are
the sequence that becomes the video. `src/posing/TechniqueScript.gd` runs the moves through the
same staging, grip, stance and fall code the hand-built techniques use, so a step, a grip or a
roll is the same wherever it is asked for.

```sh
GODOT=/path/to/godot tools/technique.sh techniques/katatedori_tenkan.json            # build + stills + video
GODOT=... tools/technique.sh techniques/katatedori_tenkan.json --no-video            # build + stills only
SKIP_BUILD=1 REF_VIDEO=clip.mp4 GODOT=... tools/technique.sh techniques/x.json --no-video   # compare with a video
```

Everything lands in `techniques/build/<slug>/` (not committed):

| File | What it is |
|---|---|
| `poses/*.json`, `sequences/<slug>.json` | the technique, loadable in the tool (copy into `poses/` and `sequences/` to keep it there) |
| `report.json` | per phase: the pose file, what the joints refused, any body through another, the worst grip error |
| `stills/<slug>_<phase>_{front,side}.png` | 1920×1080 stills per phase |
| `contact_sheet.png` | every phase, Front beside Side, in order — the one image to look at |
| `<slug>.mp4` | the video, 30 fps |
| `compare_with_video.png` | with `REF_VIDEO`: each phase's frame from the source video beside the render |

The build prints, after each phase, what the anatomy checks found. Read it: a wrist "past" its
range or a limb "through" a body is usually a move placed a little wrong, not a limit of the tool.

## Conventions

- **Directions are in a figure's own frame**: `[right, up, forward]` metres, or `[right, forward]`
  on the mat. Never the engine's axes (the engine's x runs to a figure's *left*).
- **Turns** are degrees, positive **counter-clockwise seen from above**, i.e. toward the
  figure's *left*. A turn to the right is negative.
- **Parts** are written `who.Part`: `tori.Right` (a hand or a foot, by side), `uke1.LeftLowerArm`
  (a bone). Bones: `Hips Spine Chest UpperChest Neck Head`, and per side
  `Shoulder UpperArm LowerArm Hand UpperLeg LowerLeg Foot Toes` with `Left`/`Right` in front.
  `along` on a grip is where on the bone the hand reaches for: 0 the bone's own joint (the
  elbow, for `LowerArm`), 1 its child's (the wrist); the hand then wraps the bone at the
  nearest point. A wrist grip is `LowerArm` at about 0.85.
- A character at yaw 0 faces +z. `tori` and `uke1` exist unless `characters` says otherwise.

## The file

```json
{
  "name": "Katatedori Tenkan",
  "description": "what the technique is, in words — the source the moves were written from",
  "source": "where it came from (a video and times, a book, an instructor)",
  "camera": "Side",                       // "Side" | "Front" | "per_pose"
  "view": {"yaw": 180, "height": 1.7, "zoom": 0.9},   // optional: see below
  "characters": [                         // optional; this is the default
    {"id": "tori", "name": "Tori", "role": "Tori", "gi": true, "hakama": true,
     "appearance": {"skin": "middleage_caucasian_male", "hair": "short02", "eyes": "grey"}},
    {"id": "uke1", "name": "Uke", "role": "Uke", "gi": true}
  ],
  "phases": [
    {"name": "Grepp", "hold": 0.5, "do": [ {"attack": "katatedori"} ]},
    {"name": "Tenkan", "transition": 0.8, "hold": 1.0, "ref": 11.5, "do": [ ... ]}
  ]
}
```

`view` chooses the camera the video is filmed from, and adds a third still per phase
(`*_view.png`, used by the contact sheet and the video comparison in place of Side): `yaw`
degrees swung from the Side view (positive counter-clockwise from above; 180 is the Side view
from the other side), `height` of the camera in metres (1.4 by default), `zoom` above 1 closer.
To match a clip, turn it until the two stand on the same sides of the picture as in the clip,
and raise it as high as the clip's camera.

Phase keys: `name` (the pose is "<technique> <name>"), `do` (the moves), `transition` (seconds of
blend into this pose, default 0.7), `hold` (seconds held, default 0.3), `allow_short` (keep a
gripping hand short of its point rather than walking the gripper in — a throw where the grip is
coming off), `save: false` (an intermediate step whose moves carry into the next phase), `ref`
(seconds into the source video this phase matches, for the comparison).

Appearance: `look` `realistic` | `mannequin` (flat identification colour); `skin`
`middleage_caucasian_male young_caucasian_male old_caucasian_male young_asian_male
middleage_asian_male young_african_male young_caucasian_female middleage_asian_female`; `hair`
`short02 short04 short01 ponytail01 bob02 none`; `hair_color` `#rrggbb` (a tint); `eyes`
`brown blue grey green`. `color` sets the identification colour (belt, panel swatch).

## Moves

### Starting

| Move | Does |
|---|---|
| `{"attack": "katatedori", "mirror": false}` | Sets up an attack from the catalogue (`data/attacks.json`, `docs/attacks.md`): Tori in hanmi offering what is taken, Uke placed where his joints can make the grip. Keys: `katatedori aihanmi_katatedori ryotedori morotedori katadori ryokatadori munedori eridori sodedori hijidori katadori_menuchi ushiro_ryotedori ushiro_ryokatadori ushiro_eridori ushiro_kubishime shomenuchi yokomenuchi chudan_tsuki jodan_tsuki tanto_tsuki mae_geri`. `mirror` swaps sides. |
| `{"from_pose": "Katatedori Ikkyo Grepp"}` | Starts from a committed pose (a name in `poses/`, or a path). |

### Where the bodies are

| Move | Does |
|---|---|
| `{"place": "tori", "of": "uke1", "at": [right, forward], "facing": 180}` | Puts a figure relative to another (`"of": "attack"` = where the attack left Uke). `facing` is degrees from that figure's facing: 0 the same way, 180 face to face. Optional `height`, `pitch` (lean forward), `roll`. Without `of`: `"at": [x, z]` in the world and `"yaw"`. |
| `{"move": "tori", "by": [right, forward], "turn": 0}` | Moves the whole figure, feet and all, in its own frame (a slide, being led). |
| `{"step": "tori.Right", "by": [right, forward]}` | One foot steps; the hips follow to between the feet (`weight` 0…1, default 0.5, how far onto the stepping foot). `turn` turns the stepping foot, `body_turn` the body. **Irimi.** |
| `{"step": "tori.Right", "to": "uke1.LeftFoot", "offset": [right, forward]}` | Steps to a place on someone else, offset in *their* frame — "beside Uke's front foot". |
| `{"pivot": "tori", "foot": "Right", "deg": 180}` | Turns the body about one planted foot, which turns on its ball with the body. **Tenkan** (180), **tai no henko**, kaiten. |
| `{"turn_foot": "tori.Left", "deg": 30}` | Turns one foot out (+) or in on the spot. |
| `{"hanmi": "tori", "front": "Left", "depth": 0.32, "width": 0.16, "drop": 0.06}` | A hanmi stance on the spot, knees bent by dropping the hips. |
| `{"drop_hips": "tori", "m": 0.08}` | Lowers the hips with the feet left on the mat (bends the knees). |
| `{"kneel": "tori", "kind": "seiza"}` | Kneels: `seiza` (on the insteps) or `kiza` (on the toes). Suwari waza; getting up from ukemi. |
| `{"stand": "tori"}` | Back to standing at rest, upright, limbs at rest. |
| `{"lean": "uke1", "forward": 20, "side": 0}` | Tips the whole body about the feet (kuzushi: up on the toes, back on the heels). Negative leans back. |

### The body

| Move | Does |
|---|---|
| `{"bend": "uke1.Spine", "forward": 30, "side": 0, "turn": 0}` | Sets a spine, neck, head, thigh or shin bone from its rest: `forward` folds forward (a thigh: knee up; a shin: heel back), `side` toward the figure's right, `turn` toward its left. Setting, not adding. Spread a big bend over `Spine` and `Chest`. |
| `{"straighten": "uke1.Spine"}` / `{"straighten": "uke1"}` | That bone, or the whole spine, back to rest. |

### Hands and grips

| Move | Does |
|---|---|
| `{"hand": "tori.Right", "at": [right, up, forward]}` | Puts a hand at an offset from its own shoulder. Arm hanging ≈ `[0.05, -0.5, 0.08]` (mirrored for left: `[-0.05…]`), extended at chest height ≈ `[0, 0, 0.55]`, overhead ≈ `[0.1, 0.45, 0.2]`. |
| `{"hand": "tori.Left", "to": "uke1.Head", "offset": [0, 0, 0.12]}` | Puts a hand at a place on someone (atemi to the face, a hand on a shoulder, an elbow), offset in *their* frame; `along` moves along the bone. `curl` closes the fingers. |
| `{"elbow": "tori.Right", "toward": [right, up, forward]}` | Steers the elbow (the IK pole), from the shoulder. |
| `{"arm_down": "uke1.Left"}` | The arm hangs at the side. |
| `{"grab": "tori.Left", "target": "uke1.RightLowerArm", "along": 0.6}` | The hand takes and wraps that bone, from the side its own forearm can reach with a straight wrist; it stays on as both bodies move. `curl`, `skews` (degrees the fingers may run across the bone), `from` (`[right, up, forward]` approach in the target's frame) optional. Wrist grips: `LowerArm` ~0.85 or `Hand`; elbow control: `UpperArm` ~0.8 or `LowerArm` ~0.1; collar: `UpperChest`/`Neck`. |
| `{"refit": "uke1.Left"}` | Takes a held grip again where the hand now is, the wrap and finger angle chosen afresh. Use it after the held arm turns (a tenkan, a raise, a wrist turned over): a grip keeps the wrap it was taken with, so otherwise the gripping wrist bends through the whole turn. |
| `{"release": "uke1"}` / `{"release": "uke1.Left"}` | Lets go: every grip of that figure, or one hand's. |
| `{"fingers": "tori.Right", "curl": 0.6}` | Opens (0) or closes (1) a hand. |

### Falls

| Move | Does |
|---|---|
| `{"ukemi": "uke1", "kind": "forward", "t": 0.4}` | Shapes a fall at `t` (0 upright … 1 back up) and rests the body on the mat. `kind`: `forward` (mae ukemi, a roll), `backward` (ushiro ukemi), `prone` (laid face down for a pin). Release grips first. Use several phases with increasing `t` and a `move` between them for the travel. |
| `{"ground": "uke1"}` | Rests whatever is lowest on the mat. |

### Weapons

| Move | Does |
|---|---|
| `{"weapon": "bokken1", "type": "bokken", "hold": "uke1.Right"}` | Puts a bokken / jo / tanto in one hand. |
| `{"weapon": "bokken1", "type": "bokken", "kamae": "uke1"}` | Both hands on it at chudan (a jo in its own kamae), hands fitted to where the wrists can hold it. |
| `{"weapon": "bokken1", "to": [right, up, forward], "of": "uke1", "dir": [right, up, forward], "fit": "uke1"}` | Moves it (furikaburi, a cut), the holder's hands refitted. |
| `{"weapon": "bokken1", "take": "tori.Right"}` | Puts it in another hand (a disarm). |

### Where they look

Before each pose is saved, every standing figure turns its neck and head toward its partner's
face (Tori toward the first Uke, everyone else toward Tori), within the neck's range — unless the
partner is more than 100° off the way the body faces, when the figure looks ahead (someone
beside you is watched out of the corner of the eye). Falling figures are left as the fall shapes
them. The look is not carried into the next phase's moves.

| Move | Does |
|---|---|
| `{"look": "tori", "at": "uke1.RightHand"}` | From this phase on, looks at that bone. |
| `{"look": "tori", "at": [0, -0.3, 1]}` | Looks in a direction, `[right, up, forward]` in the figure's frame (ahead and down: `[0, -0.3, 1]`). |
| `{"look": "tori", "at": "none"}` | Leaves the head as the moves put it. `"at": ""` goes back to the partner. |

A character can carry `"look"` in `characters` too, for the whole technique.

`{"settle": 4}` waits frames, if something needs to solve before the next move reads it.

## Writing one well

1. **Start from the attack.** The catalogue places Uke where his arms can make the grip; build
   every later position relative to Uke (`"of": "uke1"`, `"to": "uke1.LeftFoot"`) so the
   technique keeps its shape.
2. **Body first, then hands.** A hand is placed in the world; moving the body afterwards leaves
   it behind (a grip moves with its target, a free hand does not).
3. **One idea per phase**, named the way a handout names it (Grepp, Irimi, Tenkan, Kuzushi,
   Kake, Ukemi, Osae). Short transitions (0.3–0.5 s) for fast movement, a long hold on the
   final pose.
4. **Look, then fix.** Read `contact_sheet.png` and the problems printed per phase; change one
   number and rebuild (a build is about 40 s with `--no-video`).
5. A technique is never anatomically perfect on the first try. A wrist or shoulder a few degrees
   past range is drawn at its range (`JointLimits`), so the picture is still possible; a body
   *through* another body is worth fixing.
