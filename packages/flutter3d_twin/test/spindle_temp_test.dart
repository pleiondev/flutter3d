/// `ls-i-00`'s own acceptance, the half that is not "what if": "the
/// temperature on the panel follows the source." Checked against the real
/// production formula, not a synthetic stand-in —
/// `apps/flutter3d_template_app/test/tpl04_levels_test.dart`'s own
/// `resolveBindings` test already proves the generic machinery with a fake
/// sampler; this proves the actual signal `twin.json` ships with.
///
///     dart test test/spindle_temp_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_twin/flutter3d_twin.dart';
import 'package:test/test.dart';

void main() {
  test('spindleTempAt is deterministic — the same step always answers '
      'the same reading', () {
    expect(spindleTempAt(37), spindleTempAt(37));
  });

  test('the reading actually changes over time, not a constant', () {
    final readings = <double>{
      for (var step = 0; step < 400; step += 10) spindleTempAt(step),
    };
    expect(
      readings.length,
      greaterThan(1),
      reason: 'a twin whose panel never moves is not following anything',
    );
  });

  test('the reading stays within the sensor\'s own real range', () {
    for (var step = 0; step < 1000; step += 7) {
      final reading = spindleTempAt(step);
      expect(reading, greaterThanOrEqualTo(45.0));
      expect(reading, lessThanOrEqualTo(75.0));
    }
  });

  test('twinDataSources resolves through the exact bindings shape twin.json '
      'uses', () {
    final step = EntityDef(
      type: 'edu_step',
      name: 'reading',
      properties: <String, Object?>{
        'bindings': <Map<String, Object?>>[
          <String, Object?>{
            'source': 'spindle-temp',
            'path': 'value',
            'target': 'dashboard.temperature',
          },
        ],
      },
    );
    final sources = twinDataSources();

    final at10 = resolveBindings(step, 10, sources);
    final at60 = resolveBindings(step, 60, sources);

    expect(at10['dashboard.temperature'], spindleTempAt(10));
    expect(at60['dashboard.temperature'], spindleTempAt(60));
    expect(at10, isNot(equals(at60)));
  });
}
