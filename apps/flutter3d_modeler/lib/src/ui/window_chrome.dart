/// The title bar, told what the document is called and whether it is saved —
/// `ux-30`.
///
/// **`Title` alone reaches the browser and Android, and not the window this
/// application is usually in.** Flutter's own `Title` widget sets
/// `SystemChrome.setApplicationSwitcherDescription`, which a web build turns
/// into the tab's label and a macOS build ignores entirely: the `NSWindow`
/// keeps whatever the xib gave it for the whole session. So the window a
/// person actually has three of said `flutter3d_modeler` on all three, and
/// the review found it the same way anybody would — by alt-tabbing into the
/// wrong one.
///
/// **And the dot in the close button is a real thing, not a decoration.**
/// `NSWindow.isDocumentEdited` is what macOS itself reads to draw it, to warn
/// on a Quit, and to let Time Machine and the window restoration machinery
/// know there is unsaved work. Spelling the same fact with a bullet in the
/// title text is the part every platform gets; this is the part only this one
/// can.
library;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../close_guard.dart' show windowTitleFor;

/// The channel `MainFlutterWindow.swift` answers on.
///
/// One method, `show`, with `title` and `edited` — a single call rather than
/// two, because the two facts always change together and a window that had
/// taken one and not the other would be a window disagreeing with itself for
/// however long the second message took.
const MethodChannel kWindowChannel = MethodChannel('flutter3d/window');

/// Whether this build has a native window to tell anything to.
///
/// macOS alone: it is the platform with a handler on the other end, and the
/// only one where `isDocumentEdited` means anything. Everywhere else the
/// [Title] below is the whole of it, which is what those platforms read.
bool get hasNativeWindowChrome =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Names the window after [name], marks it when [isDirty], and draws [child].
///
/// A widget rather than a call somebody has to remember: the title follows the
/// document, the document changes in a `setState`, and the one place that is
/// reliably true is a build. Sending happens on the way in and on every change
/// after it — never on a rebuild that changed neither, since this application
/// rebuilds its whole screen once a frame and a platform message per frame for
/// a title nobody renamed would be a message channel used as a spin loop.
class DocumentWindowTitle extends StatefulWidget {
  const DocumentWindowTitle({
    super.key,
    required this.name,
    required this.isDirty,
    required this.child,
    this.channel = kWindowChannel,
    this.native,
  });

  /// What the open document is called — `ModelerReady.documentName`.
  final String name;

  /// Whether it has unsaved changes.
  final bool isDirty;

  final Widget child;

  /// Overridable so a test can listen on a channel of its own.
  final MethodChannel channel;

  /// Overridable so a test can ask what a macOS build would send without
  /// being one. Null reads [hasNativeWindowChrome].
  final bool? native;

  @override
  State<DocumentWindowTitle> createState() => _DocumentWindowTitleState();
}

class _DocumentWindowTitleState extends State<DocumentWindowTitle> {
  /// What the window was last told, so an unchanged rebuild sends nothing.
  ({String title, bool edited})? _sent;

  @override
  void initState() {
    super.initState();
    _tell();
  }

  @override
  void didUpdateWidget(DocumentWindowTitle old) {
    super.didUpdateWidget(old);
    _tell();
  }

  void _tell() {
    if (!(widget.native ?? hasNativeWindowChrome)) return;
    final ({String title, bool edited}) now = (
      // The bullet is left off the native title: macOS draws unsaved work as
      // a dot in the close button, from `edited` below, and a window saying
      // it twice reads as a bug in the application rather than as emphasis.
      title: widget.name.trim().isEmpty ? 'untitled' : widget.name.trim(),
      edited: widget.isDirty,
    );
    if (now == _sent) return;
    _sent = now;
    // Nothing waits on the answer and a window that will not be renamed is
    // not a reason to fail a frame — an older build of the native side with
    // no handler for this answers `MissingPluginException`, which is exactly
    // the case this swallows.
    widget.channel
        .invokeMethod<void>('show', <String, Object?>{
          'title': now.title,
          'edited': now.edited,
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => Title(
    title: windowTitleFor(name: widget.name, isDirty: widget.isDirty),
    color: Colors.black,
    child: widget.child,
  );
}
