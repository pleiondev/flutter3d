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
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
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

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
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
