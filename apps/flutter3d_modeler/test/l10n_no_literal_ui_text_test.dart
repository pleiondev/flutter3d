/// `ux-22`'s own guard: a file that has been through the translation pass
/// may not grow a new English literal where a widget will show it.
///
/// **A list of files rather than the whole of `lib/`, and it grows.** The
/// pass is not finished — the rows below say exactly where it has reached —
/// and a check that failed on every file the pass has not touched yet would
/// be a check somebody turns off. What it does hold is the thing worth
/// holding: a screen already translated cannot quietly go back, because the
/// next literal added to one of these files turns this red.
///
/// **What the allow-list is for.** Some strings are the same in every
/// language (an axis, a file extension), and some are not language at all
/// (a key an agent passes, a fallback a lookup falls to). Those are named
/// here, one by one, so that adding to them is a decision somebody makes
/// rather than a hole that opens by itself.
///
///     dart test test/l10n_no_literal_ui_text_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

/// The files whose words have been moved into `app_en.arb`/`app_ru.arb`.
///
/// Add a file here the moment its last literal goes, and this stops it
/// coming back.
const List<String> translated = <String>[
  'lib/src/ui/top_bar_actions.dart',
  'lib/src/ui/shell.dart',
  'lib/src/ui/shell_tablet.dart',
  'lib/src/ui/shell_phone.dart',
  'lib/src/ui/command_palette.dart',
  'lib/src/ui/settings_screen.dart',
  'lib/src/ui/autorig_dialog.dart',
  'lib/src/ui/sculpt_panel.dart',
  'lib/src/ui/paint_panel.dart',
  'lib/src/ui/bake_panel.dart',
  'lib/src/ui/simulation_panel.dart',
  'lib/src/ui/render_panel.dart',
  'lib/src/ui/weight_paint_panel.dart',
  'lib/src/ui/morphs_panel.dart',
  'lib/src/ui/retarget_panel.dart',
  'lib/src/ui/uv_unwrap_panel.dart',
  'lib/src/ui/transport_bar.dart',
  'lib/src/ui/properties/properties_panel.dart',
  'lib/src/ui/import_screen.dart',
  'lib/src/ui/export_screen.dart',
];

/// Strings a translated file may still name, and why each one is there.
const Map<String, String> allowed = <String, String>{
  'Box':
      'the English fallback `primitiveLabel` falls to, and the word an '
      'agent passes as `kind`',
  'Plane': 'the English fallback and the agent-facing kind, as Box',
  'Sphere': 'the English fallback and the agent-facing kind, as Box',
  'Cylinder': 'the English fallback and the agent-facing kind, as Box',
  'Torus': 'the English fallback and the agent-facing kind, as Box',
  'X': 'an axis is the same letter in both languages',
  'Y': 'an axis is the same letter in both languages',
  'Z': 'an axis is the same letter in both languages',
};

/// Where a widget puts something a person reads.
///
/// **Matched over the whole file rather than line by line, and adjacent
/// literals joined.** Both of those were holes: a `Text(` whose string starts
/// on the next line is invisible to a per-line scan, and a sentence broken
/// across two quoted pieces — which is how every paragraph in this
/// application is written, because the formatter wraps at eighty — showed up
/// as the first piece alone or not at all. The settings screen's own helps
/// and subtitles were exactly that shape, and this check read none of them
/// until it stopped reading lines.
final RegExp _sites = RegExp(
  r"(?:Text\(\s*|SectionLabel\(\s*|message:\s*|label:\s*|tooltip:\s*"
  r"|title:\s*|labelText:\s*|hintText:\s*|helperText:\s*|semanticLabel:\s*)"
  r"(?:const\s+)?((?:'(?:\\.|[^'\\])*'\s*)+)",
  multiLine: true,
);

/// [said] with every `${…}` and `$name` taken out, so what is left is the
/// words the file itself is putting on the screen.
String _outsideInterpolations(String said) => said
    .replaceAll(RegExp(r'\$\{[^}]*\}'), ' ')
    .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), ' ');

/// A run of adjacent quoted pieces, as the one string Dart joins them into.
String _joined(String pieces) => RegExp(
  r"'((?:\\.|[^'\\])*)'",
).allMatches(pieces).map((RegExpMatch m) => m.group(1)!).join();

/// An id, a key or a field name — `materialSlot`, `mesh.extrude` — which is
/// vocabulary rather than language.
final RegExp _identifier = RegExp(r'^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$');

void main() {
  test('a translated file names no literal a widget would show', () {
    final offenders = <String>[];
    for (final String path in translated) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is not there');
      final String source = file.readAsStringSync();
      for (final RegExpMatch m in _sites.allMatches(source)) {
        final String said = _joined(m.group(1)!);
        if (said.length < 2) continue;
        if (!RegExp('[A-Za-z]{2}').hasMatch(said)) continue;
        if (_identifier.hasMatch(said)) continue;
        // **A string with no word of its own outside an interpolation is
        // whatever it interpolates** — a count, a file name, a label and a
        // shortcut already translated where they were built. What is left
        // after the interpolations come out is punctuation and spacing,
        // which is not language and has nowhere to go in an ARB file.
        if (!RegExp('[A-Za-z]{2}').hasMatch(_outsideInterpolations(said))) {
          continue;
        }
        if (allowed.containsKey(said)) continue;
        final int line = '\n'.allMatches(source.substring(0, m.start)).length;
        offenders.add('$path:${line + 1}: $said');
      }
    }

    // Mutation: put one of these strings back as a literal. The English
    // build looks identical and the Russian one shows an English word in
    // the middle of a Russian bar, which is exactly the state `ui-22` left
    // and `ux-22` is clearing.
    expect(
      offenders,
      isEmpty,
      reason:
          'route these through AppLocalizations, or name them in `allowed` '
          'with the reason they are not language:\n${offenders.join('\n')}',
    );
  });

  test('every allowed string carries a reason', () {
    for (final MapEntry<String, String> each in allowed.entries) {
      expect(
        each.value.length,
        greaterThan(12),
        reason: '${each.key} is allowed without saying why',
      );
    }
  });
}
