/// The three big dialogs, on a window that cannot hold them — `ux-21`.
///
/// **Lathe, Auto-rig and Material Studio are each a viewport beside a panel,
/// sized in absolute pixels: 900×720, 980×720, 720×520.** On a desktop that
/// is right — they are working surfaces, and a working surface that resized
/// itself with the window would put the profile editor at a different size
/// every session. On anything narrower than the desktop shell they do not
/// fit at all, and an `AlertDialog` whose content is wider than the screen
/// does not shrink: it paints the overflow stripes over its own right-hand
/// side, which is where all three of these keep their panel.
///
/// So below [LayoutClass.desktop] the same content opens as a
/// `Dialog.fullscreen` — the whole window, an app bar with the title and a
/// close button, and the body laid out down the screen instead of across it.
/// The body is the dialog's own to build, because a viewport and a panel
/// stack differently in each of the three; what this file owns is the frame
/// round them and the one decision about when to change it.
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'layout_class.dart';

/// Whether a dialog opened over [context] has room for its desktop layout.
///
/// Measured against the window rather than against whatever box the dialog
/// has been given, because the question is how much room the dialog *could*
/// take — a `Dialog.fullscreen` takes all of it.
bool hasRoomForDialogs(BuildContext context) =>
    LayoutClass.of(MediaQuery.sizeOf(context).width) == LayoutClass.desktop;

/// One of the three big dialogs: [wide] on a desktop, [narrow] full-screen
/// anywhere else.
///
/// [actions] are the dialog's own buttons. On the full-screen shape they
/// move into the app bar, where a thumb reaches them without the body
/// having to leave room at the bottom; [onClose] is what the app bar's own
/// leading × does, which is the same thing the wide shape's Cancel does.
class RoomyDialog extends StatelessWidget {
  const RoomyDialog({
    super.key,
    required this.title,
    required this.wide,
    required this.narrow,
    required this.onClose,
    this.actions = const <Widget>[],
    this.width,
    this.height,
  });

  final String title;

  /// The desktop body, laid out inside a [width] × [height] box.
  final Widget wide;

  /// The same content for a window that cannot hold [wide] — usually the
  /// same pieces down the screen rather than across it.
  final Widget narrow;

  final VoidCallback onClose;
  final List<Widget> actions;

  /// The desktop body's own size. Both or neither.
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (hasRoomForDialogs(context)) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(width: width, height: height, child: wide),
        actions: actions,
      );
    }
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            tooltip: l.dialogClose,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
          actions: actions,
        ),
        body: SafeArea(child: narrow),
      ),
    );
  }
}
