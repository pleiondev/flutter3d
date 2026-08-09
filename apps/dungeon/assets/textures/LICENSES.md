# Texture provenance

Every texture here was fetched by `tool/fetch_textures.py`, which is
the record of where it came from. Re-run that script to reproduce
this directory.

All of it is from [ambientCG](https://ambientcg.com), published under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) — public
domain, no attribution required. The credits below are given because
not being required to say where something came from is a poor reason
not to.

| File prefix | Source | Licence | Used for |
| --- | --- | --- | --- |
| `wall_*` | [Bricks075A](https://ambientcg.com/view?id=Bricks075A) | CC0 1.0 | Irregular stone blocks, the walls of the crypt |
| `floor_*` | [PavingStones151](https://ambientcg.com/view?id=PavingStones151) | CC0 1.0 | Grey setts, the floors |
| `ceiling_*` | [Concrete042A](https://ambientcg.com/view?id=Concrete042A) | CC0 1.0 | Mottled grey, the ceilings |
| `stone_*` | [PavingStones128](https://ambientcg.com/view?id=PavingStones128) | CC0 1.0 | Cut ashlar, pillars and stairs |
| `metal_*` | [Metal046B](https://ambientcg.com/view?id=Metal046B) | CC0 1.0 | Dark worn iron, doors and lifts |

Each prefix has three files: `_albedo.jpg` (sRGB base colour),
`_normal.png` (tangent space, OpenGL green-up) and `_orm.png`
(occlusion in red, roughness in green, metallic in blue — glTF's
packing).

## The key

`key_*` and `assets/models/key.glb` are **not** from ambientCG and their
licence is **unrecorded**. The archive they came from (`key.zip`, a Cinema 4D
export dated 2019, repackaged 2022) carries no licence file, no readme and no
author — only an OBJ and four texture maps.

That is a blocker for shipping, not a formatting problem: an asset whose terms
nobody can point to cannot be redistributed, and "we could not find the licence"
is not a defence. Before this game is published the key has to be traced to its
source and its terms written here, or replaced.

The model was prepared by `tool/prepare_model.mjs` (decimated to 2 499
triangles, scaled to 0.6 m, tangents generated with MikkTSpace) and its maps
packed by `tool/pack_maps.py`.
