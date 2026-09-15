/// The formats a model arrives in and leaves in: the document every decoder
/// produces, the materials it names, the readers and writers for glTF/GLB,
/// OBJ, STL, USDZ and the engine's own `.f3d` and `.fmat`, the FBX decoder that
/// recognises a file and refuses it with a reason, the image codecs, and the
/// KTX2 container a compressed texture sits in.
///
/// **A library of `flutter3d_core`, importable on its own.** A modeller's
/// document layer, the server an agent starts with `dart run`, a service that
/// checks an uploaded asset and a plain `dart test` all read a `.glb` or a
/// `.ktx2`; none of them resolves a Flutter SDK, and none of them has to import
/// the renderer to do it. This was `flutter3d_formats` (and `flutter3d_fbx`)
/// until the package boundary turned out to protect nothing a library does not.
///
/// **The line is drawn at bytes.** This library turns bytes into a document.
/// The KTX2 reader stops at `vkFormat`, a Khronos number; mapping it to the
/// hardware's own `TextureFormat` is the engine's `Ktx2Texture`, which is why
/// `flutter3d_core.dart` exports this library with this one's `Ktx2Texture`
/// hidden. What fetches the bytes — the asset bundle, the isolate — and what
/// uploads the result is the renderer's.
library;

export 'src/formats/animation/animation_clip.dart';
// `AnimationMask` came with the clip because `ModelDocument` builds one:
// `maskUnder` answers which joints a layer may touch, and the document is what
// knows the hierarchy. The player and the layers that read a mask stayed in
// `flutter3d`, which is where a pose is applied to a scene.
export 'src/formats/animation/animation_mask.dart';
export 'src/formats/animation/animation_track.dart';
export 'src/formats/asset_resolver.dart';
export 'src/formats/asset_source.dart';
export 'src/formats/document_compare.dart';
export 'src/formats/export_report.dart';
export 'src/formats/f3d/f3d.dart';
export 'src/formats/fbx/fbx_decoder.dart';
export 'src/formats/fmat/fmat.dart';
export 'src/formats/gltf/gltf.dart';
export 'src/formats/image/deflate.dart';
export 'src/formats/image/inflate.dart';
export 'src/formats/image/jpeg_decoder.dart';
export 'src/formats/image/png_decoder.dart';
export 'src/formats/image/png_encoder.dart';
export 'src/formats/image/pure_dart_image_decoder.dart';
export 'src/formats/image_sniff.dart';
export 'src/formats/ktx2/encode/astc4x4_encoder.dart'
    show encodeAstc4x4, encodeAstc4x4Block;
export 'src/formats/ktx2/encode/bc1_encoder.dart' show encodeBc1;
export 'src/formats/ktx2/encode/bc3_encoder.dart' show encodeBc3;
export 'src/formats/ktx2/encode/etc2_encoder.dart'
    show encodeEtc2Rgb8, encodeEtc2Rgb8Block;
export 'src/formats/ktx2/encode/ktx2_writer.dart' show writeKtx2;
export 'src/formats/ktx2/encode/mip_chain.dart' show buildMipChain;
export 'src/formats/ktx2/encode/rgba8_image.dart' show Rgba8Image;
export 'src/formats/ktx2/ktx2.dart';
export 'src/formats/lighting_model.dart';
export 'src/formats/material_document.dart';
export 'src/formats/material_hint.dart';
export 'src/formats/model_document.dart';
export 'src/formats/model_loader.dart';
export 'src/formats/model_node.dart';
export 'src/formats/model_writer.dart';
export 'src/formats/obj/obj.dart';
export 'src/formats/plain_model_document.dart';
export 'src/formats/stl/stl.dart';
export 'src/formats/surface_material.dart';
export 'src/formats/usdz/usdz.dart';
