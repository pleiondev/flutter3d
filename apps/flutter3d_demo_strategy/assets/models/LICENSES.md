# Models

Every model here is Kenney's, CC0 1.0
(http://creativecommons.org/publicdomain/zero/1.0/). The full record —
models and textures, file by file, with where each came from — is
[`../CREDITS.md`](../CREDITS.md); this table is the short form the credits
test reads.

| File | Pack | Source |
|---|---|---|
| `castle-tower-hexagon-base.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-tower-hexagon-mid.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-tower-hexagon-roof.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-tower-square-base.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-tower-square-mid-windows.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-tower-square-top-roof-high.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-wall.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-flag.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-flag-banner-long.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `castle-siege-ram.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `arena-soldier.glb` | Mini Arena | https://kenney.nl/assets/mini-arena |
| `arena-spear.glb` | Mini Arena | https://kenney.nl/assets/mini-arena |
| `blocky-p.glb` | Blocky Characters | https://kenney.nl/assets/blocky-characters |
| `blocky-k.glb` | Blocky Characters | https://kenney.nl/assets/blocky-characters |
| `nature-tree_pineTallA_detailed.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-tree_pineRoundC.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-tree_oak.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-tree_default.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-tree_detailed.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-stone_tallA.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-stone_largeA.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |
| `nature-stone_smallA.glb` | Nature Kit | https://kenney.nl/assets/nature-kit |

**Every one is modified**, by `tool/prepare_models.py`: the reference to the
kit's sibling `Textures/*.png` is taken out (the game picks the texture
itself, and needs the castle's palette in two team colours anyway), and the
characters lose their animation clips, which a crowd drawn as one instanced
batch never plays. Geometry is untouched; `lib/src/kit.dart` composes the
pieces — a hall is a dozen castle pieces joined into one mesh — at load.
