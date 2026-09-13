/// `export` over `flutter3d_formats`' own list of writers, and `import`
/// through the decoders the session hands its reads.
///
///     dart test test/export_formats_test.dart
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late ModelSession session;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_formats',
    );
    session = ModelSession.open('${workspace.path}/part.f3dproj');
    expect(session.run(const AddPrimitive(kind: 'box')).did, isTrue);
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  test('an agent can write every format the engine can, STL included', () {
    // Mutation: go back to the session's own list of three suffixes. The
    // engine's `encodeModel` writes STL and an agent asking for one is told
    // it is not a format.
    final binary = session.export('${workspace.path}/part.stl');
    expect(binary.did, isTrue, reason: binary.says);
    expect(
      isBinaryStl(File('${workspace.path}/part.stl').readAsBytesSync()),
      isTrue,
    );

    final text = session.export(
      '${workspace.path}/text.stl',
      format: 'stlAscii',
    );
    expect(text.did, isTrue, reason: text.says);
    expect(
      looksLikeAsciiStl(File('${workspace.path}/text.stl').readAsBytesSync()),
      isTrue,
    );
  });

  test('a format nobody writes is refused with the ones that are there', () {
    final refused = session.export('${workspace.path}/part.dae');
    expect(refused.did, isFalse);
    expect(refused.says, contains('"usdz"'));
  });

  test(
    'an FBX to import names itself rather than opening as nothing',
    () async {
      // Mutation: drop the FBX decoder from the session's request. The bytes
      // are sniffed as OBJ and the answer is that the file held nothing.
      final path = '${workspace.path}/rig.fbx';
      File(path).writeAsBytesSync('; FBX 7.4.0 project file\n'.codeUnits);
      final answer = await session.import(path);
      expect(answer.did, isFalse);
      expect(answer.says, contains('FBX'));
    },
  );
}
