/// A browser tab that already has a file dragged onto it.
///
/// **`dragover`/`drop` on the document, not a plugin.** A browser's default
/// answer to dropping a file anywhere in the page is to navigate the tab to
/// it, so `dragover` has to call `preventDefault` for `drop` to fire at all —
/// ten lines either way, the same reasoning `project_files_web.dart`'s own
/// doc comment gives for reading and writing a file the same way.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Wraps [child] so a file dropped anywhere on the page reaches [onDropped]
/// as a name and its bytes — the same shape a picker hands back, so a drop
/// and a pick end at the same call.
///
/// **Listens on the document, not on [child]'s own render box.** A person
/// drops a file wherever the pointer happens to be over the window, not
/// necessarily over whichever widget this wraps; `main.dart` wraps the whole
/// shell in this once, so "the document" and "the app" are the same area in
/// practice.
class FileDropZone extends StatefulWidget {
  const FileDropZone({super.key, required this.child, required this.onDropped});

  final Widget child;

  final void Function(String name, Uint8List bytes) onDropped;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  /// Kept rather than recreated per call, so [dispose] removes the exact
  /// listener [initState] added — `removeEventListener` matches by identity.
  late final JSFunction _onDragOver;
  late final JSFunction _onDrop;

  @override
  void initState() {
    super.initState();
    _onDragOver = ((web.Event event) => event.preventDefault()).toJS;
    _onDrop = ((web.Event event) => _handleDrop(event)).toJS;
    web.document.addEventListener('dragover', _onDragOver);
    web.document.addEventListener('drop', _onDrop);
  }

  void _handleDrop(web.Event event) {
    event.preventDefault();
    final files = (event as web.DragEvent).dataTransfer?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i)!;
      // `arrayBuffer()` rather than a `FileReader`, the same choice
      // `project_files_web.dart`'s own `_pickFiles` already made.
      file.arrayBuffer().toDart.then((JSArrayBuffer buffer) {
        widget.onDropped(file.name, buffer.toDart.asUint8List());
      });
    }
  }

  @override
  void dispose() {
    web.document.removeEventListener('dragover', _onDragOver);
    web.document.removeEventListener('drop', _onDrop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
