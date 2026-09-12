/// A heading in a properties panel.
///
/// **Meant for both editors, built for one so far.** `ui-08`'s own row names
/// this file; the modeller and the level editor each drew their own private
/// version of the same four lines rather than share one, because sharing
/// today means one app importing the other's `lib/src/` — `ui-27` is the row
/// that moves widgets like this one into a package both can depend on
/// instead. Until then this is `apps/flutter3d_modeler`'s own copy, public
/// only so this file's own test can build one without a private import.
library;

import 'package:flutter/material.dart';

/// One line of upper-case, letter-spaced text — a section's name, not its
/// content.
final class SectionLabel extends StatelessWidget {
  const SectionLabel(this.said, {super.key});

  final String said;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      said.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
      ),
    ),
  );
}
