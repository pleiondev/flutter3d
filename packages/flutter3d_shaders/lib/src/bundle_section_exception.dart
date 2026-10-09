import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException;

/// A backend's section of a shader bundle that is not the document its
/// decoder reads: not UTF-8, not JSON, or missing a field.
///
/// The device that asked turns it into a `ShaderBundleException` naming the
/// bundle; this is the sentence about the section that goes inside it.
final class BundleSectionFormatException extends Flutter3dFormatException {
  const BundleSectionFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'BundleSectionFormatException: $message';
}

/// The JSON document [bytes] hold, or a [BundleSectionFormatException] saying
/// why they hold none: the SDK's own `FormatException` from the UTF-8 or JSON
/// decoder is the one thing a section decoder would otherwise let out bare.
Object? decodeSectionJson(ByteData bytes) {
  try {
    return jsonDecode(
      utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  } on FormatException catch (error) {
    throw BundleSectionFormatException(
      'the section is not UTF-8 JSON: ${error.message}',
    );
  }
}
