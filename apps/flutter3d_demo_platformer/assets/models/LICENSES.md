# Models

## `penguin.glb` — "Weathered penguin-bot"

| | |
|---|---|
| Author | epilogueronin — https://sketchfab.com/epilogueronin |
| Source | https://sketchfab.com/3d-models/weathered-penguin-bot-33afc2b450dd4c188b307c82f3b2cbc3 |
| Licence | **CC BY 4.0** — http://creativecommons.org/licenses/by/4.0/ |

Attribution is a condition of the licence, so it is written here, and it must
appear wherever the game does — a credits screen, a store page, a README.

**The file in this repository is modified**, which CC BY also requires be
stated. Two changes, both by `tool/prepare_models.py`:

* its four 1024x1024 maps are resized to 512x512 — this stack has no compressed
  texture formats, so every image costs raw RGBA in device memory whatever its
  PNG weighed;
* a scale of 0.2294 is folded into its root node, so the model is 1.8 m tall as
  authored and the game needs no `setScale` at runtime.

Neither touches the mesh. The original is `weathered_penguin-bot.glb` as
downloaded from the source above.

The traceable case, and the reason this file exists at all: the key below used
to be the opposite one, shipped with no licence traced at all, and it took
generating a replacement rather than finding an author to close it. This model
carries its own provenance in the GLB's
`asset.extras`, which is where the table above came from rather than from
somebody's memory:

```
$ python3 -c "..."   # read the JSON chunk of the GLB
{"author": "epilogueronin (...)", "license": "CC-BY-4.0 (...)",
 "source": "https://sketchfab.com/3d-models/...", "title": "Weathered penguin-bot"}
```

Anything added here later is expected to answer the same three rows before it is
committed.


## `coin.glb` — "Stylized Coin"

| | |
|---|---|
| Author | BarracudaByte — https://sketchfab.com/barracudabyte |
| Source | https://sketchfab.com/3d-models/stylized-coin-8cd6f95c44994ed5944a42892d0ffc10 |
| Licence | **CC BY 4.0** — http://creativecommons.org/licenses/by/4.0/ |

**Modified**, and the licence asks that this be said. All of it by
`tool/prepare_models.py`:

* its one 1024x1024 map is resized to 512x512;
* its root node carries a scale of 0.5 and a drop, so the coin is 0.4 m across
  with its origin at its own centre rather than on the floor beneath it — a
  fixture's model is placed at the collider's centre, and without the drop every
  coin would hover;
* **`KHR_materials_unlit` is removed**, and that one is a workaround for a
  defect rather than a choice. An unlit material in this engine draws its base
  colour and never samples its albedo: the coin was flat beige whatever was done
  to the image, and became a gold coin with a star on it the moment the
  extension came off. `LightingModel.unlit` declares `usesMaterialMaps: false`
  while leaving `usesAlbedoTexture` true, and the texture is lost somewhere
  between those two. Fixing it belongs in the renderer, not in an asset
  pipeline.

The mesh is untouched. The original is `stylized_coin.glb` as downloaded.


## `key.glb` — generated here, CC0

**This entry used to say the game could not ship.** The key it describes came
from an archive with no licence file, no readme and no author, both games placed
it, and the credits screen told the player so. It was not traced — an asset with
no provenance does not acquire one — it was replaced.

Written by `tool/make_key.py`: a torus for the bow, a cylinder for the shaft and
two boxes for the bit, flat-shaded, 888 vertices, 24 KB. Run it again and the
file is byte-identical; it writes the same one into `apps/flutter3d_demo_dungeon` in the same
pass, so the two games cannot drift.

CC0 1.0 — <https://creativecommons.org/publicdomain/zero/1.0/>. No attribution
is owed and this entry is a record rather than a duty, which is the whole
difference between it and what was here before. The size is copied from the
model it replaces (0.25 by 0.72 m) because both games place it by that size, and
`test/key_model_test.dart` checks that it stayed there.


## `hero.glb` — **not in this game any more**

Moved to `packages/flutter3d/test/fixtures/`, which no application declares and
no player downloads.

It is a rigged character with eighteen clips that this game stopped drawing —
the runner is the penguin — and it sat in this directory, which the pubspec
declares whole, so 424 KB went into every download of a game that never showed
it. That is the failure worth naming: an asset directory is bundled by the
directory, so an asset stops shipping only when it stops being in one.

Kept rather than deleted, because two engine tests draw it: four skins over one
armature, which shipped broken twice, and the same rig rendered, which is what
caught a node scale. Its licence — **Animated Platformer Character** by
**Quaternius**, CC0 1.0, <https://poly.pizza/m/kKtL4zvS3n> — is recorded beside
it in `test/fixtures/README.md`, because a file's provenance should travel with
the file.
