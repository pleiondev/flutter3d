/// Three curves for how a sound gets quieter with distance, and what each
/// one answers at the same handful of distances.
///
/// Quoted by `audio_rolloff.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AudioRolloffDemo extends ShowcaseDemo {
  @override
  Scene build(DemoContext context) {
    // The printed answer, for the second step of the guide.
    _run();
    final material = Material(
      name: 'speaker',
      baseColor: Vector4(0.4, 0.6, 0.9, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region curves
  static const curves = <String, Attenuation>{
    'inverse': InverseRolloff(),
    'linear': LinearRolloff(),
    'exponential': ExponentialRolloff(),
  };
  // #endregion curves

  static String _run() {
    // #region sample
    const distances = <double>[1.0, 5.0, 10.0, 20.0];
    final lines = <String>[
      for (final entry in curves.entries)
        '${entry.key}: ${[for (final d in distances) entry.value.gainAt(d).toStringAsFixed(2)].join(', ')}',
    ];
    // #endregion sample
    return 'gain at ${distances.join(', ')} metres\n${lines.join('\n')}';
  }

  double distance = 6.0;

  static const List<Color> _inks = <Color>[
    Color(0xFF7FB0FF),
    Color(0xFF6CE07C),
    Color(0xFFE8A33D),
  ];

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Distance',
      min: 0.0,
      max: 30.0,
      value: () => distance,
      onChanged: (double v) => distance = v,
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
  ];

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      ColoredBox(
        color: const Color(0xFF14161A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CustomPaint(
            painter: _CurvePainter(distance, _inks),
            child: const SizedBox.expand(),
          ),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the speaker marker was not drawn');
    }
    // #region compare
    const inverse = InverseRolloff();
    const linear = LinearRolloff();
    final closer = inverse.gainAt(5.0) > inverse.gainAt(10.0);
    final silentPastMaximum = linear.gainAt(linear.maximum + 1.0) <= 0.0;
    // #endregion compare
    if (!closer || !silentPastMaximum) {
      throw StateError(
        'every curve should get quieter with distance and go silent past '
        'its maximum',
      );
    }
  }
}

/// The three curves against distance, with a marker where the slider is and
/// what each curve answers there.
final class _CurvePainter extends CustomPainter {
  const _CurvePainter(this.distance, this.inks);

  final double distance;
  final List<Color> inks;

  static const double _reach = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTWH(48.0, 8.0, size.width - 64.0, size.height - 56.0);
    final Paint axis = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plot, axis);
    Offset at(double d, double gain) => Offset(
      plot.left + d / _reach * plot.width,
      plot.bottom - gain.clamp(0.0, 1.0) * plot.height,
    );
    void label(String text, Offset where, Color colour) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: colour, fontSize: 13)),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, where);
    }

    for (var m = 0; m <= 30; m += 5) {
      final Offset x = at(m.toDouble(), 0.0);
      canvas.drawLine(x, Offset(x.dx, plot.top), axis..color = const Color(0x22FFFFFF));
      label('$m m', Offset(x.dx - 10, plot.bottom + 4), const Color(0xAAFFFFFF));
    }
    for (var g = 0; g <= 4; g++) {
      label('${g * 25}%', Offset(6, plot.bottom - g / 4 * plot.height - 8), const Color(0xAAFFFFFF));
    }

    var i = 0;
    for (final MapEntry<String, Attenuation> entry in AudioRolloffDemo.curves.entries) {
      final Path path = Path();
      for (var step = 0; step <= 150; step++) {
        final double d = step / 150 * _reach;
        // A gain never runs off the top: at the source itself it is 1.
        final Offset p = at(d, entry.value.gainAt(d));
        step == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = inks[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final double here = entry.value.gainAt(distance);
      canvas.drawCircle(at(distance, here), 5.0, Paint()..color = inks[i]);
      label(
        '${entry.key}: ${(here * 100).round()}%',
        Offset(plot.right - 170, plot.top + 8 + 18.0 * i),
        inks[i],
      );
      i++;
    }
    canvas.drawLine(
      at(distance, 0.0),
      at(distance, 1.0),
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
