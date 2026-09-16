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
import '../settings.dart' show NavigationScheme;
import 'keymap.dart';
import 'shortcut_help.dart';

/// The modeller's own tutorial — `ux-42`.
///
/// **The tutorial, not the front door.** This pointed at the site's root
/// while there was no modeller section to point at; `rel-08` built one, and a
/// person pressing "Tutorial" in a modeller and landing on a page about a
/// rendering engine has been answered with a different question.
final Uri tutorialUrl = Uri.parse('https://flutter3d.pleion.dev/learn/modeler/');

/// Opens `ui-32n`'s own shortcut-help dialog, over the live preset.
Future<void> showShortcutHelp(
  BuildContext context, {
  required Keymap keymap,
  NavigationScheme navigation = NavigationScheme.middleMouseOrbit,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) =>
      _ShortcutHelpScreen(keymap: keymap, navigation: navigation),
);

class _ShortcutHelpScreen extends StatelessWidget {
  const _ShortcutHelpScreen({required this.keymap, required this.navigation});

  final Keymap keymap;
  final NavigationScheme navigation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final entries = shortcutTable(keymap, navigation: navigation);
    return AlertDialog(
      title: Text(l10n.keyboardShortcuts),
      // **As tall as the list needs, up to what the window can give** —
      // `ux-28`, which added enough rows to push a section heading off the
      // bottom of the 420 this used to be fixed at. A scrolling list cut off
      // mid-row is how a person concludes there is nothing below it; three
      // fifths of the window leaves room for the title and the two buttons
      // and still shrinks on a laptop turned on its side.
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              // Sectioned since `ux-10`: the review found this screen
              // teaching the tools and nothing else — not the camera, not
              // saving, not selecting, which are the three things somebody in
              // their first hour actually comes here for.
              for (final ShortcutSection section in ShortcutSection.values)
                if (entries.any((ShortcutEntry it) => it.section == section))
                  ..._section(theme, section, entries),
            ],
          ),
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

  /// One section's own heading and rows.
  List<Widget> _section(
    ThemeData theme,
    ShortcutSection section,
    List<ShortcutEntry> entries,
  ) => <Widget>[
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        switch (section) {
          ShortcutSection.camera => 'CAMERA',
          ShortcutSection.application => 'APPLICATION',
          ShortcutSection.selection => 'SELECTION',
          ShortcutSection.tools => 'TOOLS · ${keymap.preset.label}',
          ShortcutSection.touch => 'TOUCH AND PEN',
        },
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.0,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    for (final ShortcutEntry entry in entries)
      if (entry.section == section)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 132,
                child: Text(
                  entry.keys,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Text(entry.label, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
  ];
}
