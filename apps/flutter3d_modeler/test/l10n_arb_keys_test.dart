/// `ui-22`'s own acceptance: "множества ключей ru/en равны" — a key present
/// in one template and missing from the other is a bug the generator itself
/// will not catch (a missing English key just falls back to the template's
/// own Russian string at runtime, silently).
///
///     dart test test/l10n_arb_keys_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The message keys of an ARB file — everything but `@@locale` and the
/// `@name` metadata entries ICU placeholders/descriptions live under, since
/// those describe a message rather than being one.
Set<String> _messageKeys(File file) {
  final Map<String, dynamic> arb =
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return arb.keys
      .where((String key) => key != '@@locale' && !key.startsWith('@'))
      .toSet();
}

void main() {
  test('app_ru.arb and app_en.arb name exactly the same keys', () {
    final ru = _messageKeys(File('lib/l10n/app_ru.arb'));
    final en = _messageKeys(File('lib/l10n/app_en.arb'));

    expect(
      en.difference(ru),
      isEmpty,
      reason: 'app_en.arb has keys app_ru.arb does not',
    );
    expect(
      ru.difference(en),
      isEmpty,
      reason: 'app_ru.arb has keys app_en.arb does not',
    );
  });

  test('neither template is empty', () {
    final ru = _messageKeys(File('lib/l10n/app_ru.arb'));
    expect(ru, isNotEmpty);
  });
}
