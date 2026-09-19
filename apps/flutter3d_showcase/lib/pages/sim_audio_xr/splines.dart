/// A smooth curve through a list of points, measured in metres rather than
/// in the unitless parameter a cubic spline is naturally described by.
///
/// Quoted by `splines.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class SplinesDemo extends ShowcaseDemo {
  double distance = 0.0;

  // #region track
  late final CatmullRom _track = CatmullRom(<Vector3>[
    Vector3(1.2, 0, 0),
    Vector3(0, 0, 1.2),
    Vector3(-1.2, 0, 0),
    Vector3(0, 0, -1.2),
  ]);
  // #endregion track

  late final MeshNode _car;
  final Vector3 _point = Vector3.zero();

  @override
  Scene build(DemoContext context) {
    final material = Material(
      name: 'car',
      baseColor: Vector4(0.9, 0.3, 0.3, 1.0),
    );
    _car = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(_car)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region sample
  @override
  void update(DemoContext context, double dt) {
    distance = _track.wrap(distance + dt * 2.0);
    _track.sampleAt(distance, _point);
    _car.setPositionFrom(_point);
  }
  // #endregion sample

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Distance along the loop (m)',
      min: 0,
      max: _track.length,
      value: () => distance,
      onChanged: (double v) => distance = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the car marker was not drawn');
    }
    // #region measure
    // A closed loop through four points three metres from the centre comes
    // back to its own start.
    final start = Vector3.zero();
    _track.sampleAt(0.0, start);
    final afterALap = Vector3.zero();
    _track.sampleAt(_track.length, afterALap);
    final gap = (start - afterALap).length;
    // #endregion measure
    if (gap > 0.01) {
      throw StateError(
        'a closed spline should return to its own start '
        'after one full length, gap was $gap',
      );
    }
  }
}
