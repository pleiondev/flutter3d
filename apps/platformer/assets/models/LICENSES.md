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
stated. Two changes, both by `tool/shrink_glb.py` and a short script beside it:

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
