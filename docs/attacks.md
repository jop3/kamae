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
| `katatedori` | right hand forward, hip height | left hanmi, in front, offset to Tori's right | left hand round the right wrist from the outside, thumb up | 0.57 m away, 0.31 m to Tori's right — 16 cm closer than the old fixture, elbow out |
| `aihanmi_katatedori` | right hand forward, a little higher | right hanmi, straight in front | right hand over the right wrist, fingers skewed across it (45°) | 0.59 m away, centred |
| `ryotedori` | both hands forward and apart, a little high | left hanmi, in front | each hand on the same-side wrist from the outside, fingers skewed a little | 0.56 m away |
| `morotedori` | right hand forward | left hanmi, well out on Tori's right | left hand at the wrist, right hand a third of the way up the forearm, held a little looser, fingers skewed | 0.58 m away, 0.45 m to Tori's right: further round the arm than the catalogue guessed, both forearms across it |
| `katadori` | nothing (hands at the sides) | left hanmi, close, a little to the right | left hand on the top of the right shoulder | 0.51 m, where the catalogue put him |
| `ryokatadori` | nothing | left hanmi, close, square | both hands on the shoulders | 0.49 m, shifted 12 cm to Tori's right |
| `munedori` | nothing | left hanmi, close | left hand on the chest at the lapel | 0.46 m |
| `eridori` | nothing | left hanmi, close | left hand in the collar at the side of the neck, forearm over the shoulder | 0.44 m |
| `sodedori` | right arm half offered, low | left hanmi, to the right | left hand on the upper arm above the elbow | 0.46 m |
| `hijidori` | right arm half offered | left hanmi, to the right | left hand on the forearm below the elbow | 0.51 m |
| `katadori_menuchi` | nothing | left hanmi, close | left on the shoulder, right raised over the head | 0.53 m |

## Grips and holds from behind

| key | Aikikai | Iwama | Yoshinkan | Ki Society | Tomiki | English | Swedish |
|---|---|---|---|---|---|---|---|
| `ushiro_ryotedori` | Ushiro ryotedori | Ushiro ryotedori | Ushiro ryote mochi | Ushiro tekubi tori | Ushiro ryote dori | both wrists from behind | båda handlederna bakifrån |
| `ushiro_ryokatadori` | Ushiro ryokatadori | Ushiro ryokatadori | Ushiro ryokata mochi | Ushiro ryokatadori | Ushiro ryokata dori | both shoulders from behind | båda axlarna bakifrån |
| `ushiro_eridori` | Ushiro eridori | Ushiro eridori | Ushiro eri mochi | Ushiro eridori | Ushiro eri dori | collar from behind | kraggrepp bakifrån |
| `ushiro_kubishime` | Ushiro katatedori kubishime | Ushiro kubishime | Ushiro kubi shime *check* | Ushiro katatedori kubishime | — | choke from behind, one wrist held | strypgrepp bakifrån |

| key | Tori | Uke stands | Uke's hands | measured |
|---|---|---|---|---|
| `ushiro_ryotedori` | arms hanging, hands a little out | behind, facing the same way, right hanmi | each hand on the same-side wrist from behind, fingers skewed a little | 0.36 m behind, where the catalogue put him |
| `ushiro_ryokatadori` | arms hanging | behind | hands on the shoulders from above and behind | 0.40 m |
| `ushiro_eridori` | arms hanging | behind, a touch right | right hand in the collar at the nape | 0.42 m |
| `ushiro_kubishime` | left arm hanging back | behind, right up against Tori | right forearm across the throat (the hand lands on the far side of the neck), left hand on Tori's left wrist | 0.35 m; the forearm lies across the throat and shoulder by design |

## Strikes

No grip: Uke's hand is placed and the arm follows, at ma-ai.

| key | Aikikai | Yoshinkan | Ki Society | English | Swedish | Uke |
|---|---|---|---|---|---|---|
| `shomenuchi` | Shomenuchi | Shomen uchi | Shomenuchi | straight cut to the forehead | hugg mot huvudet | right hanmi, 0.90 m, right hand raised over the head |
| `yokomenuchi` | Yokomenuchi | Yokomen uchi | Yokomenuchi | diagonal cut to the side of the head | sidohugg | right hanmi, 0.90 m, right hand up and out to his right |
| `chudan_tsuki` | Chudan tsuki / mune tsuki | Shomen tsuki | Mune tsuki | punch to the solar plexus | stöt mot magen | right hanmi, 0.95 m, right fist forward, left at the hip |
| `jodan_tsuki` | Jodan tsuki | Jodan tsuki | Jodan tsuki | punch to the face | stöt mot ansiktet | as chudan, fist at face height |
| `tanto_tsuki` | Tanto tsuki (tantodori) | Tanto tsuki | Tanto tsuki | knife thrust to the belly | knivstöt mot magen | as chudan tsuki with a tanto in the right hand, 1.0 m |
| `mae_geri` | Mae geri | Mae geri | Mae geri | front kick | framåtspark | left hanmi, 1.0 m, right foot driven forward at belly height, hands up as a guard |

## What is not here yet

- The weapon attacks with bokken and jo, which the weapon poses in `tools/build_fixtures.gd`
  already cover; a `"weapons"` entry under `uke` (as `tanto_tsuki` has) is how one would go here.
- Grips with the *other* stance relation (a katatedori from ai hanmi on the left side is
  `aihanmi_katatedori` mirrored; a gyaku hanmi grip taken with the near hand is `katatedori`).
- Uke's second hand in the single grips hangs; a school that keeps it raised as a guard can add
  it under `"uke": {"hands": …}`.

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
