/// `ui-32n`'s own screen: `shortcut_help.dart`'s table, drawn, with a way out
/// to the tutorial.
///
/// **A dialog, not a route** — the same call `export_screen.dart` already
/// made, and for the same reason: this is a single-screen application, and a
/// modal keeps whatever was on screen behind it rather than pushing a route
/// nothing else here uses.
///
/// **The tutorial link points at the site's own root, not a page that does
/// not exist yet.** `rel-09` (the tutorial itself) and `rel-08` (the site's
/// own Modeler section) are both still unbuilt — linking to either by a guessed
/// path would be a link that 404s the day this ships. `https://flutter3d.pleion.dev`
/// is the one address already true today; when `rel-09` lands, this is the
/// one call site to point at the real page instead.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import 'shortcut_help.dart';

/// The site's own root — see this file's own doc comment for why not a
/// deeper, not-yet-real path.
final Uri tutorialUrl = Uri.parse('https://flutter3d.pleion.dev');

/// Opens `ui-32n`'s own shortcut-help dialog.
Future<void> showShortcutHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (BuildContext context) => const _ShortcutHelpScreen(),
);

class _ShortcutHelpScreen extends StatelessWidget {
  const _ShortcutHelpScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final entries = shortcutTable();
    return AlertDialog(
      title: Text(l10n.keyboardShortcuts),
      content: SizedBox(
        width: 360,
        height: 420,
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final ShortcutEntry entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        entry.shortcut.keyLabel.toUpperCase(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.label,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => launchUrl(tutorialUrl),
          child: Text(l10n.tutorial),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
