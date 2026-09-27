/// Local exposure: each part of the frame given the exposure that shows it
/// best, so a dark room and its bright window can both be seen.
///
/// Quoted by `local_exposure.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/pages/post/post_stage.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class LocalExposureDemo extends ShowcaseDemo {
  bool local = true;
  double strength = 1.0;
  double shadowStops = 2.0;
  double highlightStops = 2.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.7
      ..pitch = 0.07
      ..yaw = 0.18;
    context.orbit.target.setValues(-0.2, 1.1, -3.0);
  }

  @override
  Scene build(DemoContext context) {
    final GraphicsDevice device = context.device;
    MeshNode slab(Vector3 size, Vector3 at, Material material) => MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: size).build()),
      material,
    )..setPositionFrom(at);

    // #region room
    final Material plaster = Material(
      name: 'plaster',
      baseColor: Vector4(0.75, 0.72, 0.68, 1.0),
      roughness: 0.9,
    );
    // A room six metres square and three high, with walls half a metre
    // thick. Every slab runs past the ones it meets, so no corner is a seam.
    const double t = 0.5;
    const double outer = 6 + 2 * t;
    const double side = 3 + t / 2;
    // The window, a metre and a half wide, from 0.9 m to 2.3 m up.
    const double half = 0.75, sill = 0.9, head = 2.3;
    const double jamb = 3 + t - half;
    final Scene scene = Scene()
      ..add(slab(Vector3(outer, t, outer), Vector3(0, -t / 2, 0), plaster))
      ..add(slab(Vector3(outer, t, outer), Vector3(0, 3 + t / 2, 0), plaster))
      ..add(slab(Vector3(t, 3 + 2 * t, outer), Vector3(-side, 1.5, 0), plaster))
      ..add(slab(Vector3(t, 3 + 2 * t, outer), Vector3(side, 1.5, 0), plaster))
      // The back wall, in four pieces around the window.
      ..add(
        slab(
          Vector3(jamb, 3 + 2 * t, t),
          Vector3(-(half + jamb / 2), 1.5, -side),
          plaster,
        ),
      )
      ..add(
        slab(
          Vector3(jamb, 3 + 2 * t, t),
          Vector3(half + jamb / 2, 1.5, -side),
          plaster,
        ),
      )
      ..add(
        slab(
          Vector3(2 * half, sill + t, t),
          Vector3(0, (sill - t) / 2, -side),
          plaster,
        ),
      )
      ..add(
        slab(
          Vector3(2 * half, 3 + t - head, t),
          Vector3(0, (head + 3 + t) / 2, -side),
          plaster,
        ),
      )
      // A crate in the dark half of the room.
      ..add(
        slab(
          Vector3(0.8, 0.8, 0.8),
          Vector3(-1.8, 0.4, -1.2),
          Material(name: 'crate', baseColor: Vector4(0.6, 0.25, 0.15, 1.0)),
        ),
      );
    // #endregion room

    // #region outside
    final MeshNode sky = slab(
      Vector3(8.0, 8.0, 0.1),
      Vector3(0.0, 1.5, -5.0),
      Material(
        name: 'sky',
        baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
        emissive: Vector3(5.0, 6.0, 8.0),
      ),
    )..shadowCasting = ShadowCastingMode.off;
    // No lamp and no sun: the room has only a weak ambient light, and the
    // engine is told not to add a light of its own to a scene that has none.
    scene
      ..ambientIntensity = 0.12
      ..defaultLightWhenUnlit = false;
    // #endregion outside
    return scene..add(sky);
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    exposure: 1.0,
    bloom: const BloomSettings(enabled: false),
    // #region settings
    localExposure: LocalExposureSettings(
      enabled: local,
      strength: strength,
      shadowStops: shadowStops,
      highlightStops: highlightStops,
    ),
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Local exposure',
      value: () => local,
      onChanged: (bool v) => local = v,
    ),
    SliderControl(
      'Strength',
      min: 0,
      max: 1,
      value: () => strength,
      onChanged: (double v) => strength = v,
    ),
    SliderControl(
      'Shadow stops',
      min: 0,
      max: 4,
      value: () => shadowStops,
      onChanged: (double v) => shadowStops = v,
      format: (double v) => '+${v.toStringAsFixed(1)}',
    ),
    SliderControl(
      'Highlight stops',
      min: 0,
      max: 4,
      value: () => highlightStops,
      onChanged: (double v) => highlightStops = v,
      format: (double v) => '-${v.toStringAsFixed(1)}',
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region ran
    if (local && strength > 0) {
      expectPassOrDecline(frame, 'local exposure');
    } else if (passRan(frame, 'local exposure')) {
      throw StateError('local exposure is off and its pass ran');
    }
    // #endregion ran
  }
}
