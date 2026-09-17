/// `ui-38d`'s last acceptance clause: "no `#FF458E`/`#7EE081` literal outside
/// `theme.dart`".
///
/// **The clause was never checked, and it drifted the first time somebody
/// needed the accent.** `pro-rt-03`'s retopology overlay wanted the pink the
/// hand-off gives the active quad and wrote the hex, which is exactly the
/// shape the clause exists to stop: two places to edit when a theme moves,
/// and only one of them found. `theme_test.dart` holds what each token *is*;
/// this holds that nothing else spells it out.
///
///     flutter test test/theme_accent_literals_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

/// The two the clause names, as they appear in a `Color(0x…)` literal —
/// case-insensitively, since `0xffff458e` is the same colour and the same
/// mistake.
const List<String> _accents = <String>['FF458E', '7EE081'];

/// Where the same six digits are not a second copy of a theme colour, each
/// with what it is instead. **An exemption is a sentence, not a path**: a
/// list of bare paths is a list nobody can tell a considered case from an
/// unfixed one in.
const Map<String, String> _notAColourToken = <String, String>{
  // `0x7EE081` with no alpha byte: a mesh tint the gizmo shader multiplies,
  // not a `Color` a widget paints. Its own doc comment already says it is
  // `ModelerColors.success`'s hex and why the three axes are named hexes
  // rather than a rotated triple; it stays `const` because every gizmo part
  // that carries it is a `const` constructor.
  'lib/src/transform_gizmo.dart': 'an 0xRRGGBB tint for the gizmo shader',
  // One stop of a five-stop weight ramp, converted sRGB→linear for a vertex
  // buffer. Reading one of the five from the theme and leaving four as
  // literals would hide the ramp from the next person to read it.
  'lib/src/weight_gradient.dart': 'one stop of the weight ramp, in linear',
  // The same ramp again, as the `Color`s the legend widget paints. Same
  // reason: it is a scale, and a scale is read whole.
  'lib/src/ui/weight_legend.dart': 'the same ramp, as painted swatches',
};

void main() {
  test('nothing outside theme.dart spells out an accent hex', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (path.endsWith('lib/src/ui/theme.dart')) continue;
      if (_notAColourToken.containsKey(path)) continue;

      final List<String> lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final String line = lines[i];
        // A doc comment naming the hex is how this repository says which
        // token a widget is reading — `morphs_panel.dart`'s own
        // "`secondary` (`#FF458E`)". What the clause is about is the value.
        if (line.trimLeft().startsWith('//')) continue;
        for (final String accent in _accents) {
          if (!line.toUpperCase().contains('COLOR(0X') ||
              !line.toUpperCase().contains(accent)) {
            continue;
          }
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'an accent hex is written out instead of read from the scheme — '
          'use kModelerScheme.secondary or ModelerColors.dark.success, or '
          'add the file to _notAColourToken with why:\n'
          '${offenders.join('\n')}',
    );
  });

  test('and every exemption still names a file that exists', () {
    // An exemption outlives the line it excuses otherwise, and the next
    // copy of the hex lands in a file this test has already been told to
    // ignore.
    for (final String path in _notAColourToken.keys) {
      expect(File(path).existsSync(), isTrue, reason: '$path is gone');
      final String source = File(path).readAsStringSync().toUpperCase();
      expect(
        _accents.any(source.contains),
        isTrue,
        reason: '$path no longer names an accent hex — drop its exemption',
      );
    }
  });
}
