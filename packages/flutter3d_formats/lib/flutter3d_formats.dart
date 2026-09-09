/// The formats a model arrives in and leaves in: the document every decoder
/// produces, the materials it names, and the readers for glTF/GLB, OBJ and the
/// engine's own `.f3d` and `.fmat`.
///
/// **A package rather than a directory, for the reason `flutter3d_geometry` is
/// one:** `flutter3d` declares `flutter: sdk`, and none of this needs it. A
/// modeller's document layer, the server an agent starts with `dart run`, a
/// service that checks an uploaded asset and a plain `dart test` all want to
/// read a `.glb` and none of them can resolve a Flutter SDK to do it. Every
/// file here named Flutter nowhere before it moved; what moved is the pubspec
/// it resolves against.
///
/// **What stayed in `flutter3d` is what actually needs a window.**
/// `decodeModelInIsolate` spawns the isolate and answers `kIsWeb`;
/// `BundleAssetSource` reads Flutter's asset bundle and `FileAssetSource` reads
/// `dart:io`; `gltf_resolvers.dart` resolves through an `AssetBundle`;
/// `ModelAsset`, `ModelPart` and the KTX2 reader name a `GraphicsDevice`. The
/// line is drawn at bytes: this package turns bytes into a document, and the
/// engine is what fetches the bytes and uploads the result.
///
/// `flutter3d` exports this package whole, so an application that imports the
/// engine keeps every name it had.
library;

export 'src/animation/animation_clip.dart';
// `AnimationMask` came with the clip because `ModelDocument` builds one:
// `maskUnder` answers which joints a layer may touch, and the document is what
// knows the hierarchy. The player and the layers that read a mask stayed in
// `flutter3d`, which is where a pose is applied to a scene.
export 'src/animation/animation_mask.dart';
export 'src/animation/animation_track.dart';
export 'src/asset_resolver.dart';
export 'src/asset_source.dart';
export 'src/f3d/f3d.dart';
export 'src/fmat/fmat.dart';
export 'src/gltf/gltf.dart';
export 'src/lighting_model.dart';
export 'src/material_document.dart';
export 'src/material_hint.dart';
export 'src/model_document.dart';
export 'src/model_loader.dart';
export 'src/model_node.dart';
export 'src/obj/obj.dart';
export 'src/surface_material.dart';
