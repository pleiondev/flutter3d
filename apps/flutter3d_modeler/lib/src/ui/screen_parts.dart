/// The four widgets every one of `ui-05`'s three shells draws from.
///
/// **A named type rather than four positional widgets threaded through by
/// hand.** `_screen`'s own `ModelerReady` branch builds `actions`, `status`,
/// `properties` and `viewport` once — the same objects whichever shell
/// draws them, which is `ui-05`'s own acceptance that the same tools answer
/// to the same keys in all three — and used to hand the four straight to a
/// `LayoutBuilder` that picked among them inline. [ShellForWidth]
/// (`shell_for_width.dart`) is that picker now, and this is what it picks
/// between.
library;

import 'package:flutter/material.dart';

/// One screen's worth of content, built once and not yet arranged into a
/// shell.
class ScreenParts {
  const ScreenParts({
    required this.actions,
    required this.status,
    required this.properties,
    required this.viewport,
  });

  /// What sits at the right of the top bar: opening, saving, exporting.
  final List<Widget> actions;

  /// The one-line status: what happened last, readiness, the triangle count.
  final Widget status;

  /// The properties panel for whatever mode and selection are current.
  final Widget properties;

  /// The 3D viewport — gizmo, orientation dial and measurement overlay
  /// included.
  final Widget viewport;
}
