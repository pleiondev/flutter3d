/// What each quality setting costs and what it looks like, per device class —
/// `N2`.
///
/// **A table rather than a rule.** "Lower the resolution when the frame is
/// slow" is one lever and a guess about it. Every lever the renderer has —
/// resolution, the samples of the screen-space effects, the steps of the fog
/// and the shafts, the shadow maps, the work budget the probes share, the
/// temporal clip — costs a different amount on a phone and on a desktop and
/// takes a different amount out of the picture. Measured once per class, the
/// question "what is the best picture that fits in 16 ms" becomes a lookup,
/// and the answer is the setting with the smallest perceptual difference
/// (FLIP) against full quality among those whose time fits.
///
/// Each row is one combination of a render scale and an effect tier. Its
/// cost is its frame time relative to full quality on that class, its FLIP
/// the mean perceptual difference of the golden scenes rendered at it
/// against the same scenes at full quality. Relative rather than absolute
/// times, because the absolute time depends on the scene, which the table
/// cannot know; `AdaptiveQuality` scales the column by what it measures.
library;

import 'dart:math' as math;

import 'render_settings.dart';
import 'tables/quality_tables.dart' as tables;

/// The machines a table is measured on.
enum DeviceClass {
  /// A phone of the Cortex-A55 generation, the slowest target.
  phone,

  /// A desktop or laptop GPU (Apple silicon, recent discrete cards).
  desktop,

  /// A browser, through WebGL2 or WebGPU.
  web,
}

/// One combination of the levers: a render scale and an effect tier.
final class QualitySetting {
  const QualitySetting({required this.renderScale, required this.tier})
    : assert(renderScale > 0.0 && renderScale <= 1.0),
      assert(tier >= 0 && tier < tierCount);

  /// Full quality: what the application asked for, unchanged.
  static const QualitySetting full = QualitySetting(renderScale: 1.0, tier: 0);

  /// How many effect tiers there are, full included.
  static const int tierCount = 4;

  /// The render scales a table is measured at.
  static const List<double> scales = <double>[1.0, 0.85, 0.7, 0.6, 0.5];

  /// Every combination a table is measured at, full first.
  static final List<QualitySetting> grid = <QualitySetting>[
    for (final scale in scales)
      for (var tier = 0; tier < tierCount; tier++)
        QualitySetting(renderScale: scale, tier: tier),
  ];

  /// A fraction of the application's own render scale.
  final double renderScale;

  /// Nought is every effect as asked for; each tier above it takes a quarter
  /// of the samples and steps away and the temporal clip one k-DOP size
  /// down, and from tier 2 halves the shadow maps.
  final int tier;

  // Per tier: the share of samples and steps kept, the divisor of the shadow
  // maps' resolution.
  static const List<double> _kept = <double>[1.0, 0.75, 0.5, 0.25];
  static const List<int> _shadowDivisor = <int>[1, 1, 2, 4];

  /// [full] with this setting's levers pulled.
  ///
  /// **Only ever down.** A lever reduces what the application set and never
  /// switches on what it left off: an effect that is off costs nothing and
  /// has nothing to reduce. At [QualitySetting.full] this returns [full]
  /// itself, so a controller sitting at full quality renders exactly the
  /// frame it would without one.
  RenderSettings apply(RenderSettings full) {
    if (renderScale == 1.0 && tier == 0) return full;
    final kept = _kept[tier];
    final divisor = _shadowDivisor[tier];
    int fewer(int value, int floor) =>
        math.max(math.min(floor, value), (value * kept).round());

    return full.copyWith(
      renderScale: full.renderScale * renderScale,
      ambientOcclusion: full.ambientOcclusion.enabled && tier > 0
          ? full.ambientOcclusion.copyWith(
              samples: fewer(full.ambientOcclusion.samples, 2),
            )
          : null,
      reflections: full.reflections.enabled && tier > 0
          ? full.reflections.copyWith(steps: fewer(full.reflections.steps, 4))
          : null,
      contactShadows: full.contactShadows.enabled && tier > 0
          ? full.contactShadows.copyWith(
              steps: fewer(full.contactShadows.steps, 4),
            )
          : null,
      lightShafts: full.lightShafts.enabled && tier > 0
          ? full.lightShafts.copyWith(steps: fewer(full.lightShafts.steps, 4))
          : null,
      volumetricFog: full.volumetricFog.enabled && tier > 0
          ? full.volumetricFog.copyWith(
              steps: fewer(full.volumetricFog.steps, 4),
            )
          : null,
      shadows: full.shadows.enabled && divisor > 1
          ? full.shadows.copyWith(
              resolution: math.max(
                math.min(256, full.shadows.resolution),
                full.shadows.resolution ~/ divisor,
              ),
              cubeResolution: math.max(
                math.min(128, full.shadows.cubeResolution),
                full.shadows.cubeResolution ~/ divisor,
              ),
            )
          : null,
      // One k-DOP size down per tier, to the box at the bottom — `N4`.
      antiAlias:
          full.antiAlias.temporal.enabled &&
              full.antiAlias.temporal.clip != TemporalClip.aabb &&
              tier > 0
          ? full.antiAlias.copyWith(
              temporal: full.antiAlias.temporal.copyWith(
                clip:
                    TemporalClip.values[math.max(
                      0,
                      full.antiAlias.temporal.clip.index - tier,
                    )],
              ),
            )
          : null,
      // Nought is "no limit", which there is nothing to take a share of.
      frameWorkBudget: full.frameWorkBudget > 0 && tier > 0
          ? math.max(1, (full.frameWorkBudget * kept).round())
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QualitySetting &&
      other.renderScale == renderScale &&
      other.tier == tier;

  @override
  int get hashCode => Object.hash(renderScale, tier);

  @override
  String toString() => 'QualitySetting(scale $renderScale, tier $tier)';
}

/// One measured row: a setting, what it costs and what it takes away.
final class QualityRow {
  const QualityRow(this.setting, {required this.cost, required this.flip});

  final QualitySetting setting;

  /// Frame time relative to [QualitySetting.full] on the table's class.
  final double cost;

  /// Mean FLIP of the golden scenes at this setting against full quality:
  /// nought is indistinguishable, one is as different as green from blue.
  final double flip;

  @override
  String toString() => 'QualityRow($setting, cost $cost, flip $flip)';
}

/// The rows of one device class, best picture first.
final class QualityTable {
  QualityTable({
    required this.deviceClass,
    required List<QualityRow> rows,
    this.measured = false,
  }) : rows = List<QualityRow>.unmodifiable(
         <QualityRow>[...rows]..sort((QualityRow a, QualityRow b) {
           final byFlip = a.flip.compareTo(b.flip);
           if (byFlip != 0) return byFlip;
           // A lever that changes nothing visible ties with full; full stays
           // first, so a controller at the top renders the application's own
           // settings untouched.
           final aFull = a.setting == QualitySetting.full;
           final bFull = b.setting == QualitySetting.full;
           if (aFull != bFull) return aFull ? -1 : 1;
           return a.cost.compareTo(b.cost);
         }),
       ) {
    if (this.rows.isEmpty || this.rows.first.setting != QualitySetting.full) {
      throw ArgumentError(
        'a quality table needs the full setting, and nothing may look better '
        'than it',
      );
    }
  }

  /// The table measured for [deviceClass].
  factory QualityTable.of(DeviceClass deviceClass) =>
      _byClass[deviceClass] ??= QualityTable(
        deviceClass: deviceClass,
        rows: <QualityRow>[
          for (final (i, setting) in QualitySetting.grid.indexed)
            QualityRow(
              setting,
              cost: tables.qualityCost[deviceClass.index][i],
              flip: tables.qualityFlip[deviceClass.index][i],
            ),
        ],
        measured: tables.qualityMeasured[deviceClass.index],
      );

  static final Map<DeviceClass, QualityTable> _byClass =
      <DeviceClass, QualityTable>{};

  final DeviceClass deviceClass;

  /// Sorted by FLIP, then by cost: the first row that fits a budget is the
  /// best picture that fits it.
  final List<QualityRow> rows;

  /// Whether the costs were measured on a device of [deviceClass], or are
  /// the software rasteriser's stand-in until they are. See
  /// `tables/quality_tables.dart`.
  final bool measured;
}
