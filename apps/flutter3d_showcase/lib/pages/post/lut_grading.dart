/// A colour grade held in a table: every colour goes in, the colour the table
/// says comes out.
///
/// Quoted by `lut_grading.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class LutGradingDemo extends ShowcaseDemo {
  int table = 0;
  double strength = 1.0;

  late final List<TextureHandle> _tables;
  late LookSettings _look;

  static const int _size = 17;

  @override
  void configureView(DemoContext context) => PostStage.frame(context);

  @override
  Scene build(DemoContext context) {
    // #region table
    final Uint8List identity = buildIdentityLut(size: _size);
    final List<Uint8List> looks = <Uint8List>[
      // Sepia: every colour becomes a brown of the same brightness.
      _remap(identity, (double r, double g, double b) {
        final double l = 0.3 * r + 0.59 * g + 0.11 * b;
        return <double>[l * 1.15, l * 0.95, l * 0.7];
      }),
      // Red and blue swapped, which nobody would mistake for the original.
      _remap(identity, (double r, double g, double b) => <double>[b, g, r]),
      // Night: dark, with the red taken out.
      _remap(identity, (double r, double g, double b) {
        return <double>[r * 0.3, g * 0.55, b * 0.9];
      }),
    ];
    _tables = <TextureHandle>[
      for (final Uint8List pixels in looks)
        context.device.createTextureFromPixels(
          width: _size * _size,
          height: _size,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(pixels),
        )!,
    ];
    // #endregion table
    return PostStage.build(context).scene;
  }

  /// A copy of [source] with every entry passed through [change].
  static Uint8List _remap(
    Uint8List source,
    List<double> Function(double r, double g, double b) change,
  ) {
    final Uint8List out = Uint8List.fromList(source);
    for (var i = 0; i < out.length; i += 4) {
      final List<double> mapped = change(
        out[i] / 255.0,
        out[i + 1] / 255.0,
        out[i + 2] / 255.0,
      );
      for (var c = 0; c < 3; c++) {
        out[i + c] = (mapped[c].clamp(0.0, 1.0) * 255).round();
      }
    }
    return out;
  }

  @override
  RenderSettings settings(DemoContext context) {
    // #region apply
    _look = LookSettings(lut: _tables[table], lutStrength: strength);
    // #endregion apply
    return RenderSettings(look: _look);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Table',
      options: const <String>['Sepia', 'Red and blue swapped', 'Night'],
      index: () => table,
      onChanged: (int i) => table = i,
    ),
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!_look.gradesThroughLut) {
      throw StateError('the table would not be sampled this frame');
    }
    if (!passRan(frame, 'composite')) {
      throw StateError('the composite pass, which reads the table, is absent');
    }
  }
}
