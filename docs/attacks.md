# The attacks: a cheat sheet for starting a technique

Every technique starts from an attack — a grip, a strike, a hold from behind — and every one of
those has a name, a stance, a distance, a hand and a side. This page is the catalogue in
`data/attacks.json` written out: what each attack is called in the schools that call it
something else (Swedish for the handout), who stands where, which hand takes what and how, and
what the tool measured when it built each one with the joints switched on. The tool can set
any of them up in a second:

- in the app, **Start from an attack** in the side panel (pick, tick *mirror* for the other
  side, **Stage**);
- headless, `godot --headless -s tools/stage_attack.gd -- katatedori [--mirror]` saves the
  staged pose to `poses/` as "Katatedori Start";
- in a script, `await Attacks.stage(staging, "katatedori", {"mirror": true})`; the fixture
  builder's `attack("katatedori")` does this, and katatedori ikkyo and shihonage in `poses/`
  start from it (`tools/build_fixtures.gd`).

Staging puts Tori at the origin facing +z in hanmi, offers whatever the attack takes, puts Uke in
hanmi where the catalogue has him, hangs the hands nobody uses at the sides, wraps each gripping
hand round its target **from the side its own forearm comes from** (a fist round a wrist has its
fingers across the wrist and its length at right angles to it, so the forearm must arrive at
right angles too — for a wrist held from in front that is the *side* of the wrist, thumb on top,
not the top of it), tries the fist both ways round and at the skews the catalogue allows, and
then moves Uke to the place where his shoulders, elbows and wrists refuse nothing and no body is
inside another. Everything below in the "measured" column is what came of that
(`tests/test_attacks.gd`, `ATTACKS_VERBOSE=1`).

Names marked *check* are the compiler's best knowledge of a school's usage, not the instructor's;
edit `data/attacks.json` and the panel, the tool and this page's source follow. Yoshinkan says
*mochi* where Aikikai says *dori*; Ki Society and Iwama mostly say what Aikikai says with a few
of their own; Tomiki/Shodokan names its attacks by the same words but its syllabus is built on
different forms, so treat that column as vocabulary only.

## Grips from the front

| key | Aikikai | Iwama | Yoshinkan | Ki Society | Tomiki | English | Swedish |
|---|---|---|---|---|---|---|---|
| `katatedori` | Gyaku hanmi katatedori | Katatedori | Katate mochi | Katatedori | Katate dori | single wrist grab, mirror stance | grepp om handleden, spegelvänd ställning |
| `aihanmi_katatedori` | Ai hanmi katatedori | Kosadori | Katate mochi (ai hanmi) *check* | Katate kosadori | Ai gamae katate dori *check* | cross-hand wrist grab | korsgrepp om handleden |
| `ryotedori` | Ryotedori | Ryotedori | Ryote mochi | Ryotedori | Ryote dori | both wrists | grepp om båda handlederna |
| `morotedori` | Morotedori / katate ryotedori | Morotedori | Katate mochi ryote mochi *check* | Katate ryotedori | *check* | two hands on one wrist | tvåhandsgrepp om en handled |
| `katadori` | Katadori | Katadori | Kata mochi | Katadori | Kata dori | shoulder grab | axelgrepp |
| `ryokatadori` | Ryokatadori | Ryokatadori | Ryokata mochi | Ryokatadori | Ryokata dori | both shoulders | grepp om båda axlarna |
| `munedori` | Munedori | Munedori | Mune mochi | Munedori | Mune dori | chest / lapel grab | grepp i bröstet |
| `eridori` | Eridori | Eridori | Eri mochi | Eridori | Eri dori | collar grab | kraggrepp |
| `sodedori` | Sodedori | Sodedori | Sode mochi | Sodedori | Sode dori | sleeve at the elbow | ärmgrepp |
| `hijidori` | Hijidori | Hijidori | Hiji mochi | Hijidori | Hiji dori | elbow grab | armbågsgrepp |
| `katadori_menuchi` | Katadori menuchi | Katadori menuchi | Kata mochi shomen uchi *check* | Katadori menuchi | — | shoulder grab and a strike | axelgrepp med hugg |

How each is situated (Tori in right hanmi, offering the right side; *mirror* swaps everything):

| key | Tori offers | Uke stands | Uke's hands | measured: Uke ended up |
|---|---|---|---|---|
| `katatedori` | right hand forward at the belt, 40 cm out | left hanmi, an arm's length off, a little to Tori's right | left hand round the right wrist from the outside, thumb up; the right low in front of his centre | 0.87 m away, 0.19 m to Tori's right |
| `aihanmi_katatedori` | right hand forward | right hanmi, in front | right hand over the right wrist, fingers across it | 0.83 m away |
| `ryotedori` | both hands forward and apart | left hanmi, in front | each hand on the same-side wrist from the outside | 0.80 m away |
| `morotedori` | right hand forward | left hanmi, out on Tori's right | left hand at the wrist, right hand a little below the elbow | 0.78 m away, 0.30 m to Tori's right |
| `katadori` | nothing (hands at the sides) | left hanmi, the arm nearly straight | a fistful of gi at the front of the right shoulder, thumb up | 0.71 m |
| `ryokatadori` | nothing | left hanmi, square | a fist on the front of each shoulder | 0.67 m |
| `munedori` | nothing | left hanmi | a fistful of lapel at the chest, thumb up | 0.70 m |
| `eridori` | nothing | left hanmi | a fist in the collar at the side of the neck | 0.67 m |
| `sodedori` | right arm hanging | left hanmi, to the right | a fistful of sleeve above the elbow, from the outside | 0.64 m |
| `hijidori` | right arm half offered | left hanmi | left hand round the forearm just below the elbow | 0.70 m |
| `katadori_menuchi` | nothing | as katadori | left on the shoulder, right raised over the forehead | 0.71 m |

## Grips and holds from behind

| key | Aikikai | Iwama | Yoshinkan | Ki Society | Tomiki | English | Swedish |
|---|---|---|---|---|---|---|---|
| `ushiro_ryotedori` | Ushiro ryotedori | Ushiro ryotedori | Ushiro ryote mochi | Ushiro tekubi tori | Ushiro ryote dori | both wrists from behind | båda handlederna bakifrån |
| `ushiro_ryokatadori` | Ushiro ryokatadori | Ushiro ryokatadori | Ushiro ryokata mochi | Ushiro ryokatadori | Ushiro ryokata dori | both shoulders from behind | båda axlarna bakifrån |
| `ushiro_eridori` | Ushiro eridori | Ushiro eridori | Ushiro eri mochi | Ushiro eridori | Ushiro eri dori | collar from behind | kraggrepp bakifrån |
| `ushiro_kubishime` | Ushiro katatedori kubishime | Ushiro kubishime | Ushiro kubi shime *check* | Ushiro katatedori kubishime | — | choke from behind, one wrist held | strypgrepp bakifrån |
| `ushiro_dori` | Ushiro dori (ushiro hagai jime) *check* | Ushiro kakae dori *check* | Ushiro kakae *check* | Ushiro dori *check* | Ushiro dori *check* | bear hug from behind, over the arms | omfamning bakifrån över armarna |

| key | Tori | Uke stands | Uke's hands | measured |
|---|---|---|---|---|
| `ushiro_ryotedori` | arms hanging, hands a little forward | behind, facing the same way, right hanmi | each hand on the same-side wrist from behind | 0.36 m behind |
| `ushiro_ryokatadori` | arms hanging | behind | a fist in the gi at the back of each shoulder, thumbs up | 0.45 m |
| `ushiro_eridori` | arms hanging | behind, a touch right | right fist in the collar at the nape | 0.48 m |
| `ushiro_kubishime` | left arm hanging back | behind, right up against Tori | right forearm across the throat, the fist at Tori's left collar; left hand on Tori's left wrist | 0.30 m; the forearm lies across the throat and shoulder by design |
| `ushiro_dori` | arms hanging | behind, chest to his back | both arms round Tori over his upper arms, the hands holding on in front of his chest, elbows out | 0.31 m; Uke's arms press into Tori's sides (4 cm) by design |

## Strikes

No grip: the strike arrives (the `strike` block, below) and stops a hand's width short of its
target; Tori stands in kamae.

| key | Aikikai | Yoshinkan | Ki Society | English | Swedish | Uke |
|---|---|---|---|---|---|---|
| `shomenuchi` | Shomenuchi | Shomen uchi | Shomenuchi | straight cut to the forehead | hugg mot huvudet | stepped through into a deep right hanmi, the right hand-blade at the forehead; 0.83 m |
| `yokomenuchi` | Yokomenuchi | Yokomen uchi | Yokomenuchi | diagonal cut to the side of the head | sidohugg | right hanmi a little out to his right, the hand-blade at Tori's left temple; 0.67 m |
| `chudan_tsuki` | Chudan tsuki / mune tsuki | Shomen tsuki | Mune tsuki | punch to the solar plexus | stöt mot magen | a long, low right lunge, the arm straight, the left fist at the hip; 0.93 m |
| `jodan_tsuki` | Jodan tsuki | Jodan tsuki | Jodan tsuki | punch to the face | stöt mot ansiktet | as chudan, the fist at the face; 0.79 m |
| `tanto_tsuki` | Tanto tsuki (tantodori) | Tanto tsuki | Tanto tsuki | knife thrust to the belly | knivstöt mot magen | as chudan tsuki with a tanto in the right hand; 1.01 m |
| `mae_geri` | Mae geri | Mae geri | Mae geri | front kick | framåtspark | left hanmi, 1.0 m, right foot driven forward at belly height, hands up as a guard |

## In motion

An attack is not only its moment. Each entry has a `"motion"` block: the **stages** before the
moment — the poses a handout would show of Uke coming in — and the moment's own timing (`final`).
A technique script asks for them with `"approach"` on its `attack` move (`docs/technique-scripts.md`):

- `"none"` (the default): the moment alone, as before.
- `"static"`: from kamae at ma-ai, through the stages, into the moment.
- `"moving"`: Uke walks in from further away first — `steps` walking steps (2 by default, a stride
  of 0.6 m, half a second each), worked out by taking the first stage's feet back a step at a time
  along the way Uke faces, so the last step lands exactly on it. Uke starts about 2.5 m from Tori.

`techniques/attack_<key>.json` is every attack built this way, filmed in the gallery's first section.

What the stages are, by kind of attack (right side; *mirror* swaps it):

| attack | stages before the moment |
|---|---|
| grabs from the front | **Kamae** in the other hanmi, about half a metre further off than the grip; **Te**: one step through with the grabbing side's foot, the hand(s) reaching for the target, open; then the hand closes on it |
| `katadori_menuchi` | as a grab, then **Katadori** (the shoulder taken), then the right hand raised to strike |
| `shomenuchi`, `yokomenuchi` | **Kamae** in left hanmi; **Furikaburi**: the right hand raised over the forehead (yokomen: up and out to the right), the hips back; then the step through with the right foot and the cut |
| `chudan_tsuki`, `jodan_tsuki`, `tanto_tsuki` | **Kamae** in left hanmi with the right fist (or the tanto) chambered at the hip; then the lunge through with the right foot |
| `mae_geri` | **Kamae** in left hanmi, guard up; then the kick |
| from behind | **Kamae** in front of Tori; **Te** (ushiro ryotedori: the right wrist taken cross-hand) or **Ayumi**, a step to Tori's right front; **Mawari**, past his right side, keeping hold; **Ushiro**, turning in behind him; **Ushiro ni**, the left foot to its place; then the grip |

One foot moves from one stage to the next, never two (two feet off the mat in one blend is a
hop): `tests/test_attacks.gd` checks it for every attack, and that a grip taken on the way in
is on its point.

A stage is written in the catalogue as:

```json
{"name": "Te", "feet": {"Right": [0, -0.75]}, "turn": 0, "weight": 0.6, "drop": 0.06, "lean": 0,
 "hands": {"Left": {"to": "RightLowerArm", "along": 0.85, "offset": [0, 0.02, 0.12], "curl": 0.15}},
 "grips": [0], "lead": "Left", "transition": 0.55, "hold": 0.0}
```

`feet` gives each foot as `[left, forward]` metres from where *that foot* ends up in the attack, in
Uke's frame there (a foot left out is where it ends up); with `"frame": "tori"` the feet are places
in Tori's frame instead (an attack from behind starts in front of him), and `"final"` puts a foot
where it ends up. `turn` is degrees from the way Uke faces in the attack (or, in Tori's frame, from
Tori's: 180 is facing him). The hips are `weight` of the way from the rear foot to the front one,
lowered by `drop`, the trunk leaned `lean` degrees forward (the spine bent, the feet where they are). `hands` is `"kamae"` (the default; `lead` picks
the front hand, otherwise the front foot's side) or per side an offset from the shoulder, `"hang"`,
`"kamae"`, or a block with `at` or `to` (a bone of Tori, `along` it, `offset` in Tori's frame) and
optionally `point`, `palm` (directions in Uke's frame), `curl` and `elbow` (where the elbow points
from the shoulder, for arms that go round a body). `grips` takes the attack's own grips by index.

### The moment's own keys

Besides `hanmi`, `distance`, `lateral`, `facing` and `hands`, an attack's `uke` (and `tori`) block
may give the stance's `depth`, `width`, `drop`, `weight` (how far onto the front foot) and `lean`;
`"hands": "kamae"` holds both hands in kamae. `min_gap` is how close Uke's hips may come to
Tori's when the fit moves him (a grab is taken at arm's length; without it the joints alone pulled
Uke in chest to chest), `fit_in` the distances toward Tori the fit tries.

A grip with `"cloth": true` is a fist in the gi, not a hand wrapped round a bone: its knuckles go
`along` the bone plus `offset` (Tori's frame), turned by `point` and `palm` (Uke's frame), closed
`curl`, and held there relative to the bone (`Staging.grab_cloth`, `GripDirector.attach_at`). The
shoulder, lapel, collar and sleeve grabs are cloth grips.

A `strike` block is a strike arriving: `hand`, `to` (a bone of Tori), `along`, `offset`, and
`reach`, the share of the arm's full length the arm is extended to. Uke is moved along the line to
Tori until the striking hand is there at that reach, and the hand is turned by `point` and `palm`.
The cuts and punches stop a hand's width short of the forehead, temple, solar plexus or face.

## What is not here yet

- The weapon attacks with bokken and jo, which the weapon poses in `tools/build_fixtures.gd`
  already cover; a `"weapons"` entry under `uke` (as `tanto_tsuki` has) is how one would go here.
- Grips with the *other* stance relation (a katatedori from ai hanmi on the left side is
  `aihanmi_katatedori` mirrored; a gyaku hanmi grip taken with the near hand is `katatedori`).
- Uke's second hand in the single grips is held low in front of his centre; a school that keeps
  it raised as a guard can change it under `"uke": {"hands": …}`.
- The kick has no chambered knee: its approach is kamae and the kick.
- Tori does not move while Uke comes in. A technique moves him from the attack's moment on; meeting
  the attack earlier (Tori entering as Uke raises the hand) is a phase of the technique placed
  between the stages, which the `approach` does not do for it.

## How a grip is placed, for the record

`Staging.grab` is the whole of it. The target bone is treated as a shaft. From Uke's shoulder to
the point on the shaft is the forearm's line; the palm must lie on the shaft perpendicular to both
that line and the shaft, which leaves two sides, and the fingers can run either way along the
shaft (thumb toward the hand or toward the elbow), which leaves four wraps, times any skews the
entry allows. Each is attached, solved, and measured by what Uke's shoulder, elbow and wrist
refuse (`JointLimits`) and how far the hand is from its point; the cheapest is kept. Then
`Attacks._fit` tries Uke at up to 49 places around the catalogue's — toward and away from Tori
by up to 20 cm, sideways by up to 18 cm — scoring each by refused degrees, a fixed price for any
refusal at all, a hand short of its point, the two bodies overlapping, and the distance moved;
grips are taken again from the winning place and the search runs once more. What is left in the
"measured" columns is where a body can do the grip, not where a script put it.
