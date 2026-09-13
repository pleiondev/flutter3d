/// A file dragged onto the desktop window — `ui-31n`'s macOS half.
///
///     flutter test test/file_drop_io_test.dart
///
/// **Driven through the real `desktop_drop` channel, not a fake of it.**
/// `DesktopDrop` registers a `MethodChannel('desktop_drop')` handler for
/// calls the native side makes; sending it the same two calls a real drop
/// delivers — `entered` then `performOperation` — exercises the plugin's own
/// dispatch and this file's `FileDropZone` together, reading a real file off
/// disk the way a dropped one would be.
///
/// **What this cannot reach: the native half beneath the channel.** A
/// platform actually noticing a file dragged onto a window and calling this
/// channel in the first place needs a real window and a person's hand — see
/// `integration_test/` for the one place this repository checks a claim
/// against the real platform rather than a simulated one. Nothing here
/// stands in for that; it proves the Dart side of the wire does what a drop
/// arriving on it should.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/files/file_drop_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Before anything below reaches for a binary messenger — the same order
  // `android_test.dart`'s own channel group already needs it in.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('file_drop_io_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  const channel = MethodChannel('desktop_drop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// One call on the channel `DesktopDrop.instance.init()` listens on — the
  /// shape the native plugin side sends, not a shortcut into this package's
  /// own listener list.
  Future<void> send(String method, Object? arguments) async {
    final message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await messenger.handlePlatformMessage(channel.name, message, (_) {});
  }

  testWidgets(
    'a file dropped on the window reaches onDropped with its bytes',
    (WidgetTester tester) async {
      final file = File('${dir.path}/helmet.glb')
        ..writeAsBytesSync(<int>[1, 2, 3, 4]);
      final dropped = <(String, Uint8List)>[];

      await tester.pumpWidget(
        MaterialApp(
          home: FileDropZone(
            onDropped: (String name, Uint8List bytes) =>
                dropped.add((name, bytes)),
            child: const SizedBox.expand(),
          ),
        ),
      );

      // `runAsync`, because reading the dropped file is real `dart:io`, not a
      // microtask `pump` alone would let finish.
      await tester.runAsync(() async {
        // A pointer has to enter the drop target before `desktop_drop` itself
        // will report a drop inside it — see `_DropTargetState._onDropEvent`.
        await send('entered', <double>[10, 10]);
        await send('performOperation', <String>[file.path]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      expect(dropped, hasLength(1));
      expect(dropped.single.$1, 'helmet.glb');
      expect(dropped.single.$2, Uint8List.fromList(<int>[1, 2, 3, 4]));
    },
  );

  testWidgets(
    'a drop outside the target is not reported',
    (WidgetTester tester) async {
      final file = File('${dir.path}/helmet.glb')
        ..writeAsBytesSync(<int>[1, 2, 3, 4]);
      final dropped = <(String, Uint8List)>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              SizedBox(
                height: 100,
                child: FileDropZone(
                  onDropped: (String name, Uint8List bytes) =>
                      dropped.add((name, bytes)),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.runAsync(() async {
        // Mutation: drop this guard and every file dragged anywhere onto the
        // window — including over a menu that happens to sit outside the
        // zone in some future layout — opens as if it landed on the target.
        await send('entered', <double>[10, 500]);
        await send('performOperation', <String>[file.path]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      expect(dropped, isEmpty);
    },
  );
}
