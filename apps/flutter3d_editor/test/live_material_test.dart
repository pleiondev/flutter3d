/// `HR4`: what the material panel drags reaches a running game at most
/// thirty times a second, merged, and never without its last value.
///
///     flutter test test/live_material_test.dart
library;

import 'package:flutter3d_editor/src/play/live_material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interval = Duration(milliseconds: 33);

  /// What reached the game, in order.
  ({ThrottledMaterials sender, List<(String, Map<String, Object?>)> sent})
  sender() {
    final sent = <(String, Map<String, Object?>)>[];
    return (
      sender: ThrottledMaterials(
        send: (String material, Map<String, Object?> fields) async =>
            sent.add((material, Map<String, Object?>.of(fields))),
      ),
      sent: sent,
    );
  }

  testWidgets('the first value goes at once', (WidgetTester tester) async {
    final it = sender();
    it.sender.push('stone', <String, Object?>{'roughness': 0.1});
    expect(it.sent, hasLength(1));
    it.sender.dispose();
  });

  testWidgets('a drag inside one interval sends its last value once', (
    WidgetTester tester,
  ) async {
    final it = sender();
    it.sender.push('stone', <String, Object?>{'roughness': 0.1});
    for (final at in <double>[0.2, 0.3, 0.4]) {
      it.sender.push('stone', <String, Object?>{'roughness': at});
    }
    expect(it.sent, hasLength(1), reason: 'the rest wait for the interval');

    await tester.pump(interval);

    expect(it.sent, hasLength(2));
    expect(it.sent.last.$1, 'stone');
    expect(it.sent.last.$2, <String, Object?>{'roughness': 0.4});

    await tester.pump(interval * 3);
    expect(it.sent, hasLength(2), reason: 'nothing new, nothing sent');
    it.sender.dispose();
  });

  testWidgets('fields and materials are merged, not dropped', (
    WidgetTester tester,
  ) async {
    final it = sender();
    it.sender.push('stone', <String, Object?>{'roughness': 0.1});
    it.sender
      ..push('stone', <String, Object?>{'metallic': 0.5})
      ..push('moss', <String, Object?>{'roughness': 0.9});

    await tester.pump(interval);

    final merged = it.sent.skip(1).toList();
    expect(merged.map((it) => it.$1), <String>['stone', 'moss']);
    expect(merged.first.$2, <String, Object?>{'metallic': 0.5});
    expect(merged.last.$2, <String, Object?>{'roughness': 0.9});
    it.sender.dispose();
  });

  testWidgets('at most one send per material per interval', (
    WidgetTester tester,
  ) async {
    final it = sender();
    // Two seconds of a sixty-hertz drag.
    for (var frame = 0; frame < 120; frame++) {
      it.sender.push('stone', <String, Object?>{'roughness': frame / 120});
      await tester.pump(const Duration(microseconds: 16667));
    }
    await tester.pump(interval);

    expect(it.sent.length, lessThanOrEqualTo(2 * 1000 ~/ 33 + 2));
    expect(it.sent.length, greaterThan(40));
    expect(it.sent.last.$2['roughness'], 119 / 120);
    it.sender.dispose();
  });
}
