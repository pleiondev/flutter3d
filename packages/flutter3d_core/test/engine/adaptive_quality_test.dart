/// The best picture that fits the budget, from a measured table — `N2`.
///
///     dart test test/engine/adaptive_quality_test.dart
///
/// The controller is driven by a simulated device: each row really costs the
/// table's cost times a load that follows a recorded trace (a device warming
/// up, holding hot, cooling down) times a few per cent of its own that the
/// table got wrong. What the plan asks of it is that no frame it chooses is
/// late on that trace, and that it climbs back when the times fall.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A table shaped like a measured one: cost falls with the pixel count and
/// the tier, the picture gets worse with both.
QualityTable _table() => QualityTable(
  deviceClass: DeviceClass.desktop,
  rows: <QualityRow>[
    for (final s in QualitySetting.grid)
      QualityRow(
        s,
        cost: s.renderScale * s.renderScale * (1.0 - 0.15 * s.tier),
        flip: (1.0 - s.renderScale) * 0.3 + s.tier * 0.02,
      ),
  ],
);

/// Microseconds per unit of cost at frame [t]: 14 ms, warming to 30 ms over
/// 200 frames, hot for 100, cooling to 10 ms over 50; then something in the
/// background taking three per cent more every frame for 40 frames, holding,
/// and letting go.
double _load(int t) => switch (t) {
  < 100 => 14000.0,
  < 300 => 14000.0 + (t - 100) * 80.0,
  < 400 => 30000.0,
  < 450 => 30000.0 - (t - 400) * 400.0,
  < 550 => 10000.0,
  < 590 => 10000.0 * math.pow(1.03, t - 550),
  < 650 => 10000.0 * math.pow(1.03, 40),
  _ => 10000.0,
};

/// What row [i] really costs on the simulated device: the table's guess off
/// by up to three per cent, differently for every row.
double _truth(QualityTable table, int i, int t) =>
    _load(t) * table.rows[i].cost * (1.0 + 0.03 * math.sin(i * 1.7));

const AdaptiveQualitySettings _on = AdaptiveQualitySettings(enabled: true);

void main() {
  test('no chosen frame is late on a trace that warms and cools', () {
    final table = _table();
    final controller = AdaptiveQuality(table, _on);
    var late = 0;
    var lowest = 0;
    for (var t = 0; t < 800; t++) {
      final i = controller.index;
      final micros = _truth(table, i, t);
      if (t > 0 && micros > _on.budgetMicros) late++;
      lowest = math.max(lowest, i);
      controller.recordFrame(micros.round());
    }
    // Mutation: let the load follow a slow frame by the exponential average
    // instead of at once, and the warm-up makes frames late.
    expect(late, 0);
    // Hot, it had to give quality away...
    expect(lowest, greaterThan(0));
    // ...and cooled, it climbs back to full. Mutation: never climb.
    expect(controller.index, 0);
    expect(controller.row.setting, QualitySetting.full);
  });

  test('it waits before climbing, and does not flicker between two rows', () {
    final table = _table();
    final controller = AdaptiveQuality(table, _on);
    // Hot enough that full does not fit.
    for (var t = 0; t < 5; t++) {
      controller.recordFrame(_truth(table, controller.index, 350).round());
    }
    final hot = controller.index;
    expect(hot, greaterThan(0));
    // Cooler at once: nothing moves for fewer than `climbFrames` frames.
    var changes = 0;
    var last = controller.index;
    for (var t = 0; t < _on.climbFrames - 1; t++) {
      controller.recordFrame(_truth(table, controller.index, 700).round());
      if (controller.index != last) changes++;
      last = controller.index;
    }
    // Mutation: climb on the first frame that fits.
    expect(changes, 0);
    expect(controller.index, hot);
  });

  test('in motion it trades resolution first, and takes it back after', () {
    final table = _table();
    const settings = AdaptiveQualitySettings(
      enabled: true,
      motionThreshold: 0.01,
      motionScale: 0.7,
    );
    final controller = AdaptiveQuality(table, settings);
    controller.recordFrame(_truth(table, 0, 700).round());
    expect(controller.index, 0);

    controller.recordFrame(
      _truth(table, controller.index, 700).round(),
      motion: 0.05,
    );
    // The best row at 0.7 or below, which with room to spare is 0.7 itself
    // at full effects. Mutation: ignore `motion`.
    expect(controller.row.setting.renderScale, lessThanOrEqualTo(0.7));
    expect(controller.row.setting.tier, 0);

    for (var t = 0; t < settings.climbFrames; t++) {
      controller.recordFrame(_truth(table, controller.index, 700).round());
    }
    expect(controller.row.setting, QualitySetting.full);
  });

  test('off, it sits at full and passes the settings through untouched', () {
    final table = _table();
    final controller = AdaptiveQuality(table);
    for (var t = 0; t < 50; t++) {
      controller.recordFrame(1000000);
    }
    expect(controller.index, 0);
    const full = RenderSettings(
      ambientOcclusion: AmbientOcclusionSettings(enabled: true),
    );
    expect(identical(controller.apply(full), full), isTrue);
  });

  group('a setting', () {
    const full = RenderSettings(
      ambientOcclusion: AmbientOcclusionSettings(enabled: true, samples: 12),
      volumetricFog: VolumetricFogSettings(enabled: true, steps: 24),
      shadows: ShadowSettings(resolution: 2048, cubeResolution: 512),
      frameWorkBudget: 2000,
    );

    test('at full is the application\'s own settings, the same object', () {
      expect(identical(QualitySetting.full.apply(full), full), isTrue);
    });

    test('pulls its levers down and never switches anything on', () {
      const setting = QualitySetting(renderScale: 0.7, tier: 2);
      final applied = setting.apply(full);
      expect(applied.renderScale, closeTo(0.7, 1e-12));
      expect(applied.ambientOcclusion.samples, 6);
      expect(applied.volumetricFog.steps, 12);
      expect(applied.shadows.resolution, 1024);
      expect(applied.shadows.cubeResolution, 256);
      expect(applied.frameWorkBudget, 1000);
      // Off in the application's settings, and left off and untouched.
      expect(applied.reflections.enabled, isFalse);
      expect(identical(applied.reflections, full.reflections), isTrue);
      expect(applied.lightShafts.enabled, isFalse);
    });

    test('scales the application\'s own render scale, not a fixed one', () {
      const setting = QualitySetting(renderScale: 0.5, tier: 0);
      expect(
        setting.apply(full.copyWith(renderScale: 0.8)).renderScale,
        closeTo(0.4, 1e-12),
      );
    });
  });

  test('every class has a table, best picture first, full at the top', () {
    for (final deviceClass in DeviceClass.values) {
      final table = QualityTable.of(deviceClass);
      expect(table.rows, hasLength(QualitySetting.grid.length));
      expect(table.rows.first.setting, QualitySetting.full);
      expect(table.rows.first.cost, 1.0);
      expect(table.rows.first.flip, 0.0);
      for (var i = 1; i < table.rows.length; i++) {
        expect(
          table.rows[i].flip,
          greaterThanOrEqualTo(table.rows[i - 1].flip),
        );
      }
    }
  });

  group('screen motion', () {
    vm.Matrix4 viewProjection(double yaw) {
      final camera = vm.makePerspectiveMatrix(1.0, 1.5, 0.1, 100.0);
      return camera * vm.Matrix4.rotationY(yaw);
    }

    test('is nought for a still camera', () {
      expect(
        screenMotion(viewProjection(0.3), viewProjection(0.3)),
        closeTo(0.0, 1e-6),
      );
    });

    test('grows with how far the camera turned', () {
      final small = screenMotion(viewProjection(0.0), viewProjection(0.01));
      final large = screenMotion(viewProjection(0.0), viewProjection(0.05));
      expect(small, greaterThan(0.0));
      expect(large, greaterThan(small * 3.0));
    });
  });
}
