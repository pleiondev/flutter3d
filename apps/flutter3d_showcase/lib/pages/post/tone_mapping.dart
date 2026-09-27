/// The curve that squeezes light of any brightness into a picture a display can
/// show, the curves the engine has, and a display transform baked by the page.
///
/// Quoted by `tone_mapping.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ToneMappingDemo extends ShowcaseDemo {
  int curve = 0;
  int display = 0;
  double exposure = 1.6;

  static const List<TonemapCurve> _curves = TonemapCurve.values;

  late final TextureHandle _table;

  @override
  void configureView(DemoContext context) =>
      PostStage.frame(context, distance: 7.0);

  @override
  Scene build(DemoContext context) {
    final PostStage stage = PostStage.build(context, sunIntensity: 6.0);

    // #region lamps
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      const SphereShape(radius: 0.28, segments: 24, rings: 12).build(),
    );
    const List<List<double>> colours = <List<double>>[
      <double>[1.0, 0.1, 0.05],
      <double>[0.1, 0.9, 0.2],
      <double>[0.1, 0.25, 1.0],
    ];
    for (var i = 0; i < colours.length; i++) {
      stage.scene.add(
        MeshNode(
          ball,
          Material(
            name: 'lamp $i',
            baseColor: Vector4(0.05, 0.05, 0.05, 1.0),
            emissive: Vector3(colours[i][0], colours[i][1], colours[i][2]),
            emissiveStrength: 6.0,
          ),
          name: 'lamp $i',
        )..setPosition((i - 1) * 1.1, 1.7, -1.4),
      );
    }
    // #endregion lamps

    // #region upload
    _table = context.device.createTextureFromPixels(
      width: _size * _size,
      height: _size,
      format: TextureFormat.r16g16b16a16Float,
      pixels: _bake(),
    )!;
    // #endregion upload

    return stage.scene;
  }

  // #region table
  /// Entries per axis of the page's own table.
  static const int _size = 17;

  /// A display transform in the strip shape the engine reads: `_size` slices
  /// of `_size` by `_size`, blue picking the slice, red across and green down.
  /// Entry `i` holds the output for the input `0.18 * 2^(-10 + 20 * i / 16)`.
  ///
  /// The curve is Reinhard on the brightest channel, with the other two
  /// scaled by the same amount so the hue holds. Nothing here walks towards
  /// white: a bright red stays red however bright it gets.
  static ByteData _bake() {
    final ByteData strip = ByteData(_size * _size * _size * 8);
    double input(int i) =>
        0.18 * math.pow(2.0, -10.0 + 20.0 * i / (_size - 1)).toDouble();
    for (var b = 0; b < _size; b++) {
      for (var g = 0; g < _size; g++) {
        for (var r = 0; r < _size; r++) {
          final List<double> colour = <double>[input(r), input(g), input(b)];
          final double peak = colour.reduce(math.max);
          final double scale = 1.0 / (1.0 + peak);
          final int at = (g * _size * _size + b * _size + r) * 8;
          for (var c = 0; c < 3; c++) {
            strip.setUint16(
              at + c * 2,
              _half(colour[c] * scale),
              Endian.little,
            );
          }
          strip.setUint16(at + 6, _half(1.0), Endian.little);
        }
      }
    }
    return strip;
  }

  /// [value], from 0 to 1, as the bits of a half float.
  static int _half(double value) {
    final int bits = (ByteData(4)..setFloat32(0, value)).getUint32(0);
    final int exponent = ((bits >> 23) & 0xff) - 127 + 15;
    if (exponent <= 0) return 0;
    return (exponent << 10) | ((bits >> 13) & 0x3ff);
  }
  // #endregion table

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region exposure
    exposure: exposure,
    // #endregion exposure
    // #region curve
    tonemapCurve: _curves[curve],
    // #endregion curve
    // #region display
    look: LookSettings(
      displayTransform: display == 1
          ? DisplayTransform(texture: _table, size: _size)
          : null,
    ),
    // #endregion display
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Curve',
      options: <String>[for (final TonemapCurve c in _curves) c.name],
      index: () => curve,
      onChanged: (int i) => curve = i,
    ),
    ChoiceControl(
      'Display transform',
      options: const <String>['none', 'page table'],
      index: () => display,
      onChanged: (int i) => display = i,
    ),
    SliderControl(
      'Exposure',
      min: 0.2,
      max: 6,
      value: () => exposure,
      onChanged: (double v) => exposure = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!passRan(frame, 'composite')) {
      throw StateError(
        'the composite pass, which applies the curve, is absent',
      );
    }
    if ((frame.exposure - exposure).abs() > 1e-6) {
      throw StateError('the frame was exposed at ${frame.exposure}');
    }
  }
}
