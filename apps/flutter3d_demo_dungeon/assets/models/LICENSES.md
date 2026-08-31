# Models

Every entry here answers the same three rows — author, source, licence — and
says what was changed. That form comes from `apps/flutter3d_demo_platformer/assets/models/`,
and the reason it exists is written there: the game once shipped a model from an
archive with no licence file, no readme and no author, and it could not be
released until that was replaced. An asset with no provenance does not acquire
one.

## `monster_runner.glb`, `monster_shooter.glb`, `monster_tank.glb`

| | |
|---|---|
| Author | Quaternius — https://quaternius.com |
| Source | **Ultimate Monsters** pack, https://quaternius.com/packs/ultimatemonsters.html — the individual models via https://poly.pizza |
| Licence | **CC0 1.0** — https://creativecommons.org/publicdomain/zero/1.0/ |

CC0 asks for nothing at all: no attribution is owed and this entry is a record
rather than a duty. It is written anyway, because not being *required* to say
where something came from is a poor reason not to.

The same author's work is already in this repository — `hero.glb` under
`packages/flutter3d/test/fixtures/`, also CC0, also rigged — which is why this
pack was chosen over searching for one. The licence, the format and the fact
that a model of theirs already rigs and renders in this engine were all known
before anything was downloaded.

Which is which:

| File | The model | Roster | Height |
|---|---|---|---|
| `monster_runner.glb` | Frog | `runner` | 1.7 m |
| `monster_shooter.glb` | Wizard | `shooter` | 1.8 m |
| `monster_tank.glb` | Yeti | `tank` | 2.4 m |

Chosen for **silhouette** rather than for colour: a low quadruped, a tall robed
figure and something twice your width are three different shapes in a corridor
lit by one torch, and three different colours are one grey shape.

### What was changed

All of it by `tool/prepare_monsters.py`, and re-running it on the same downloads
produces the same files.

* **A scale is folded into each root node**, so each model stands at its own
  `MonsterDef.height` — 1.56 m becomes 1.70, 2.31 becomes 1.80, 2.59 becomes
  2.40. Not cosmetic: the capsule these replace *is* the collision shape, so a
  model taller than its own hitbox is a monster you can shoot over the head of.
  Nothing scales at runtime as a result.
* **`CharacterArmature|` is stripped from every clip name.** That prefix is a
  fact about the Blender file the models were exported from, not about the
  animation — every clip in every one of them carries it, so it distinguishes
  nothing, and leaving it means game code that says
  `'CharacterArmature|Idle'` and reads as a mistake nobody has noticed.
* **The provenance above is written into `asset.extras` inside each file**, so
  it travels with the copy rather than with this table.

The meshes, the skins and the animation data are untouched. No image is touched
either, because there are none: these are vertex-coloured, which is why three
rigged monsters cost 546 KB between them.

## `weapon_pistol.glb`, `weapon_shotgun.glb`

| | |
|---|---|
| Author | Quaternius — https://quaternius.com |
| Source | **Ultimate Gun Pack**, https://quaternius.com/packs/ultimategun.html — the individual models via https://poly.pizza/m/J3i9KDQ3kt and https://poly.pizza/m/ZmPTnh7njL |
| Licence | **CC0 1.0** — https://creativecommons.org/publicdomain/zero/1.0/ |

Same author as the monsters above, for the same reason: the licence, the format
and the fact that his work already renders in this engine were all known before
anything was downloaded.

**The licence is recorded per model, not per pack, and that distinction is not
pedantry.** Quaternius' own pack pages state CC0 for the set, and poly.pizza
records some of his uploads as CC-BY 3.0 — the animated pistol from the Animated
Guns Pack is one of them. Both files here are uploads poly.pizza states as CC0,
which is why they were the two chosen. Where two sources disagree about a
licence, the narrower claim is the one to record.

**Why not the animated pack**, which was the first choice: Quaternius ships every
pack as Blend, FBX and OBJ with no glTF at all, and poly.pizza — which converts
uploads with FBX2glTF, and is the only reason any of this is reachable without a
converter on the machine — mirrors just one weapon from it. An animated pistol
beside a static shotgun is a mixed licence and a mixed treatment for one clip
nothing would play: `WeaponView` bobs and recoils by moving the node and has no
animation player in it.

There is **no rocket launcher** in any CC0 pack searched, so that weapon is still
procedural blocks, as are the fists — a pair of hands is not a weapon model.

### What was changed

All of it by `tool/fetch_weapons.py`, which both downloads and prepares, so
re-running it reproduces both files exactly. That is `fetch_textures.py`'s
convention rather than `prepare_monsters.py`'s: the monsters were downloaded by
hand because their pack is a Google Drive folder, and these have direct URLs.

* **A quarter turn about Y is folded into a new root node.** Both models are
  built pointing down +X, and the view-model camera looks down −Z like every
  other camera in the engine, so the barrel faced sideways.
* **A scale is folded into the same node**, so each weapon is as long as the
  procedural blocks it replaces — 0.30 m for the pistol, 0.62 m for the shotgun.
  Not cosmetic: the rest position, the bob and the recoil in `WeaponView` are
  tuned against a weapon of about that size.
* **And a translation**, so each rests on the same line its blocks did. Length
  alone left both weapons floating: a model is drawn upward from its origin and
  the blocks hung down from theirs, so the pistol sat seven centimetres above
  the hand. Matching middles was not enough either — a model is slimmer than the
  blocks that stood in for it, so the shotgun was still high with its centre
  exactly right. The bottom edge is matched, because that is the line a player
  reads as where the weapon is held.
* **Every material is made a dark dielectric.** They arrived black, twice over:
  `metallicFactor` 0.4 with no image-based lighting to reflect renders very
  nearly black — the reason written above `_metal` in `weapon_models.dart` — and
  the base colours were darker again than the blocks, 0.0998 at the pistol's
  lightest against their 0.30. Metallic is zeroed and the colours are scaled by
  one factor per file, so the parts keep their relation and the lightest lands
  at 0.30.
* **The provenance above is written into `asset.extras` inside each file**, for
  the same reason it is in the monsters.

The meshes are untouched.

### What was *not* used, and why it matters

**Not `tool/prepare_model.mjs`.** That is the other model script in this
directory and it would have destroyed them: it runs `simplify`, `weld` and
`unweld`, which rewrite the vertex buffer — and on a **skinned** mesh that means
the joint weights no longer describe the vertices they are attached to. The
monster arrives as a bag of triangles hinged around the origin. It was written
for a static key and it is correct for one.

`tool/prepare_monsters.py` follows `apps/flutter3d_demo_platformer/tool/prepare_models.py`
instead, which touches no geometry at all and is the script that prepared
`hero.glb` — the rigged model the engine's own tests render.

## `key.glb` — generated here, CC0

Written by `apps/flutter3d_demo_platformer/tool/make_key.py`: a torus for the bow, a cylinder
for the shaft and two boxes for the bit, flat-shaded, 888 vertices, 24 KB. Run
it again and the file is byte-identical; it writes the same one into both games
in the same pass, so the two cannot drift.

CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/. It replaced an
untraceable model rather than tracing one, which is the entry the paragraph at
the top of this file is about.

## `exit.glb`, `note.glb`, `pickup.glb`, `player_spawn.glb` — generated here, CC0

Written by `tool/make_models.py`, out of the same functions that build the
editor's shooter template: boxes, tubes and balls, flat-shaded, coordinates
quantised so the bytes are identical on any machine. Run it again and `git diff`
says nothing, which is what CI checks.

**They exist because the editor was drawing coloured cubes for half of what a
level contains.** A note, a pickup, a way down and the point the player starts
at are coordinates with a word attached, and the editor cannot know what any of
those words mean — so what it drew was a box tinted from the word's own letters.
The models are named in `assets/editor.json`, which is the file that tells the
editor what this game's things look like.

CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/.
