// The tape parity on a device: a phone, a simulator or this desktop, run
// from an application that has both games, the racing demo's:
//
//     cd apps/flutter3d_demo_racing
//     flutter test -d <device-id> \
//       ../../packages/flutter3d_physics_native/tool/tape_parity/tape_digests_device_test.dart \
//       --dart-define-from-file=<defines.json>
//
// `tool/digest_platforms.sh tapes device:<id>` writes the defines and runs
// it. A device reads neither the repository nor the host's disk, so the
// tapes and their levels arrive as one define, `F3D_TAPE_PARITY_GZIP`: a
// JSON map of file name to contents, gzipped, in base64. See
// `tape_play.dart` for what is played and digested.
// ignore_for_file: depend_on_referenced_packages, avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'tape_play.dart';

const String _staged = String.fromEnvironment('F3D_TAPE_PARITY_GZIP');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final files = _staged.isEmpty
      ? const <String, Object?>{}
      : (jsonDecode(utf8.decode(gzip.decode(base64.decode(_staged)))) as Map)
            .cast<String, Object?>();
  Future<String> read(String name) async => switch (files[name]) {
    final String contents => contents,
    _ => throw StateError(
      '$name was not handed in: run tool/digest_platforms.sh tapes '
      'device:<id>',
    ),
  };

  testWidgets('the tapes on the core', (tester) async {
    print('parity physics ${await startCore()}');
    for (final name in tapes) {
      (await playTape(name, read)).forEach(print);
    }
  });
}
