import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cube_lut.dart';

/// A kind of colour blindness: which cone is missing.
///
/// **A class with constant instances, not an enum**, so a kind added later —
/// the anomalous trichromacies at a given severity, achromatopsia — does not
/// break an exhaustive `switch` somebody wrote against these three.
final class ColorVisionDeficiency {
  const ColorVisionDeficiency._(this.name, this._simulation, this._shift);

  /// The long-wavelength cones are missing: red reads dark and close to green.
  static const ColorVisionDeficiency protan = ColorVisionDeficiency._(
    'protan',
    <double>[
      0.152286, 1.052583, -0.204868, //
      0.114503, 0.786281, 0.099216, //
      -0.003882, -0.048116, 1.051998,
    ],
    _redGreenShift,
  );

  /// The middle-wavelength cones are missing — the commonest, about one man
  /// in sixteen: red and green are one colour.
  static const ColorVisionDeficiency deutan = ColorVisionDeficiency._(
    'deutan',
    <double>[
      0.367322, 0.860646, -0.227968, //
      0.280085, 0.672501, 0.047413, //
      -0.011820, 0.042940, 0.968881,
    ],
    _redGreenShift,
  );

  /// The short-wavelength cones are missing: blue and green run together,
  /// and yellow and violet.
  static const ColorVisionDeficiency tritan = ColorVisionDeficiency._(
    'tritan',
    <double>[
      1.255528, -0.076749, -0.178779, //
      -0.078411, 0.930809, 0.147602, //
      0.004733, 0.691367, 0.303900,
    ],
    <double>[
      1.0, 0.0, 0.7, //
      0.0, 1.0, 0.7, //
      0.0, 0.0, 0.0,
    ],
  );

  /// The value called [name], or null for a name this version does not
  /// know, which is what a file written by a later version can carry.
  static ColorVisionDeficiency? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The three, in the order a settings menu lists them.
  static const List<ColorVisionDeficiency> values = <ColorVisionDeficiency>[
    protan,
    deutan,
    tritan,
  ];

  /// Where the colour lost between red and green is put back: on green and
  /// blue, which a red-green deficiency still tells apart.
  static const List<double> _redGreenShift = <double>[
    0.0, 0.0, 0.0, //
    0.7, 1.0, 0.0, //
    0.7, 0.0, 1.0,
  ];

  /// The deficiency's short name, `protan`, `deutan` or `tritan`; what
  /// [toString] returns.
  final String name;

  /// How this deficiency sees, in linear RGB at full severity: Machado,
  /// Oliveira and Fernandes, "A Physiologically-based Model for Simulation
  /// of Color Vision Deficiency" (2009).
  final List<double> _simulation;

  /// Where a correction moves what is lost — Fidaner, Lin and Ozguven,
  /// "Analysis of Color Blindness" (2005).
  final List<double> _shift;

  @override
  String toString() => name;
}

/// A colour transform for colour vision: how the picture looks to someone
/// with a [deficiency], or the picture moved so that they tell apart what
/// it would otherwise run together.
///
/// **A table, not a pass.** Both are a matrix in linear light, applied to
/// the picture as the display gets it — after the tone map, which is where
/// `LookSettings.lut` is read. So [toStrip] bakes the matrix into the colour
/// table every backend already samples, with a software mirror and goldens
/// of its own, and a game with a grade of its own bakes the two into one
/// table, the grade first.
///
/// [simulate] is for a developer looking at their own game; [correct] is
/// for a player.
final class ColorVision {
  /// The picture as someone with [deficiency] sees it. [severity] blends
  /// from normal vision at nought to the missing cone at one, straight
  /// between the two matrices — the paper tabulates the steps between, and a
  /// straight line through them is within a few percent.
  const ColorVision.simulate(this.deficiency, {this.severity = 1.0})
    : corrects = false,
      assert(severity >= 0.0 && severity <= 1.0, 'severity is nought to one');

  /// The picture with what [deficiency] cannot see moved to where it can:
  /// the difference between the picture and its simulation, shifted onto
  /// the channels still told apart and added back, by [severity].
  const ColorVision.correct(this.deficiency, {this.severity = 1.0})
    : corrects = true,
      assert(severity >= 0.0 && severity <= 1.0, 'severity is nought to one');

  /// The missing cone the transform shows or corrects for.
  final ColorVisionDeficiency deficiency;

  /// A 0..1 fraction.
  final double severity;

  /// Whether this corrects for the deficiency rather than showing it.
  final bool corrects;

  /// The transform as a 3×3 matrix on linear RGB, row by row.
  List<double> get matrix {
    final m = deficiency._simulation;
    const identity = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
    if (!corrects) {
      return <double>[
        for (var i = 0; i < 9; i++)
          identity[i] + (m[i] - identity[i]) * severity,
      ];
    }
    // I + severity · S · (I − M): the error the deficiency makes, shifted.
    final s = deficiency._shift;
    double shifted(int row, int column) =>
        s[row * 3] * (identity[column] - m[column]) +
        s[row * 3 + 1] * (identity[3 + column] - m[3 + column]) +
        s[row * 3 + 2] * (identity[6 + column] - m[6 + column]);
    return <double>[
      for (var row = 0; row < 3; row++)
        for (var column = 0; column < 3; column++)
          identity[row * 3 + column] + severity * shifted(row, column),
    ];
  }

  /// [matrix] applied to a linear colour, clamped to what a display shows.
  RgbTriple applyLinear(double r, double g, double b) {
    final m = matrix;
    double row(int i) =>
        (m[i * 3] * r + m[i * 3 + 1] * g + m[i * 3 + 2] * b).clamp(0.0, 1.0);
    return RgbTriple(r: row(0), g: row(1), b: row(2));
  }

  /// The same for a colour as the display is sent it, sRGB encoded, which is
  /// what the colour table is indexed with and answers in.
  RgbTriple applyEncoded(double r, double g, double b) {
    final RgbTriple(r: lr, g: lg, b: lb) = applyLinear(
      _linear(r),
      _linear(g),
      _linear(b),
    );
    return RgbTriple(r: _encoded(lr), g: _encoded(lg), b: _encoded(lb));
  }

  /// This transform as the strip `LookSettings.lut` grades through — the
  /// layout `buildIdentityLut` writes, [size] slices of [size]×[size] — with
  /// [grade], a game's own table, applied first when there is one.
  Uint8List toStrip({int size = 33, CubeLut? grade}) {
    if (size < 2) {
      throw ArgumentError.value(size, 'size', 'a table needs two ends');
    }
    final width = size * size;
    final pixels = Uint8List(width * size * 4);
    final last = size - 1;
    int byte(double v) => (v.clamp(0.0, 1.0) * 255.0).round();
    for (var blue = 0; blue < size; blue++) {
      for (var green = 0; green < size; green++) {
        for (var red = 0; red < size; red++) {
          final input = RgbTriple(
            r: red / last,
            g: green / last,
            b: blue / last,
          );
          final RgbTriple(:r, :g, :b) = grade == null
              ? input
              : grade.lookup(input.r, input.g, input.b);
          final RgbTriple(r: or, g: og, b: ob) = applyEncoded(r, g, b);
          final at = ((green * width) + blue * size + red) * 4;
          pixels[at] = byte(or);
          pixels[at + 1] = byte(og);
          pixels[at + 2] = byte(ob);
          pixels[at + 3] = 255;
        }
      }
    }
    return pixels;
  }

  /// [toStrip] uploaded through [device], ready for `LookSettings.lut`;
  /// null when the device refuses a texture that size.
  TextureHandle? upload(
    GraphicsDevice device, {
    int size = 33,
    CubeLut? grade,
  }) => device.createTextureFromPixels(
    width: size * size,
    height: size,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: ByteData.sublistView(toStrip(size: size, grade: grade)),
  );

  /// Of [colors] — sRGB encoded, nought to one, by name — the pairs that
  /// someone missing a cone runs together: [within] or further apart to
  /// normal eyes, and nearer than it to the deficiency's.
  ///
  /// **The lint for a cue told apart by hue alone.** Two keys, two teams,
  /// two kinds of pickup coloured to say which: a pair this answers is one a
  /// player with that deficiency cannot tell apart by colour, and the fix is
  /// a second cue — a letter, a shape, a pattern — rather than a third
  /// colour. Distances are CIE 1976 ΔE in Lab under D65 ([difference]),
  /// where about two is the least anybody notices side by side; the default
  /// of twenty is what still reads at a glance on a small mark.
  static List<ColorConfusion> confusions(
    Map<String, RgbTriple> colors, {
    double within = 20.0,
  }) {
    final names = colors.keys.toList()..sort();
    final found = <ColorConfusion>[];
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final first = colors[names[i]]!;
        final second = colors[names[j]]!;
        if (difference(first, second) < within) continue;
        for (final kind in ColorVisionDeficiency.values) {
          final sees = ColorVision.simulate(kind);
          final distance = difference(
            sees.applyEncoded(first.r, first.g, first.b),
            sees.applyEncoded(second.r, second.g, second.b),
          );
          if (distance < within) {
            found.add(
              ColorConfusion(
                a: names[i],
                b: names[j],
                by: kind,
                distance: distance,
              ),
            );
          }
        }
      }
    }
    return found;
  }

  /// How far apart two sRGB colours look: CIE 1976 ΔE in Lab, D65.
  static double difference(RgbTriple a, RgbTriple b) {
    final la = _lab(a);
    final lb = _lab(b);
    return math.sqrt(
      (la.$1 - lb.$1) * (la.$1 - lb.$1) +
          (la.$2 - lb.$2) * (la.$2 - lb.$2) +
          (la.$3 - lb.$3) * (la.$3 - lb.$3),
    );
  }

  static (double, double, double) _lab(RgbTriple srgb) {
    final r = _linear(srgb.r);
    final g = _linear(srgb.g);
    final b = _linear(srgb.b);
    final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1.0 / 3.0).toDouble() : 7.787 * t + 16 / 116;
    return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)));
  }

  static double _linear(double c) =>
      c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _encoded(double c) => c < 0.0031308
      ? c * 12.92
      : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
}

/// Two named colours that someone missing a cone runs together: one pair
/// [ColorVision.confusions] answers.
final class ColorConfusion {
  /// The colours named [a] and [b], [distance] apart to eyes with the
  /// deficiency [by].
  const ColorConfusion({
    required this.a,
    required this.b,
    required this.by,
    required this.distance,
  });

  /// The name of the first colour, the earlier of the two in sorted order.
  final String a;

  /// The name of the second colour.
  final String b;

  /// The deficiency that runs them together.
  final ColorVisionDeficiency by;

  /// How far apart they look to eyes with [by]: CIE 1976 ΔE in Lab under
  /// D65, in no unit, where about two is the least anybody notices.
  final double distance;

  @override
  bool operator ==(Object other) =>
      other is ColorConfusion &&
      other.a == a &&
      other.b == b &&
      other.by == by &&
      other.distance == distance;

  @override
  int get hashCode => Object.hash(a, b, by, distance);

  @override
  String toString() => 'ColorConfusion($a, $b, ${by.name}, $distance)';
}
