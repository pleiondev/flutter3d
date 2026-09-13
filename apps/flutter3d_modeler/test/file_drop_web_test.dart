/// A file dragged onto the browser tab — `ui-31n`'s web half.
///
///     flutter test --platform chrome test/file_drop_web_test.dart
///
/// **A synthetic `drop` event, because a real one cannot be scripted.** There
/// is no way for a test — or anything else — to move an actual mouse holding
/// an actual file over a browser tab; the platform simply does not expose
/// drag-and-drop to automation the way a click or a key press can be sent.
/// What is reachable is the DOM event itself: `FileDropZone` listens for
/// `dragover` and `drop` on `document`, and a `DragEvent` built and
/// dispatched by hand is indistinguishable from one the browser fires during
/// a real drag, from the listener's own point of view. `ui-31n`'s own row
/// asks for exactly this.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/files/file_drop_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// A `drop` event carrying one file, the way a browser builds one from
/// whatever was dragged in.
web.DragEvent _dropOf(String name, Uint8List bytes) {
  // The same construction `project_files_web.dart`'s own `saveAs` already
  // uses for a `Blob` — a `File` is one with a name attached.
  final file = web.File(<JSUint8Array>[bytes.toJS].toJS, name);
  final transfer = web.DataTransfer()..items.add(file);
  return web.DragEvent('drop', web.DragEventInit(dataTransfer: transfer));
}

void main() {
  testWidgets('a dropped .glb reaches onDropped with its name and bytes', (
    WidgetTester tester,
  ) async {
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

    await tester.runAsync(() async {
      web.document.dispatchEvent(
        _dropOf('helmet.glb', Uint8List.fromList(<int>[1, 2, 3, 4])),
      );
      // `arrayBuffer()` is a real promise; nothing here resolves it but the
      // browser's own event loop.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(dropped, hasLength(1));
    expect(dropped.single.$1, 'helmet.glb');
    expect(dropped.single.$2, Uint8List.fromList(<int>[1, 2, 3, 4]));
  });

  testWidgets(
    'dragover is prevented, or the browser would navigate to the file',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FileDropZone(
            onDropped: (String name, Uint8List bytes) {},
            child: const SizedBox.expand(),
          ),
        ),
      );

      final event = web.Event('dragover', web.EventInit(cancelable: true));
      web.document.dispatchEvent(event);

      // Mutation: drop the `dragover` listener, or drop its
      // `preventDefault()` call, and this reads `false` — which in a real tab
      // is the browser leaving the page to open the file instead of firing
      // `drop` at all.
      expect(event.defaultPrevented, isTrue);
    },
  );
}
