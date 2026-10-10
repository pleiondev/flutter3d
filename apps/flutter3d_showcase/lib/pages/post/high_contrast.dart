/// The high-contrast look: texture flattened inside each surface, the frame
/// drained toward grey, every edge drawn, and a ring in its role's colour
/// around each thing a player has to find.
///
/// Quoted by `high_contrast.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class HighContrastDemo extends ShowcaseDemo {
  bool look = true;
  bool roles = true;
  double saturation = 0.25;
  double contrast = 1.5;

  final List<(MeshNode, Vector3)> _marked = <(MeshNode, Vector3)>[];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.5
      ..yaw = 0.4;
    context.orbit.target.setValues(0.0, 0.5, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region level
    // A busy floor and some crates in colours of their own: the detail the
    // look is there to take away.
    const CheckerboardTexture tiles = CheckerboardTexture(
      size: 32,
      cell: 2,
      light: 0x9A8F7A,
      dark: 0x5E6B48,
    );
    final Scene scene = Scene()
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 12, depth: 12).build(),
          ),
          RenderMaterial(
            name: 'tiles',
            albedo: tiles.upload(context.device),
            albedoSampler: SamplerDescriptor.linearRepeat,
            roughness: 0.9,
          ),
          name: 'floor',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.4, -0.8, -0.3)),
      );
    final DeviceMesh crate = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(1.0)).build(),
    );
    final List<Vector4> paint = <Vector4>[
      Vector4(0.7, 0.35, 0.2, 1.0),
      Vector4(0.25, 0.45, 0.7, 1.0),
      Vector4(0.55, 0.6, 0.25, 1.0),
    ];
    for (var i = 0; i < 3; i++) {
      scene.add(
        MeshNode(
          crate,
          RenderMaterial(
            name: 'crate $i',
            baseColor: _fromSrgb(paint[i]),
            roughness: 0.7,
          ),
          name: 'crate $i',
        )..setPosition(-3.0 + i * 1.2, 0.5, -2.5),
      );
    }
    // #endregion level

    // #region roles
    // Three things the player has to find, each in the colour its role has:
    // a monster, a pickup and the way out. The colours are display colours,
    // as a swatch in the game's settings gives them.
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.5, segments: 24, rings: 12).build(),
    );
    final List<(String, Vector3, Vector3)> things =
        <(String, Vector3, Vector3)>[
          ('monster', Vector3(1.0, 0.2, 0.2), Vector3(1.8, 0.5, 0.5)),
          ('pickup', Vector3(1.0, 0.85, 0.1), Vector3(-1.2, 0.5, 1.6)),
          ('exit', Vector3(0.2, 0.9, 0.4), Vector3(3.2, 0.5, -2.2)),
        ];
    for (final (String role, Vector3 color, Vector3 at) in things) {
      final MeshNode node = MeshNode(
        ball,
        RenderMaterial(
          name: role,
          baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0),
        ),
        name: role,
      )..setPositionFrom(at);
      // The role colours are picked by eye, so they are sRGB.
      node.outlineColor = LinearColor.fromSrgb(color.x, color.y, color.z);
      _marked.add((node, color));
      scene.add(node);
    }
    // #endregion roles
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // A mark is per mesh; taking it off is setting it back to null.
    for (final (MeshNode node, Vector3 color) in _marked) {
      node.outlineColor = roles
          ? LinearColor.fromSrgb(color.x, color.y, color.z)
          : null;
    }
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region look
    highContrast: HighContrastSettings(
      enabled: look,
      saturation: saturation,
      contrast: contrast,
      outlineWidth: 1.0,
      roleWidth: 3.0,
      roleFill: 0.3,
    ),
    // #endregion look
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'High contrast',
      value: () => look,
      onChanged: (bool v) => look = v,
    ),
    ToggleControl(
      'Role outlines',
      value: () => roles,
      onChanged: (bool v) => roles = v,
    ),
    SliderControl(
      'Saturation',
      min: 0,
      max: 1,
      value: () => saturation,
      onChanged: (double v) => saturation = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
    SliderControl(
      'Contrast',
      min: 1,
      max: 3,
      value: () => contrast,
      onChanged: (double v) => contrast = v,
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // The look is one pass on the finished picture, and the rings are a mask
    // drawn before it from the marked nodes alone. On, with marks, both run;
    // off, neither does, which is what "an exact no-op" means here.
    bool ran(String name) => frame.passes.any((FramePass p) => p.name == name);
    final bool marked = scene.meshes.any(
      (MeshNode m) => m.outlineColor != null,
    );
    if (ran('high contrast') != look) {
      throw StateError(
        'the look pass ran: ${ran('high contrast')}, look: $look',
      );
    }
    if (ran('outline mask') != (look && marked)) {
      throw StateError(
        'the outline mask ran: ${ran('outline mask')}; '
        'look: $look, marked nodes: $marked, skipped: ${frame.skipped}',
      );
    }
    // #endregion check
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
