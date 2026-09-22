/// `WindowCapture`'s own subprocess commands, against a fake
/// [ProcessRunner] — what each method asks the shell to run, and how it
/// reacts to a non-zero exit. Not the real `swift`/`screencapture`
/// processes themselves; see `WindowCapture`'s own doc comment for why
/// those need a real macOS run.
///
///     dart test tool/tutorial/test/window_capture_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tutorial/tutorial.dart';

ProcessResult _ok({Object stdout = '', Object stderr = ''}) =>
    ProcessResult(0, 0, stdout, stderr);

ProcessResult _failed({Object stdout = '', Object stderr = 'boom'}) =>
    ProcessResult(0, 1, stdout, stderr);

void main() {
  group('findWindowId', () {
    test('runs swift on window_id.swift with the process name', () async {
      String? executable;
      List<String>? arguments;
      final capture = WindowCapture(
        windowIdScript: '/repo/tool/tutorial/window_id.swift',
        run: (exe, args) async {
          executable = exe;
          arguments = args;
          return _ok(stdout: '42\n');
        },
      );

      final id = await capture.findWindowId('flutter3d_modeler');

      expect(executable, 'swift');
      expect(arguments, <String>[
        '/repo/tool/tutorial/window_id.swift',
        'flutter3d_modeler',
      ]);
      expect(id, 42);
    });

    test('throws, naming the process, on a non-zero exit', () async {
      final capture = WindowCapture(
        windowIdScript: 'window_id.swift',
        run: (_, _) async => _failed(stderr: 'no on-screen window'),
      );

      await expectLater(
        capture.findWindowId('flutter3d_modeler'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('flutter3d_modeler'),
          ),
        ),
      );
    });
  });

  group('capture', () {
    test('runs screencapture -x -l <id> <path>', () async {
      String? executable;
      List<String>? arguments;
      final capture = WindowCapture(
        windowIdScript: 'window_id.swift',
        run: (exe, args) async {
          executable = exe;
          arguments = args;
          return _ok();
        },
      );

      final tempDir = Directory.systemTemp.createTempSync(
        'window_capture_test',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final outputPath = '${tempDir.path}/case/01-front.png';

      await capture.capture(42, outputPath);

      expect(executable, 'screencapture');
      expect(arguments, <String>['-x', '-l', '42', outputPath]);
      // The parent directory is created even though nothing was actually
      // written to it — the fake runner never touches the filesystem.
      expect(Directory('${tempDir.path}/case').existsSync(), isTrue);
    });

    test('throws, naming the window id, on a non-zero exit', () async {
      final capture = WindowCapture(
        windowIdScript: 'window_id.swift',
        run: (_, _) async => _failed(),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'window_capture_test',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      await expectLater(
        capture.capture(7, '${tempDir.path}/x.png'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('7')),
        ),
      );
    });
  });
}
