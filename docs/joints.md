# The joints: what the body knows about how it moves

The mannequin came with fifty-two bones and no anatomy. Nothing in a skeleton says an elbow is
a hinge, a wrist bends further toward the palm than away from it, a knee cannot turn until it is
bent, or a finger cannot spread once it has curled. Every such fact used to live, if anywhere, in
one number per bone in `Anatomy` — a cone a joint might swing inside — and the tool would happily
draw a hand bent ninety degrees sideways onto a jo because no rule said not to. This document is
the rule set that replaced that: `src/rig/Joints.gd`, enforced by `JointLimits.gd`, spent by
`LimbTurn.gd` through `TwistFollow.gd` and `HandOrient.gd`, reported by `Anatomy.gd`, posed from
the panel, and checked by `tests/test_joints.gd`.

## One joint, three angles

Every bone except the root is a joint against its parent, and every joint is described the way a
physiotherapist describes it:

- a **neutral direction** `n` — where the bone points at anatomical zero: straight along the
  parent for a hinge, straight down for a shoulder or hip;
- a **flexion direction** `p` — where the far end goes when the joint flexes (forward for a
  shoulder, backward for a knee, toward the palm for a wrist), which fixes the flexion axis
  `f = n × p`;
- an **abduction direction** `b` — out to the side, toward the little finger, toes out.

Any rotation of the bone is then read as three numbers in degrees — **flexion** (negative is
extension), **abduction** (negative is adduction or deviation the other way), and **twist** (the
roll about the bone once its swing is taken out) — and the same three numbers are turned back into
a rotation. The round trip is exact to a hundredth of a degree (`tests/test_joints.gd`). Each of
the three has its own asymmetric range, and each end of each range has a name, so the readout says
"ulnar deviation 12°" and a refusal says "wrist flexion 119°, past 80°".

The directions are **measured from the rig, not typed in**. The exporter left the bones' local
axes meaning nothing anatomical (the two feet are not even mirror images), so a joint is described
by directions in the character's own space — down, forward, out, the palm normal `FingerCurl`
measured, the fold direction of the rest elbow — and stored in the parent's rest frame so it
moves with the parent. The rest pose reads as anatomy would say it: the A-pose is 42° of shoulder
abduction and 43° of elbow flexion, the knees are 7° bent, and everything else is within a few
degrees of neutral.

## The ranges

Typical passive range of a healthy adult (AAOS goniometry; Kapandji for the hand), degrees.
Negative is the first-named direction.

| joint | kind | flexion | abduction | twist |
|---|---|---|---|---|
| spine (lumbar) | gliding | extension 25 / flexion 60 | side-bend 25 | turn 10 |
| chest (thoracic) | gliding | 20 / 45 | 20 | 25 |
| upper chest | gliding | 15 / 35 | 15 | 20 |
| neck | gliding | 50 / 45 | 40 | 70 |
| head | condyloid | 30 / 30 | 20 | 30 |
| clavicle | gliding | depression 10 / elevation 45 | retraction 30 / protraction 30 | 15 |
| shoulder | ball | extension 60 / flexion 180 | adduction 45 / abduction 180 | internal 90 / external 90 |
| elbow | hinge | 5 / 155 | carrying angle 8 | supination 85 / pronation 80 |
| wrist | condyloid | extension 70 / flexion 80 | radial 20 / ulnar 30 | roll 45 |
| knuckle (MCP) | condyloid | 30 / 90 | 20 (30 little finger) | 10 |
| finger PIP | hinge | 5 / 100 | 4 | 5 |
| finger DIP | hinge | 15 / 80 | 4 | 5 |
| thumb base (CMC) | saddle | 15 / 60 across the palm | 10 / 60 palmar abduction | 40 |
| thumb MP | hinge | 10 / 55 | 10 | 15 |
| thumb IP | hinge | 20 / 80 | 10 | 15 |
| hip | ball | extension 30 / flexion 120 | adduction 30 / abduction 45 | 45 / 45 |
| knee | hinge | 5 / 155 | varus/valgus 8 | 5, up to 35 when bent |
| ankle | hinge | dorsiflexion 35 / plantarflexion 65 | toes in 15 / out 20 | eversion 15 / inversion 35 |
| toes (MTP) | hinge | lifted 60 / curled 40 | 5 | 5 |

Three of these are deliberately not the book's number, and say why in the code: ankle
dorsiflexion (the rig's foot is one bone from ankle to ball, and a squat with the heels down
loads the midfoot too); the wrist's roll (the forearm bone carries pronation and `HandOrient`
hands the wrist what the forearm and shoulder cannot take); and the thumb joints' roll
(`FingerCurl` folds the whole thumb about one axis, which each phalanx reads as a little roll).

Four ranges **depend on the joint's own position**, which is what makes them joints rather than
three sliders:

- a **knee** turns 5° when straight and about 35° once bent to 90° (the screw-home lock);
- a **knuckle** spreads 20° while the finger is open and not at all once it has curled;
- a **shoulder** adducts across the body only as far as the arm is also raised forward;
- a **forearm's** roll is the elbow's twist, so it is measured on the forearm bone, and which sign
  is pronation is read off the palm at build time rather than assumed.

## Where the rules take effect

**On screen, always.** `JointLimits` is the last modifier on every skeleton. Whatever the FK
rotations, the finger curls, the four IK solves and the hand orientations asked for, every joint
is measured, brought inside the range for its position, and written back. A pose file that asks
a wrist for 120° shows a wrist at 80°. The pose is not hidden: the modifier records what it
refused (`refused`, `report()`), `Anatomy.joint_problems` carries the same lines, the side panel
shows "Asked for more: …" under the joint, and `tests/check_anatomy.gd` lists every committed pose
that asks a joint for more than it has. With the modifier off, `Anatomy` measures the shown pose
against the same ranges instead. `PoseImport` clamps the FK bones of a video draft on import, so a
draft is a possible person from the start.

**In the hand of the instructor.** The rings and the sliders go through
`PoseController.within_range`, so a joint dragged past its range stops there and comes back off
it. The three sliders under "Selected joint" are the joint's own — flexion/extension,
abduction/adduction, twist, named for that joint, each running exactly as far as it goes — and the
readout under them says the pose in words. The hips, which are not a joint, keep raw X/Y/Z.

**In the limb, when a joint is asked for more than it has.** A placed limb has one freedom left:
with the shoulder and the hand fixed, the elbow can still be anywhere on a circle between them,
and turning the whole arm about the line from shoulder to wrist moves it round that circle without
moving the hand (`LimbTurn`). A body spends that freedom whenever a joint is over-asked, and so
does the tool:

- `TwistFollow` twists the humerus so the elbow folds the way it can; when the pole asks for an
  elbow the shoulder cannot twist to, the arm turns about its line until the shoulder is back in
  range. The pole is a preference, the shoulder is a fact, and the hand does not move.
- `HandOrient` gives a hand its orientation through the joints that can do it: it searches the
  turn that leaves the wrist the least to do that it cannot do (shoulder kept in range, elbow kept
  near the pole), rolls the forearm as far as pronation goes, and only then asks the wrist. An arm
  spends its turn freely; a leg turns at the hip only for where the foot *points*, so a knee stays
  over its toes and a foot asked to bend too far is the ankle's to refuse. A standing foot turned
  out 30° is now a hip turned 30°, not a knee twisted 28° as every committed stance used to have.
- What is still left is the wrist's, and `JointLimits` holds it. The hand is then on its point
  but short of its orientation by exactly what the wrist could not give, and the panel says so.

The search is deterministic and history-free: the roll a forearm needs is measured from the
wrist's rest, not from wherever the hand was last frame, so a reloaded pose lands exactly where it
was saved (`tests/test_m4.gd`). It knows joints, not bodies; an elbow can be turned into a chest
to straighten a wrist. See the note at the top of `LimbTurn.gd` for what was tried.

## What the model found on the first day

Run against the committed poses and the movements the tool can make, the joints reported (and
in two cases fixed) things no earlier check had seen:

- **Kneeling folded the foot onto the front of the shin.** `Stance.kneel` kept the foot's
  standing orientation, toes forward, while the shin lay back on the mat: 90° of dorsiflexion. A
  kneeling foot points *back*, instep down in seiza and on the ball in kiza; `kneel` now turns it
  over the ankle, and seiza reads as 46° of plantarflexion, which is what seiza feels like.
- **The forward roll extended the hips 65° behind the body.** `Ukemi.shape` turned the thighs
  about the same axis and in the same sense as it curled the spine; a spine standing up and a
  thigh hanging down go opposite ways under that turn. The tuck now flexes the hips 70° toward
  the chest, and the three rolling poses of ushiro ryotedori zenponage were rebuilt.
- **Every hanmi stance twisted a knee 27–28°** to turn the rear foot out, with the knee nearly
  straight. The hip does that now.
- **Fists on wrists were bent 86° sideways** (katatedori), forearms pronated up to 171°, and the
  weapon-hold wrists extended 107–134°. These are the poses' own geometry: Uke stands where his
  arm is straight, so no elbow position brings the forearm across Tori's wrist, and a two-handed
  hold is rolled to an angle no wrist reaches. Each is listed in `tests/check_anatomy.gd`.

## Working with it

- `Joints.angles(spec, q)` / `Joints.rotation(spec, flex, abd, twist)` — the two directions.
- `Joints.limits(spec, angles)` — the range in force at those angles; `clamp_angles`,
  `clamp_rotation`, `excess`, `describe`, `readout`.
- `rig.joints.spec("RightHand")` — the catalogue entry; `rig.joints.order` — parents first.
- `rig.joint_limits.refused` / `report()` — what the last pass held back.
- `Anatomy.joint_angles(rig, bone)` — a joint's angles as shown; `Anatomy.range_problems(rig)`.
- `PoseController.set_joint_angles` / `get_joint_angles` — pose a joint by its own numbers.
- `Limb.hand_orient.last_turn_deg`, `last_middle_twist_deg`, `Limb.twist.last_turn_deg` — what
  a limb did to serve its hand or foot on the last pass.
