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

The traceable case, and the reason this file exists at all:
`apps/dungeon/assets/textures/LICENSES.md` records the opposite one, where the
key model and its maps have **no** licence traced and the game cannot ship until
that is fixed. This model carries its own provenance in the GLB's
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


## `key.glb` — provenance **unrecorded**

Carried across from `apps/dungeon/assets/models/key.glb` on request, and it is
the one asset here that cannot answer the three rows above.
`apps/dungeon/assets/textures/LICENSES.md` records why: the archive it came from
— a Cinema 4D export dated 2019, repackaged 2022 — has no licence file, no
readme and no author.

**This game therefore inherits the shooter's blocker.** Neither can ship until
the licence is traced or the model replaced, and it is now two games rather than
one. Written here rather than left implied, because the whole point of this file
is that an asset with no provenance should be visible from the game that uses
it.

Modified by `tool/prepare_models.py`: scaled by 1.2 and dropped onto its own
centre. The mesh is untouched.

## `hero.glb` — the runner, animated

**Animated Platformer Character** by **Quaternius**, **CC0 1.0 (public domain)**
— <https://poly.pizza/m/kKtL4zvS3n>, downloaded 15.08.2026 from
`https://static.poly.pizza/906e29d9-2e15-4c5c-a38a-fb99023acc9c.glb`.

CC0, so there is no attribution requirement and this entry is a record rather
than a duty. It is written down anyway, because the whole point of this file is
that a licence nobody can trace is a debt — and a file whose provenance is
"somebody downloaded it" cannot be told apart from one that is.

Chosen for what it has rather than for how it looks: **eighteen clips**,
including `Idle`, `Walk`, `Run`, `Jump`, `Jump_Idle`, `Jump_Land`, `Duck` and
`Death` — which is the platformer's whole state machine — and **twenty-nine
joints**, comfortably under the engine's cap of sixty-four. The penguin has
`animations: 0` and no skin at all, which is why the runner was a statue for
three stages.

Prepared by `tool/prepare_models.py`: scaled from its bind-pose height of 3.75
units to the 1.8 m the character controller is, and `KHR_materials_unlit`
stripped for the reason recorded above.
