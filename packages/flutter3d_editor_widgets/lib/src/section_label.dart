/// A heading in a properties panel: one line of upper-case, letter-spaced
/// text naming a section, not its content.
///
/// **One widget for both editors, not one written for each.** The modeller
/// and the level editor drew their own private version of the same four
/// lines before `ui-27` moved this here — the modeller's own default look
/// is what renders with no [style]/[padding] given, and the two overrides
/// let a caller reproduce the level editor's own denser heading (its
/// inspector panel's title, and its material panel's own row heading, ten
/// and eleven points against the modeller's own eleven) without keeping a
/// second copy of this widget around to get there.
library;

import 'package:flutter/material.dart';

/// One line of upper-case, letter-spaced text — a section's name, not its
/// content.
final class SectionLabel extends StatelessWidget {
  const SectionLabel(this.said, {super.key, this.style, this.padding});

  /// What the section is called. Always drawn upper-case regardless of the
  /// case it arrives in, so a caller never has to remember to shout.
  final String said;

  /// Overrides the modeller's own default text style. Null draws 11/400,
  /// upper case, in `colorScheme.outline` with `0.08em` of letter-spacing —
  /// the modeller's own look, and the design hand-over's own row for
  /// "Подписи разделов".
  final TextStyle? style;

  /// Overrides the modeller's own default padding of 14 above, 6 below.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        said.toUpperCase(),
        // A section's name is one line by design in both editors' own
        // layouts; a caller with a name too long to fit its column gets a
        // truncated line rather than a second row eating into the panel.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            style ??
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              // The design hand-over states this as `letter-spacing: 0.08em`
              // — CSS's own relative unit, a fraction of the font size —
              // where Flutter's `letterSpacing` wants logical pixels; 0.08 of
              // this style's own 11 is 0.88.
              letterSpacing: 0.88,
              color: theme.colorScheme.outline,
            ),
      ),
    );
  }
}
