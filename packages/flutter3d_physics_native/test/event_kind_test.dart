/// A plugin's own event kinds beside the core's closed set.
///
///     dart test test/event_kind_test.dart
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

void main() {
  test('a plugin kind sits above every code the core raises', () {
    const frozen = NativeEventKind.plugin(
      NativeEventKind.firstPluginCode,
      'frost.frozen',
    );
    expect(frozen.isPlugin, isTrue);
    // Mutation: drop `burnerOut` below `firstPluginCode` by lowering the
    // constant to 9 — the core's last kind then reads as a plugin's.
    for (final core in <NativeEventKind>[
      NativeEventKind.slept,
      NativeEventKind.ignited,
      NativeEventKind.wetted,
      NativeEventKind.burnerOut,
    ]) {
      expect(core.isPlugin, isFalse, reason: core.name);
      expect(core.code, lessThan(NativeEventKind.firstPluginCode));
    }
  });

  test('a code from the core is never read as a plugin kind', () {
    // Mutation: make `of` look plugin codes up in a list of its own — an
    // unknown core code then takes a plugin's name.
    final unknown = NativeEventKind.of(NativeEventKind.firstPluginCode - 1);
    expect(unknown.isPlugin, isFalse);
    expect(unknown.name, startsWith('unknown('));
  });

  test('kinds are equal by code', () {
    // Mutation: compare by name in `==` — a plugin's kind spelled the same
    // as another's with a different code would then be the same event.
    const a = NativeEventKind.plugin(0x10001, 'a');
    const b = NativeEventKind.plugin(0x10001, 'a');
    const c = NativeEventKind.plugin(0x10002, 'a');
    expect(a, b);
    expect(a == c, isFalse);
  });
}
