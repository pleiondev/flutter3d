# Models

## `car.glb` — "Race car" from the Car Kit

| | |
|---|---|
| Author | Kenney — https://kenney.nl |
| Source | Car Kit 3.1, `race.glb` — https://kenney.nl/assets/car-kit |
| Licence | **CC0 1.0** — http://creativecommons.org/publicdomain/zero/1.0/ |

CC0 asks for nothing. It replaces a real racing car whose livery carried its
sponsors' trademarks, which a public repository and a demo anybody can play
had no business shipping.

**Modified**, by `tool/prepare_models.py`, in three ways:

* the atlas is inside the file, as with the buildings below;
* the body's paint is a primitive and a material of its own, `paint`: the
  triangles whose middle samples the body's red swatch, with copies of
  their corners sampling a white texel of the same atlas, so a game can give
  each car a colour and leave its tyres, glass and stripes as they are;
* one root over the kit's five nodes scales the car until its axles are
  2.7 m apart, the wheel base `SphereVehicle` steers by — the kit draws at no
  scale in particular, and the one length of a car the simulation knows is
  the one to match.

The kit's car faces +Z, the way `SphereVehicle` drives at a heading of
nought, so it is not turned.

## `building-a.glb`, `building-e.glb`, `building-k.glb`, `building-q.glb`

| | |
|---|---|
| Author | Kenney — https://kenney.nl |
| Source | City Kit (Suburban) 2.0 — https://kenney.nl/assets/city-kit-suburban |
| Licence | **CC0 1.0** — http://creativecommons.org/publicdomain/zero/1.0/ |

CC0 asks for nothing, so this table is a note to ourselves rather than a
condition being met: where these came from, and that nobody has to be credited
if the roadside grows.

Four of the pack's forty, renamed from `building-type-*.glb`.

**Modified in one way: the texture is now inside the file.** The pack ships each
`.glb` referencing `Textures/colormap.png` beside it, which is legal glTF and
useless to a bundle — the loader resolves nothing relative to an asset path, so
every building arrived untextured and drew plain white. The PNG is appended as a
buffer view and the image points at it, which is what `car.glb` also gets and
what makes a model one file rather than two. The kit is authored two units to a building and this
game is in metres, so the scale lives at the call site in `src/roadside.dart`
rather than in the file — a house that is eight metres across on one circuit
may want to be ten on another, and baking that into the asset would make it a
property of the model instead of a property of the placement.
