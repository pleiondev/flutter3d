/// The format exceptions of the readers in this package that had none of
/// their own, one per format.
///
/// **Each is a leaf of [Flutter3dFormatException]**, so a caller who reports
/// anything unreadable catches the family, and a caller who acts on one
/// format — an importer falling back from glTF to OBJ, a tool rebuilding a
/// broken `.fmat` — catches that format's. Before 1.0 these readers threw
/// `dart:core`'s bare `FormatException`, which a caller could not tell from a
/// `jsonDecode` or `utf8.decode` failure in its own code.
///
/// The formats that already had a leaf keep it beside their reader:
/// `F3dFormatException`, `Ktx2FormatException`, `HdrFormatException`,
/// `DracoException`, `MaterialSyntaxException` and the splat readers'.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException;

/// A glTF or GLB file the reader cannot read: a container that is not GLB, an
/// accessor that runs past its buffer, a component type or mode the
/// specification does not define.
final class GltfFormatException extends Flutter3dFormatException {
  const GltfFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'GltfFormatException: $message';
}

/// A `.fmat` material file that is not one: not a JSON object, no version
/// key, or a version newer than this build reads.
final class FmatFormatException extends Flutter3dFormatException {
  const FmatFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'FmatFormatException: $message';
}

/// A `.cube` colour lookup table the reader cannot read, naming the line.
final class CubeLutFormatException extends Flutter3dFormatException {
  const CubeLutFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'CubeLutFormatException: $message';
}

/// A meshopt-compressed buffer (`EXT_meshopt_compression`) that does not
/// decode: truncated, an unknown header, or a count that does not match.
final class MeshoptFormatException extends Flutter3dFormatException {
  const MeshoptFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MeshoptFormatException: $message';
}

/// An FBX file, which this build recognises and does not read yet.
final class FbxFormatException extends Flutter3dFormatException {
  const FbxFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'FbxFormatException: $message';
}

/// A `.f3dmat` bundle that holds no material, or one that cannot be told
/// apart from another. Syntax errors inside a material are
/// `MaterialSyntaxException`.
final class MaterialBundleException extends Flutter3dFormatException {
  const MaterialBundleException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MaterialBundleException: $message';
}

/// An animation graph's JSON (a model's `extras`) in a shape the reader does
/// not know, naming where in the document it went wrong.
final class AnimationGraphFormatException extends Flutter3dFormatException {
  const AnimationGraphFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'AnimationGraphFormatException: $message';
}

/// A frame capture (`FrameCapture.fromJson`) that is not one, or is from a
/// newer build: the message says which, and what to do about it.
final class FrameCaptureFormatException extends Flutter3dFormatException {
  const FrameCaptureFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'FrameCaptureFormatException: $message';
}

/// An image the pure decoders (PNG, JPEG) cannot read: a signature that is
/// not the format's, a chunk that runs past the end, a feature the decoder
/// does not implement.
final class ImageFormatException extends Flutter3dFormatException {
  const ImageFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'ImageFormatException: $message';
}

/// An animation pointer (`KHR_animation_pointer`) whose path this build
/// does not know how to resolve.
final class AnimationPointerFormatException extends Flutter3dFormatException {
  const AnimationPointerFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'AnimationPointerFormatException: $message';
}
