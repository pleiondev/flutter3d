/// A window on a desktop that already has a file dragged onto it.
///
/// **`desktop_drop` rather than a channel of this package's own.** The web
/// half beside this one is ten lines of `dragover`/`drop` because that is all
/// a browser needs; a desktop drop needs a platform side registered per
/// window per OS, which is exactly the part a hand-rolled channel would have
/// to reinvent for four platforms to save one dependency.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

/// Wraps [child] so a file dropped anywhere over it reaches [onDropped] as a
/// name and its bytes — the same shape a picker hands back, so a drop and a
/// pick end at the same call.
class FileDropZone extends StatelessWidget {
  const FileDropZone({super.key, required this.child, required this.onDropped});

  final Widget child;

  final void Function(String name, Uint8List bytes) onDropped;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragDone: (DropDoneDetails details) {
      for (final DropItem file in details.files) {
        unawaited(_read(file));
      }
    },
    child: child,
  );

  Future<void> _read(DropItem file) async {
    onDropped(file.name, await file.readAsBytes());
  }
}
