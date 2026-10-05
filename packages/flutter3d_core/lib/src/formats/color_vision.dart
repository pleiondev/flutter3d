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

  final ColorVisionDeficiency deficiency;
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
  (double, double, double) applyLinear(double r, double g, double b) {
    final m = matrix;
    double row(int i) =>
        (m[i * 3] * r + m[i * 3 + 1] * g + m[i * 3 + 2] * b).clamp(0.0, 1.0);
    return (row(0), row(1), row(2));
  }

  /// The same for a colour as the display is sent it, sRGB encoded, which is
  /// what the colour table is indexed with and answers in.
  (double, double, double) applyEncoded(double r, double g, double b) {
    final (lr, lg, lb) = applyLinear(_linear(r), _linear(g), _linear(b));
    return (_encoded(lr), _encoded(lg), _encoded(lb));
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
          final input = (red / last, green / last, blue / last);
          final (r, g, b) = grade == null
              ? input
              : grade.lookup(input.$1, input.$2, input.$3);
          final (or, og, ob) = applyEncoded(r, g, b);
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

  static double _linear(double c) =>
      c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _encoded(double c) => c < 0.0031308
      ? c * 12.92
      : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
}
