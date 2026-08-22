# Models

Every entry here answers the same three rows — author, source, licence — and
says what was changed. That form comes from `apps/platformer/assets/models/`,
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

### What was *not* used, and why it matters

**Not `tool/prepare_model.mjs`.** That is the other model script in this
directory and it would have destroyed them: it runs `simplify`, `weld` and
`unweld`, which rewrite the vertex buffer — and on a **skinned** mesh that means
the joint weights no longer describe the vertices they are attached to. The
monster arrives as a bag of triangles hinged around the origin. It was written
for a static key and it is correct for one.

`tool/prepare_monsters.py` follows `apps/platformer/tool/prepare_models.py`
instead, which touches no geometry at all and is the script that prepared
`hero.glb` — the rigged model the engine's own tests render.

## `key.glb` — generated here, CC0

Written by `apps/platformer/tool/make_key.py`: a torus for the bow, a cylinder
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
