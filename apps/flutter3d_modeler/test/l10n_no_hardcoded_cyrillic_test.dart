/// `ui-22`'s other acceptance: "под `Locale('en')` нет кириллицы" — checked
/// here at its source rather than by rendering the whole app tree in English
/// and looking for it, which would need a widget for every screen this app
/// has and would still miss one this test does not happen to pump. A
/// hardcoded Russian string compiles into `lib/` regardless of which locale
/// ever asks for it; that is the one place this check has to look.
///
///     dart test test/l10n_no_hardcoded_cyrillic_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

final RegExp _cyrillic = RegExp('[а-яА-ЯёЁ]');

/// A `///` or `//` line — the doc comments this repository writes in Russian
/// throughout, which are not strings a widget ever shows.
final RegExp _commentLine = RegExp(r'^\s*//');

void main() {
  test('lib/ names no Cyrillic outside a comment', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // `lib/l10n/` is the one place Cyrillic belongs: the Russian template
      // and its generated getters.
      if (entity.path.startsWith('lib${Platform.pathSeparator}l10n')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (_commentLine.hasMatch(line)) continue;
        if (_cyrillic.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a string in lib/ names Cyrillic directly — route it through '
          'AppLocalizations instead:\n${offenders.join('\n')}',
    );
  });
}
