/// `probeSandbox`'s own container lines — `ui-20`'s acceptance line asks for
/// a save under the sandbox to pass in a `flutter test` on a macOS runner.
///
/// **What this can and cannot stand in for.** `flutter test` runs the probe
/// as a plain, unsigned process — it is never actually confined by
/// `Release.entitlements`, so a pass here does not by itself prove the real
/// sandboxed app can still write its container; that half is `p0-13n`'s own
/// manual run, recorded in `doc/model-editor.md`, because reaching a signed,
/// sandboxed process needs a person. What this test does prove, on every
/// run of the suite rather than once by hand, is that `probeSandbox`'s own
/// write path — the one `ui-18`'s autosave and `saveAs`'s "container" case
/// both go through — still writes and still renames on whatever this runner
/// calls its application-support directory. `path_provider` is mocked only
/// for *which directory that is*; the write, the length read-back and the
/// delete are real `dart:io`, against a real temporary directory standing in
/// for the container.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/files/sandbox_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory container;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    container = Directory.systemTemp.createTempSync('sandbox_probe_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return container.path;
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.deleteSync(recursive: true);
  });

  test(
    'a direct write and a temp-file rename both land in the container',
    () async {
      final lines = await probeSandbox();

      final direct = lines.singleWhere(
        (line) => line.what == 'the container, directly',
      );
      final renamed = lines.singleWhere(
        (line) => line.what == 'the container, temp + rename',
      );

      expect(direct.worked, isTrue, reason: direct.said);
      expect(renamed.worked, isTrue, reason: renamed.said);

      // The probe cleans up after itself; nothing it wrote should still be
      // sitting in the container once it has answered.
      expect(container.listSync(), isEmpty);
    },
  );
}
