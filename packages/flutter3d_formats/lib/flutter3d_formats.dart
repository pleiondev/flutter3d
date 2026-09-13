/// The formats a model arrives in and leaves in: the document every decoder
/// produces, the materials it names, the readers for glTF/GLB, OBJ and the
/// engine's own `.f3d` and `.fmat`, and the KTX2 container a compressed
/// texture sits in.
///
/// **A package rather than a directory, for the reason `flutter3d_geometry` is
/// one:** `flutter3d` declares `flutter: sdk`, and none of this needs it. A
/// modeller's document layer, the server an agent starts with `dart run`, a
/// service that checks an uploaded asset and a plain `dart test` all want to
/// read a `.glb` or a `.ktx2` and none of them can resolve a Flutter SDK to do
/// it. Every file here named Flutter nowhere before it moved; what moved is
/// the pubspec it resolves against.
///
/// **What stayed in `flutter3d` is what actually needs a window.**
/// `decodeModelInIsolate` spawns the isolate and answers `kIsWeb`;
/// `BundleAssetSource` reads Flutter's asset bundle and `FileAssetSource` reads
/// `dart:io`; `gltf_resolvers.dart` resolves through an `AssetBundle`;
/// `ModelAsset` and `ModelPart` name a `GraphicsDevice`. The KTX2 reader here
/// stops at `vkFormat`, a Khronos number — mapping it to the engine's own
/// `TextureFormat` is a thin wrapper `flutter3d` keeps, for the same reason:
/// `TextureFormat` lives in `flutter3d_hardware`, which needs a window too.
/// The line is drawn at bytes: this package turns bytes into a document, and
/// the engine is what fetches the bytes, resolves the format and uploads the
/// result.
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
export 'src/document_compare.dart';
export 'src/export_report.dart';
export 'src/f3d/f3d.dart';
export 'src/fmat/fmat.dart';
export 'src/gltf/gltf.dart';
export 'src/image/deflate.dart';
export 'src/image/inflate.dart';
export 'src/image/jpeg_decoder.dart';
export 'src/image/png_decoder.dart';
export 'src/image/png_encoder.dart';
export 'src/image_sniff.dart';
export 'src/ktx2/encode/astc4x4_encoder.dart'
    show encodeAstc4x4, encodeAstc4x4Block;
export 'src/ktx2/encode/bc1_encoder.dart' show encodeBc1;
export 'src/ktx2/encode/bc3_encoder.dart' show encodeBc3;
export 'src/ktx2/encode/etc2_encoder.dart'
    show encodeEtc2Rgb8, encodeEtc2Rgb8Block;
export 'src/ktx2/encode/ktx2_writer.dart' show writeKtx2;
export 'src/ktx2/encode/mip_chain.dart' show buildMipChain;
export 'src/ktx2/encode/rgba8_image.dart' show Rgba8Image;
export 'src/ktx2/ktx2.dart';
export 'src/lighting_model.dart';
export 'src/material_document.dart';
export 'src/material_hint.dart';
export 'src/model_document.dart';
export 'src/model_loader.dart';
export 'src/model_node.dart';
export 'src/model_writer.dart';
export 'src/obj/obj.dart';
export 'src/plain_model_document.dart';
export 'src/stl/stl.dart';
export 'src/surface_material.dart';
export 'src/usdz/usdz.dart';
