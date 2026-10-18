# Block pictures

Every picture here is 256 by 256 pixels, one block face edge to edge: a
colour map `<name>.jpg` and an OpenGL-convention normal map
`<name>_normal.jpg`. All of them are made from ambientCG materials, which
are CC0. The 1K JPG download of each was taken down to 256 pixels and
graded by [`tool/make_block_pictures.py`](../../tool/make_block_pictures.py),
which reads only each material's `Color` and `NormalGL` maps.

| Files | Made from | Author | Licence |
| --- | --- | --- | --- |
| `stone.jpg`, `stone_normal.jpg` | [Rock030](https://ambientcg.com/view?id=Rock030), brightened | ambientCG (Lennart Demes) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `dirt.jpg`, `dirt_normal.jpg` | [Ground106](https://ambientcg.com/view?id=Ground106) | ambientCG | CC0 1.0 |
| `grass_top.jpg`, `grass_top_normal.jpg` | [Grass004](https://ambientcg.com/view?id=Grass004) | ambientCG | CC0 1.0 |
| `grass_side.jpg`, `grass_side_normal.jpg` | Ground106 under a fringe of Grass004, composed by the tool | ambientCG; composed for this sandbox | CC0 1.0 |
| `sand.jpg`, `sand_normal.jpg` | [Ground093A](https://ambientcg.com/view?id=Ground093A), darkened, its contrast raised | ambientCG | CC0 1.0 |
| `brick.jpg`, `brick_normal.jpg` | [Bricks085](https://ambientcg.com/view?id=Bricks085) | ambientCG | CC0 1.0 |
| `planks.jpg`, `planks_normal.jpg` | [Planks037A](https://ambientcg.com/view?id=Planks037A), brightened | ambientCG | CC0 1.0 |
| `gold.jpg`, `gold_normal.jpg` | [Metal048C](https://ambientcg.com/view?id=Metal048C), deepened, with a bevel worked into its border by the tool | ambientCG; bevel made for this sandbox | CC0 1.0 |

Each material's download is `https://ambientcg.com/get?file=<Id>_1K-JPG.zip`.
To make the pictures again, unzip each into a folder of its own name and run
`python3 tool/make_block_pictures.py <that directory>`.

CC0 asks for no credit; ambientCG is named here because the materials are
theirs.
