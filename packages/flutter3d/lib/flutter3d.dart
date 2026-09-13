/// A 3D engine, written against a graphics vocabulary rather than a graphics
/// API.
///
/// Everything a consumer needs is exported here. The layout behind it is not
/// arbitrary and is worth knowing before reaching past this file:
///
/// - **This package names no graphics API.** It depends on `flutter3d_hardware` and
///   nothing below it, so an application chooses a backend package
///   today — and hands it to `Renderer.create`. That is checked, not intended:
///   `tool/structure.dart`'s "the engine names no backend" rule, which scans
///   this package's `lib/`. The rule named here until now — "the hardware
///   layer names no graphics API" — scans `flutter3d_hardware` and says
///   nothing whatever about this file's claim.
/// - `geometry`, `scene`, `assets` and `render/key_sort` need no device at all,
///   which is what lets bounds, culling, framing, picking, decoding and sorting
///   be unit tested without one.
///
/// The shader bundle is still an asset of *this* package, and that is a known
/// wrinkle rather than a decision: a compiled bundle is one backend's output,
/// so it belongs with
/// the backend that can read it. The GLSL it is built from is shared. Moving it
/// is a question about where shader sources live, which is worth answering on
/// its own rather than as a side effect of the package split.
/// `packages/flutter3d_impeller/tool/build_shaders.sh` builds it — beside the
/// backend that needs it, not beside this package — and it has to be rebuilt
/// after every Flutter SDK change.
library;

// The rendering core: animation, assets, the render graph and the scene
// graph — everything that resolves without the Flutter SDK, which mcp-03n
// moved to its own package once the four files that did not were down to
// four small seams. See `flutter3d_core`'s own doc comment for the full
// account of what moved and why.
export 'package:flutter3d_core/flutter3d_core.dart';
// Assets: the formats and the documents they decode into are
// `package:flutter3d_formats` — glTF/GLB, OBJ, the project's own .f3d container
// and its .fmat material, `ModelDocument`, `SurfaceMaterial`, `LightingModel`
// and the synchronous half of loading. Exported whole, so an application that
// imports the engine keeps every name it had — except `Ktx2Texture`, which
// this package's own `src/engine/assets/ktx2/ktx2.dart` exports below: that
// one carries a `TextureFormat`, this one only a raw `vkFormat` (`ap-01`).
export 'package:flutter3d_formats/flutter3d_formats.dart' hide Ktx2Texture;
// Geometry: CPU-side meshes, the shapes that generate them and the ray
// arithmetic that reads one, all of it `package:flutter3d_geometry` since the
// day a program with no Flutter SDK had to be able to say `MeshData`. Exported
// whole, so an application that imports the engine keeps every name it had.
export 'package:flutter3d_geometry/flutter3d_geometry.dart';
// The graphics vocabulary, re-exported from `flutter3d_hardware`.
//
// Re-exported rather than left for a consumer to depend on separately, because
// these names are all over this package's own API — a `Material` holds
// `SamplerOptions`, a `RenderNode` is handed a `GraphicsDevice` — and a
// consumer should not have to add a dependency to spell the type of something
// this package handed them.
//
// The backend is deliberately **not** re-exported. An application picks one and
// depends on one by name; there are three today — `flutter3d_impeller`,
// `flutter3d_webgl` and `flutter3d_cpu` — and room for more.
// That choice is the one thing that must stay visible in an application's
// pubspec.
export 'package:flutter3d_hardware/flutter3d_hardware.dart';

// What could not go with it, each because it needs something this package may
// name and that one may not: the two Flutter-named asset sources and glTF
// resolvers, `defaultImageDecoder`, and everything from `ModelAsset` down
// that defaults to it.
export 'src/engine/assets/bundle_asset_source.dart';
export 'src/engine/assets/default_image_decoder.dart';
export 'src/engine/assets/gltf_resolvers.dart';
export 'src/engine/assets/material_loader.dart';
export 'src/engine/assets/model_asset.dart';
// Particles are `package:flutter3d_particles` and are named nowhere here.
// The engine defines what a contributor is; what draws through one is not its
// business, which is the whole test of the extension model.
