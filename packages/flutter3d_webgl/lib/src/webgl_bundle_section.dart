/// The WebGL section of a `ShaderBundle`: GLSL ES 3.00 sources by name.
///
/// A JSON document, `{"vertex": {name: source}, "fragment": {name: source}}`,
/// as UTF-8. Text rather than anything compiled, because that is what this
/// backend compiles from: the browser is the compiler, and there is nothing
/// to run ahead of time except the translation from the engine's GLSL, which
/// `tool/pack_shaders.dart` does when it writes the section.
///
/// **No `package:web` here, on purpose.** The packer runs on the Dart VM,
/// where a browser binding does not load, and it has to write exactly what
/// the device reads. One file both import is how the two stay the same
/// document.
library;

import 'dart:convert';
import 'dart:typed_data';

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
/// Throws [FormatException] when the bytes are not the document above — the
/// device turns that into a refusal naming the bundle.
WebGlSectionSources decodeWebGlSection(ByteData bytes) {
  final text = utf8.decode(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  final document = jsonDecode(text);
  if (document is! Map<String, dynamic>) {
    throw const FormatException('the section is not a JSON object');
  }
  Map<String, String> stages(String kind) {
    final entries = document[kind];
    if (entries is! Map<String, dynamic>) {
      throw FormatException('the section has no "$kind" object');
    }
    return <String, String>{
      for (final entry in entries.entries)
        entry.key: switch (entry.value) {
          final String source => source,
          _ => throw FormatException(
            '"${entry.key}" under "$kind" is not a source string',
          ),
        },
    };
  }

  return (vertex: stages('vertex'), fragment: stages('fragment'));
}
