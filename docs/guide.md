# Kamae — instruktörsguide / instructor guide

Kamae is the posing tool for the grading handout: two to five neutral figures, posed by hand, saved
as poses, strung into techniques, and exported as stills and short clips. This is how to use it.
The Godot editor is never needed.

## Starting

```sh
godot --path /path/to/kamae
```

A window opens with Tori (teal) and Uke (amber) facing each other on a one-metre grid, and a panel
on the right. The panel scrolls. Everything you do is undoable with Ctrl+Z / Ctrl+Y.

**Camera:** left-drag on empty space orbits, middle-drag (or Shift+drag) pans, the wheel zooms.
The Camera section has **Front** and **Side** buttons that frame every figure; Side is the default
view, Front looks from Tori's side of the line, swung a little so that Tori does not hide Uke.

**Keyboard:** `1` Front view, `2` Side view, `Home` frame everything, `Space` play or pause the
sequence, `Ctrl+Z` / `Ctrl+Y` undo and redo, `Shift` while dragging a ring snaps to 15°.

## Characters

The Characters list shows who is in the scene. **Add** puts in another Uke, Tori or observer (up
to five), **Duplicate** copies the selected figure with its pose, **Remove** takes it out (asking
first if it is part of a grip). Type a name and press Enter to rename; the colour button picks
the skin colour, which is what tells the hands apart in a printed grip. **gi** dresses the figure
in a white keikogi with a belt in its own colour (a first version, cut from the mannequin
itself; the hem, collar and V are straight cuts). **Mirror pose** swaps the
selected figure's left and right; **Copy pose to** gives another figure the same pose.

## Posing a figure

1. **Click a body part.** Three coloured rings appear at the joint. Drag a ring to rotate about
   that axis; hold **Shift** to snap to 15°. The X/Y/Z sliders do the same with numbers.
   "Reset joint" returns it to rest.
2. **Place the whole figure** with the X, Z and Turn boxes, or "Turn 180°".
3. **Arms and legs** can be switched to **IK**: a blue ball appears at the hand or foot and a grey
   one at the elbow or knee. Drag the blue ball to put the hand where you want it; the arm
   follows. Drag the grey ball to steer the elbow. If the ball turns **red** the hand cannot reach
   and the panel says by how many centimetres. Switching a limb back to FK keeps its pose.
4. **Wrists** are joints like any other: click the hand and turn it with the rings or the
   sliders, whether the arm is in FK, in IK, or gripping something. On a gripping hand the new
   angle becomes part of the grip, so it is kept as the figures move.
5. **Fingers:** one slider per finger, "Grip" closes the hand, "Open" opens it. A single finger
   joint can also be clicked and turned on its own (a pointing finger, a spread hand); the curl
   slider then closes it from there.

## Grips (the important part)

A grip keeps one figure's hand on another figure's body while either of them moves.

1. Click the body part to be gripped, on the figure being gripped (for katatedori: Tori's
   forearm).
2. In the Grips section choose who grips and with which hand, then **Attach**.
3. The hand **wraps round the body part** the way a real hand does, on the side it was on
   before you pressed Attach. So bring Uke's hand roughly above or beside Tori's wrist first,
   then Attach. A wrist is taken in a fist; on a thick part (the neck, a thigh, the torso) the
   palm is laid on the skin and the fingers close only as far as the part allows. The fingers
   are set for you; adjust them afterwards if you like.

The bodies are solid to each other. A hand target dragged into the other figure stops at the
skin, a gripping hand rides on the surface of what it holds as that figure turns or bends,
and the **collisions** line under the grip list reports any body part that is still passing
through another (or through a weapon), checked as you pose. A hand overlapping the part it
grips is fine and is not reported.

From now on the gripping hand follows. Move Tori's arm, turn Tori, step Tori away: Uke's hand
stays on the wrist. If Tori moves beyond Uke's reach the hand stops short and the ball turns red,
which is the tool telling you the figures are too far apart.

Several grips at once are fine (two Ukes on two wrists, or a chain). To reverse a grip during a
technique, release it ("Release selected grip") and attach the other way round in the next pose.

## Weapons

"Add weapon" puts a bokken, jo or tanto in the scene at the standard aikido size (1.02 m, 1.28 m,
0.30 m; the lengths are editable). Two ways to hold it:

- **Hand-driven** (default): pick the holder and hand, set *t* (where along the weapon the hand
  is: 0 at the butt, 1 at the tip) and a roll angle, press **Hold**. The weapon now follows that
  hand. "Attach the other hand at t" puts the second hand on it for a two-handed hold, using
  the roll angle in the box for that hand too.
- **Weapon-driven**: tick "Weapon-driven" and place the weapon itself with the X/Z/turn boxes;
  every hand on it follows. This is the natural mode for kumitachi and kumijo, where the crossing
  point of the weapons is what matters and the arms should follow.

**Both hands, default hold** puts the selected holder's two hands on the weapon at its default
grip: right hand in front (on a bokken just below where the tsuba would be), left hand at the
back against the kashira, each palm turned in from its own side so the backs of the hands face
up and out. The jo starts from the same grip, right hand forward and the hands about a forearm
apart; slide them with *t* and turn them with the roll box as the technique needs. The *t* and
roll boxes are pre-filled with the default for the chosen hand.

A weapon changes owner between poses by pressing **Hold** for the new holder in the later pose.

**Weapon contact** (kumitachi, kumijo): choose two weapons and a point along each; the panel
shows the gap between the points live. **Close the gap** moves the weapon-driven weapon (or the
selected figure's hand, which falls short by exactly its reach if the point is too far) until
they touch, and is undoable; **Record contact** saves the pair with the pose. The
contact is a measurement, never a constraint: nothing stops you moving the figures apart again.

## Poses and techniques

- **Save pose**: type a name and press "Save pose". The pose is a JSON file in the project's
  `poses/` folder, named from the name (`Katatedori Ikkyō — Grepp` becomes
  `katatedori_ikkyo_grepp.json`). "Load pose" brings one back, camera included.
- **A technique is a sequence** of two to five poses. Type the technique name and press **New**
  to get three steps, Grepp, Kuzushi and Kake. Select a step, pose the scene, and press
  **"Save scene as this step's pose"**. Repeat for each step. Each step has a *transition*
  (seconds to blend into it) and a *hold* (seconds to stay).
- **Play** previews it. Drag the slider to scrub. Between poses the tool blends everything; a grip
  that exists in both poses stays exactly attached the whole way, a grip that exists in only one
  fades in or out. If a transition looks wrong, insert a pose rather than fighting it.
- "Save sequence" writes `sequences/<name>.json`; "Load sequence" brings one back.

## Exporting

- **Export still (PNG)**: the current view, without the panel, balls and rings, on a flat white
  background or transparent if ticked. Files go to the exports folder shown in the panel.
- **Export Front+Side stills of the sequence**: every phase from both presets at 1920×1080,
  named `<technique>_<phase>_front.png` and `_side.png`. A second window opens briefly.
- **Export video of the sequence**: a second window renders every frame at 30 fps; then, if
  `ffmpeg` is installed (`sudo apt install ffmpeg`), the result is `<technique>.mp4`. Without
  ffmpeg you get an AVI and a note saying so. A still per phase is written alongside.

## The techniques that ship with the tool

`poses/` and `sequences/` contain first drafts of the grading techniques: Katatedori Ikkyo,
Ushiro Ryotedori Zenponage, Katatedori Shihonage irimi (which reuses the Ikkyo Grepp pose), a
three-person Ryotemochi fixture, and the four weapon forms (tachi dori, jo dori, kumitachi,
kumijo). They were built by a script to prove the mechanics, not by an aikidoka: load them,
correct them, save them. The Zenponage Kake pose deliberately keeps Uke's grips attached while
Uke is thrown beyond reach, so you can see what the red warning looks like.

## When something looks wrong

- **Hand floats beside what it grips:** attach again with the hand close to the limb; the wrap
  uses the side the hand is on.
- **Red ball:** out of reach. Move the figures closer or lower the target.
- **Wrist looks broken:** the elbow is steering the wrong way; drag the grey ball down and out.
  If the hand itself is turned too far, click the hand and turn it back with the rings.
- **Hand sits inside the other figure:** the collisions line names the parts. Release the grip and
  attach again from the side you want the hand on, or move the gripped figure.
- **Weapon in the wrong place after loading:** press Hold again for the holder.
