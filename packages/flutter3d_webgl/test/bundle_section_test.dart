/// The `webgl` section of a loadable bundle: what the packer writes and the
/// device reads, held to being one document.
///
/// Pure text in and out, so this runs on the VM and in the browser alike —
/// which is the point of the codec living in a file with no `package:web`
/// in it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_webgl/src/webgl_bundle_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sources survive the round trip by stage kind', () {
    // Mutation: write both maps under one key and the fragment comes back
    // under vertex.
    final bytes = encodeWebGlSection(
      vertex: <String, String>{'MeshVertex': 'void main() {}'},
      fragment: <String, String>{'Stripes': 'out vec4 c; void main() {}'},
    );
    final back = decodeWebGlSection(bytes);
    expect(back.vertex, <String, String>{'MeshVertex': 'void main() {}'});
    expect(back.fragment, <String, String>{
      'Stripes': 'out vec4 c; void main() {}',
    });
  });

  test('a section that is not the document is a FormatException', () {
    // Each shape the device would otherwise read as an empty library: not
    // JSON, JSON that is not an object, an object with a map missing, and a
    // source that is not a string. Every one is a message rather than a
    // bundle with no stages in it.
    ByteData text(String s) =>
        Uint8List.fromList(utf8.encode(s)).buffer.asByteData();
    for (final bad in <ByteData>[
      text('not json'),
      text('[]'),
      text('{"vertex": {}}'),
      text('{"vertex": {}, "fragment": {"Stripes": 3}}'),
    ]) {
      expect(() => decodeWebGlSection(bad), throwsFormatException);
    }
  });
}
