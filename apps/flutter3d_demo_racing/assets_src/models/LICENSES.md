# Models

## `car.glb` — "2002 McLaren MP4-17"

| | |
|---|---|
| Author | Dave Love — https://sketchfab.com/Tyler_Dave |
| Source | https://sketchfab.com/3d-models/2002-mclaren-mp4-17-bf74904934284bbbb5e3c69f1650bdba |
| Licence | **CC BY 4.0** — http://creativecommons.org/licenses/by/4.0/ |

Attribution is a condition of the licence, so it is written here, and it must
appear wherever the game does — a credits screen, a store page, a README.

The licence is not guessed: the downloaded file carries it in `asset.extras`,
along with the author and the source, and those three fields are where the table
above comes from.

**The file in this repository is modified**, which CC BY also requires be
stated. Three changes, all by `tool/prepare_models.py`:

* the twenty-four maps of 1024×1024 are resized to 512×512, and the eight
  already at 512 are left alone — this stack has no compressed texture formats,
  so every map costs raw RGBA in device memory whatever its PNG weighed, and
  twenty-four of them at 1024 is ninety-six megabytes of it. The maps smaller
  than 512 are deliberately untouched: `sips -Z` *sets* the long edge rather
  than capping it, so running it over a 32-pixel map returns a 512-pixel one
  holding exactly as much detail and sixteen times the memory;
* `KHR_materials_specular` and `KHR_materials_clearcoat` are removed. Neither is
  in `extensionsRequired`, so a loader may ignore them — but this one has no
  clearcoat, and a file that still claims the extension is a file that two
  loaders can read two ways;
* the scene root is turned half a turn about the vertical, so that the car faces
  the way `SphereVehicle` drives. glTF says a model faces −Z and the car drives
  towards +Z at a heading of nought; this reconciles them once, in the asset,
  rather than at every place the car is drawn.

**Not** resized. The model measures 4.32 m nose to tail and an MP4-17 measures
4.5, so it is left at the size it was authored: a car scaled to look right is a
car whose mirrors are the wrong size for the track it is on.

### The half turn, checked

It rested on the exporter having kept glTF's convention, which the file does not
state and which nothing in the model settled: the meshes are named `Object_4`
upwards, and the geometry at the two ends is closer in height than a front and a
rear wing should be, so guessing from the shape was not on.

**Checked on screen instead, and it is right.** With the chase camera behind the
car, what faces the camera is the rear wing and the diffuser — which is what the
back of a car looks like. If some future export ever comes out backwards, the
line to change is `TURN_TO_FACE_FORWARD` in `tool/prepare_models.py`.

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
buffer view and the image points at it, which is what `car.glb` already does and
what makes a model one file rather than two. The kit is authored two units to a building and this
game is in metres, so the scale lives at the call site in `src/roadside.dart`
rather than in the file — a house that is eight metres across on one circuit
may want to be ten on another, and baking that into the asset would make it a
property of the model instead of a property of the placement.
