# Credits

Everything under `assets/models` and `assets/textures` that somebody else
made. All of it is CC0 1.0 (http://creativecommons.org/publicdomain/zero/1.0/),
which asks for nothing — this is a record, not a condition being met. The
levels in `assets/levels` are this repository's own (`tool/make_map.py`).

`tool/prepare_models.py` turns the downloaded archives into the files below;
run it on a folder holding the archives and the result is the same files.

## Models — Kenney (https://kenney.nl), CC0 1.0

| File | Pack, piece | Source |
|---|---|---|
| `models/castle-tower-hexagon-base.glb` | Castle Kit, `tower-hexagon-base` | https://kenney.nl/assets/castle-kit |
| `models/castle-tower-hexagon-mid.glb` | Castle Kit, `tower-hexagon-mid` | https://kenney.nl/assets/castle-kit |
| `models/castle-tower-hexagon-roof.glb` | Castle Kit, `tower-hexagon-roof` | https://kenney.nl/assets/castle-kit |
| `models/castle-tower-square-base.glb` | Castle Kit, `tower-square-base` | https://kenney.nl/assets/castle-kit |
| `models/castle-tower-square-mid-windows.glb` | Castle Kit, `tower-square-mid-windows` | https://kenney.nl/assets/castle-kit |
| `models/castle-tower-square-top-roof-high.glb` | Castle Kit, `tower-square-top-roof-high` | https://kenney.nl/assets/castle-kit |
| `models/castle-wall.glb` | Castle Kit, `wall` | https://kenney.nl/assets/castle-kit |
| `models/castle-flag.glb` | Castle Kit, `flag` | https://kenney.nl/assets/castle-kit |
| `models/castle-flag-banner-long.glb` | Castle Kit, `flag-banner-long` | https://kenney.nl/assets/castle-kit |
| `models/castle-siege-ram.glb` | Castle Kit, `siege-ram` | https://kenney.nl/assets/castle-kit |
| `models/arena-soldier.glb` | Mini Arena, `character-soldier` | https://kenney.nl/assets/mini-arena |
| `models/arena-spear.glb` | Mini Arena, `weapon-spear` | https://kenney.nl/assets/mini-arena |
| `models/blocky-p.glb` | Blocky Characters, `character-p` | https://kenney.nl/assets/blocky-characters |
| `models/blocky-k.glb` | Blocky Characters, `character-k` | https://kenney.nl/assets/blocky-characters |
| `models/nature-tree_pineTallA_detailed.glb` | Nature Kit, `tree_pineTallA_detailed` | https://kenney.nl/assets/nature-kit |
| `models/nature-tree_pineRoundC.glb` | Nature Kit, `tree_pineRoundC` | https://kenney.nl/assets/nature-kit |
| `models/nature-tree_oak.glb` | Nature Kit, `tree_oak` | https://kenney.nl/assets/nature-kit |
| `models/nature-tree_default.glb` | Nature Kit, `tree_default` | https://kenney.nl/assets/nature-kit |
| `models/nature-tree_detailed.glb` | Nature Kit, `tree_detailed` | https://kenney.nl/assets/nature-kit |
| `models/nature-stone_tallA.glb` | Nature Kit, `stone_tallA` | https://kenney.nl/assets/nature-kit |
| `models/nature-stone_largeA.glb` | Nature Kit, `stone_largeA` | https://kenney.nl/assets/nature-kit |
| `models/nature-stone_smallA.glb` | Nature Kit, `stone_smallA` | https://kenney.nl/assets/nature-kit |

Modified: texture references and animation clips removed (see
`models/LICENSES.md`); the geometry is as the kits ship it.

## Textures

| File | Work | Author | Source |
|---|---|---|---|
| `textures/castle-colormap.png` | Castle Kit, `Textures/colormap.png` | Kenney | https://kenney.nl/assets/castle-kit |
| `textures/arena-colormap.png` | Mini Arena, `Textures/colormap.png` | Kenney | https://kenney.nl/assets/mini-arena |
| `textures/blocky-p.png` | Blocky Characters, `Textures/texture-p.png` | Kenney | https://kenney.nl/assets/blocky-characters |
| `textures/blocky-k.png` | Blocky Characters, `Textures/texture-k.png` | Kenney | https://kenney.nl/assets/blocky-characters |
| `textures/grass.jpg` | Grass 001, colour map (1K) | ambientCG | https://ambientcg.com/view?id=Grass001 |
| `textures/meadow.jpg` | Grass 004, colour map (1K) | ambientCG | https://ambientcg.com/view?id=Grass004 |
| `textures/dirt.jpg` | Ground 048, colour map (1K) | ambientCG | https://ambientcg.com/view?id=Ground048 |
| `textures/rock.jpg` | Rock 030, colour map (1K) | ambientCG | https://ambientcg.com/view?id=Rock030 |
| `textures/sand.jpg` | Ground 054, colour map (1K) | ambientCG | https://ambientcg.com/view?id=Ground054 |

All CC0 1.0. Modified: scaled to no more than 512 px on a side, and only
the colour map of each ambientCG set is kept. The far side's
team colours are not a file: `lib/src/kit.dart` repaints the castle and arena
palettes at load, turning the accent blues red (and the soldiers' red plumes
blue for the near side).
