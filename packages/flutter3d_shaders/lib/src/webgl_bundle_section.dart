/// The WebGL section of a `ShaderBundle`: GLSL ES 3.00 sources by name.
///
/// A JSON document, `{"vertex": {name: source}, "fragment": {name: source}}`,
/// as UTF-8. Text rather than anything compiled, because that is what the
/// WebGL backend compiles from: the browser is the compiler, and there is
/// nothing to run ahead of time except the translation from the engine's GLSL,
/// which `flutter3d_webgl/tool/pack_shaders.dart` and `flutter3d_build`'s
/// material step do when they write the section.
///
/// **No `package:web` here, on purpose.** The packers run on the Dart VM,
/// where a browser binding does not load, and they have to write exactly what
/// the device reads. One file every side imports is how they stay the same
/// document — which is also why it lives in `flutter3d_shaders` rather than in
/// `flutter3d_webgl`: a build hook cannot resolve a package that declares the
/// Flutter SDK.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'bundle_section_exception.dart';

/// What the section decodes to.
typedef WebGlSectionSources = ({
  Map<String, String> vertex,
  Map<String, String> fragment,
});

/// The section bytes for [vertex] and [fragment] sources.
ByteData encodeWebGlSection({
  required Map<String, String> vertex,
  required Map<String, String> fragment,
}) {
  final text = jsonEncode(<String, Object>{
    'vertex': vertex,
    'fragment': fragment,
  });
  return Uint8List.fromList(utf8.encode(text)).buffer.asByteData();
}

/// The sources in [bytes].
///
/// Throws [BundleSectionFormatException] when the bytes are not the document
/// above — the device turns that into a refusal naming the bundle.
WebGlSectionSources decodeWebGlSection(ByteData bytes) {
  final document = decodeSectionJson(bytes);
  if (document is! Map<String, dynamic>) {
    throw const BundleSectionFormatException(
      'the section is not a JSON object',
    );
  }
  Map<String, String> stages(String kind) {
    final entries = document[kind];
    if (entries is! Map<String, dynamic>) {
      throw BundleSectionFormatException('the section has no "$kind" object');
    }
    return <String, String>{
      for (final entry in entries.entries)
        entry.key: switch (entry.value) {
          final String source => source,
          _ => throw BundleSectionFormatException(
            '"${entry.key}" under "$kind" is not a source string',
          ),
        },
    };
  }

  return (vertex: stages('vertex'), fragment: stages('fragment'));
}
