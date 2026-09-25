import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
// The two bakes are plain Dart and reach a browser build, but the package's
// barrel also exports the converter, which does not; importing the two
// libraries alone is what keeps the web build of this demo compiling.
// ignore: implementation_imports
import 'package:flutter3d_build/src/impostor_bake.dart';
// ignore: implementation_imports
import 'package:flutter3d_build/src/six_way_bake.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:vector_math/vector_math.dart';

import 'golden_scene.dart';

/// The arrangements the golden scenes 0.8 added draw, and the settings they draw
/// them with.
///
/// **Each is the construction of the software test that carries the scene's
/// name**, grown to the golden's frame: the same slabs, lights and materials,
/// placed where that test places them, so a difference between this picture
/// and the test's assertion is a difference in the backend and not in the
/// scene. Where a test measured one property on a 48-pixel frame, the scene
/// sometimes shows two or three variations side by side — three roughnesses
/// rather than one — because a golden is looked at, and a row says more than
/// a single sample of it.
///
/// Every scene places its own camera through [GoldenStaged.everyFrame]
/// rather than through the orbit: the tests fix an eye and a target, and the
/// orbit frames whatever bounds it is handed, which a room seen from inside
/// or a cloud with no mesh at all does not have.
abstract final class GoldenStages {
  // ---------------------------------------------------------------- helpers

  /// Puts [camera] at [eye] looking at [target], through a lens whose depth
  /// range suits a room rather than whatever the orbit derived.
  static void _look(
    CameraNode camera,
    Vector3 eye,
    Vector3 target, {
    double fovY = math.pi / 4,
    double near = 0.1,
    double far = 200.0,
    Vector3? up,
  }) {
    camera
      ..projection = PerspectiveProjection(
        fovYRadians: fovY,
        near: near,
        far: far,
      )
      ..setPosition(eye.x, eye.y, eye.z)
      ..lookAt(target, up: up);
  }

  /// A box of [size] at [at], drawn with [material].
  static MeshNode _slab(
    GraphicsDevice device,
    Vector3 size,
    Vector3 at,
    Material material, {
    String? name,
  }) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    material,
    name: name,
  )..setPositionFrom(at);

  static MeshNode _sphere(
    GraphicsDevice device,
    Vector3 at,
    Material material, {
    double radius = 0.5,
  }) => MeshNode(
    DeviceMesh.upload(
      device,
      SphereShape(radius: radius, segments: 48, rings: 24).build(),
    ),
    material,
  )..setPositionFrom(at);

  static Material _unlit(Vector4 colour, {bool doubleSided = false}) =>
      Material(
        lighting: LightingModel.unlit,
        baseColor: colour,
        doubleSided: doubleSided,
      );

  /// A directional light of the scene's own, since the demo's sun and key
  /// light are aimed for a model on a turntable.
  static LightNode _directional(
    Vector3 forward, {
    double intensity = 3.0,
    bool castsShadow = false,
  }) =>
      LightNode(intensity: intensity, castsShadow: castsShadow)
        ..setLocalForward(forward.normalized());

  /// The temporal resolve, on, with [settings]' other choices kept.
  static RenderSettings _temporal(
    RenderSettings settings, {
    TemporalSettings temporal = const TemporalSettings(enabled: true),
  }) => settings.copyWith(
    antiAlias: settings.antiAlias.copyWith(temporal: temporal),
  );

  // ------------------------------------------------------------------ R1

  /// `velocity-shapes`: the rigged and morphing robot playing, and a rigid
  /// box sliding beside it, drawn as the velocity buffer's colours — the
  /// three ways a vertex moves between frames in one picture.
  ///
  /// The robot is the demo's own model, kept rather than replaced, and its
  /// clip is sought and its expression weighted by the frame index: the
  /// skinned stage has last frame's joints to answer to, the morph stage
  /// last frame's weights. The box is placed off the orbit's own target, to
  /// the right of the robot at the orbit's distance, so it is in the frame
  /// whatever size the file is.
  ///
  /// **Large steps, and down and to the right**, because the view shows
  /// motion in UV units through the output encoding: a hundredth of the frame
  /// a frame is a black picture, and a negative channel lights nothing. So
  /// the box steps a twentieth of the frame down-right each frame and starts
  /// over every eight (the capture, frame 89, is the first step after a
  /// restart, never the jump back), the clip jumps a fifth of a second a
  /// frame, and the expression flips between its two shapes every frame.
  static Future<GoldenStaged> velocityShapes(GoldenStage stage) async {
    final box = MeshNode(
      DeviceMesh.upload(stage.device, CuboidShape().build()),
      Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
      name: 'sliding box',
    );
    return GoldenStaged(
      nodes: <SceneNode>[box],
      keepModel: true,
      everyFrame: (frame, model) {
        // Round the clip, since a seek past its end holds the last pose and
        // the skeleton would stop moving a few seconds in.
        if (model.player case final player? when player.duration > 0.0) {
          player.seek((1.2 + 0.2 * frame) % player.duration);
        }
        final smile = (frame % 2).toDouble();
        for (final mesh in model.meshes) {
          mesh.morph?.setWeights(<double>[smile, 1.0 - smile, 0.0]);
        }
        final distance = stage.orbit.distance;
        final world = stage.camera.worldMatrix.storage;
        final right = Vector3(world[0], world[1], world[2]);
        final up = Vector3(world[4], world[5], world[6]);
        final step = (frame % 8).toDouble();
        final at =
            stage.orbit.target +
            right * (distance * (0.12 + 0.05 * step)) +
            up * (distance * (0.2 - 0.03 * step));
        final size = distance * 0.1;
        box
          ..setPositionFrom(at)
          ..setScale(size, size, size);
      },
    );
  }

  static RenderSettings velocityShapesSettings(RenderSettings settings) =>
      _temporal(settings).copyWith(showVelocity: true);

  // ------------------------------------------------------------------ R2

  /// The resolve settled on the teapot `teapot-generated-normals` draws, so
  /// the two frames differ by what the history made of the jittered edges.
  static RenderSettings taaConverge(RenderSettings settings) =>
      _temporal(settings);

  /// The frame `taa-railing` settles on before anything changes.
  static const int _railingTurn = 78;

  /// `taa-railing`: blue bars in front of a wall that turns from red to
  /// green, the railing sliding for the twelve frames after the turn, and the
  /// capture on the twelfth — `temporal_kdop_test.dart`'s railing, with the
  /// motion R2's own golden asked for.
  ///
  /// The wall is close behind the bars, so the resolve keeps its history
  /// across the two and only the clip stands between the red it remembers
  /// and the green it now sees; which clip is the difference between the
  /// variants.
  static Future<GoldenStaged> railing(GoldenStage stage) async {
    stage.sun.visible = false;
    final device = stage.device;
    final wall = _unlit(Vector4(1.0, 0.0, 0.0, 1.0));
    final bar = _unlit(Vector4(0.0, 0.0, 1.0, 1.0));
    final cube = DeviceMesh.upload(device, CuboidShape().build());
    final bars = SceneNode(name: 'railing');
    for (var i = -6; i <= 6; i++) {
      bars.add(
        MeshNode(cube, bar)
          ..setPosition(i * 0.45, 0.0, -4.0)
          ..setRotationYawPitchRoll(0.0, 0.0, 0.3)
          ..setScale(0.05, 6.0, 0.05),
      );
    }
    return GoldenStaged(
      nodes: <SceneNode>[
        MeshNode(cube, wall)
          ..setPosition(0.0, 0.0, -4.3)
          ..setScale(20.0, 20.0, 0.1),
        bars,
      ],
      everyFrame: (frame, _) {
        _look(stage.camera, Vector3.zero(), Vector3(0.0, 0.0, -1.0));
        final moving = math.max(0, frame - _railingTurn);
        if (moving > 0) wall.baseColor.setValues(0.0, 1.0, 0.0, 1.0);
        bars.setPosition(0.03 * moving, 0.0, 0.0);
      },
    );
  }

  static RenderSettings _railingSettings(
    RenderSettings settings, {
    TemporalClip clip = TemporalClip.aabb,
    double renderScale = 1.0,
  }) => _temporal(
    settings,
    temporal: TemporalSettings(enabled: true, sharpen: 0.0, clip: clip),
  ).copyWith(renderScale: renderScale);

  /// The railing under the box clip, at full size.
  static RenderSettings railingSettings(RenderSettings settings) =>
      _railingSettings(settings);

  /// The railing drawn at six tenths and resolved up to the frame — TAAU.
  static RenderSettings railingScaledSettings(RenderSettings settings) =>
      _railingSettings(settings, renderScale: 0.6);

  /// The railing under the eight-sided clip — `N4`.
  static RenderSettings railingKdop8Settings(RenderSettings settings) =>
      _railingSettings(settings, clip: TemporalClip.kdop8);

  /// The railing under the sixteen-sided clip — `N4`.
  static RenderSettings railingKdop16Settings(RenderSettings settings) =>
      _railingSettings(settings, clip: TemporalClip.kdop16);

  // ------------------------------------------------------------------ R3

  /// `ao-temporal`: `ambient-occlusion-corner`'s room and occlusion, the
  /// kernel at half its samples, turned by the blue noise each frame and
  /// accumulated in its own history under the resolve.
  static RenderSettings aoTemporal(RenderSettings settings) =>
      _temporal(settings);

  // ------------------------------------------------------------------ L1

  /// A row of five spheres, roughness 0.1 to 0.9, of [colour] and
  /// [metallic], lit by a light from the upper right of the camera.
  static List<SceneNode> _sphereRow(
    GraphicsDevice device,
    Vector4 colour, {
    double metallic = 1.0,
    List<double> roughness = const <double>[0.1, 0.3, 0.5, 0.7, 0.9],
    LightingModel lighting = LightingModel.pbr,
  }) => <SceneNode>[
    for (var i = 0; i < roughness.length; i++)
      _sphere(
        device,
        Vector3((i - (roughness.length - 1) / 2) * 1.15, 0.0, 0.0),
        Material(
          lighting: lighting,
          baseColor: colour.clone(),
          metallic: metallic,
          roughness: roughness[i],
        ),
      ),
  ];

  /// `rough-metals`: gold spheres from polished to rough, which is where
  /// single scattering loses the most light and the compensation puts it
  /// back — `energy_compensation_test.dart`'s sphere, five times.
  static Future<GoldenStaged> roughMetals(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.3;
    return GoldenStaged(
      nodes: <SceneNode>[
        ..._sphereRow(stage.device, Vector4(1.0, 0.78, 0.34, 1.0)),
        _directional(Vector3(-0.4, -0.5, -1.0)),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.6, 6.6), Vector3(0.0, 0.0, 0.0)),
    );
  }

  static RenderSettings roughMetalsSettings(RenderSettings settings) =>
      settings.copyWith(energyCompensation: true);

  // ------------------------------------------------------------------ L8

  /// `rough-dielectrics`: grey clay from half rough to fully rough, lit from
  /// the eye, with the energy-preserving diffuse — `eon_diffuse_test.dart`'s
  /// sphere, the last one drawn by the layered model.
  static Future<GoldenStaged> roughDielectrics(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.05;
    final device = stage.device;
    return GoldenStaged(
      nodes: <SceneNode>[
        ..._sphereRow(
          device,
          Vector4(0.8, 0.8, 0.8, 1.0),
          metallic: 0.0,
          roughness: const <double>[0.5, 0.75, 1.0],
        ),
        _sphere(
          device,
          Vector3(2.3, 0.0, 0.0),
          Material(
            lighting: LightingModel.pbrLayered,
            baseColor: Vector4(0.8, 0.8, 0.8, 1.0),
            roughness: 1.0,
          ),
        )..setPositionFrom(Vector3(2.3, 0.0, 0.0)),
        _directional(Vector3(0.0, 0.0, -1.0), intensity: 0.9),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.6, 0.0, 5.0), Vector3(0.6, 0.0, 0.0)),
    );
  }

  static RenderSettings roughDielectricsSettings(RenderSettings settings) =>
      settings.copyWith(diffuseModel: DiffuseModel.eon);

  // ------------------------------------------------------------------ L2

  /// `tonemap-aces2`: an HDR test card, emissive patches a stop apart from
  /// four stops under mid grey to six over, in white and in the three
  /// primaries, under the ACES 2.0 table.
  ///
  /// Emissive on black rather than unlit, because an unlit colour is an
  /// sRGB value and stops at one; the card has to reach past the display's
  /// white for the table's shoulder to have anything to do.
  static Future<GoldenStaged> hdrTestCard(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.0;
    final device = stage.device;
    final patch = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(0.44, 0.44, 0.05)).build(),
    );
    final rows = <Vector3>[
      Vector3(1.0, 1.0, 1.0),
      Vector3(1.0, 0.0, 0.0),
      Vector3(0.0, 1.0, 0.0),
      Vector3(0.0, 0.0, 1.0),
    ];
    const stops = 11;
    return GoldenStaged(
      nodes: <SceneNode>[
        for (var row = 0; row < rows.length; row++)
          for (var stop = 0; stop < stops; stop++)
            MeshNode(
              patch,
              Material(
                baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
                roughness: 1.0,
                emissive: rows[row] * (0.18 * math.pow(2.0, stop - 4)),
              ),
            )..setPosition(
              (stop - (stops - 1) / 2) * 0.5,
              (1.5 - row) * 0.5,
              0.0,
            ),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.0, 6.0), Vector3.zero()),
    );
  }

  static RenderSettings tonemapAces2(RenderSettings settings) =>
      settings.copyWith(tonemapCurve: TonemapCurve.aces2, exposure: 1.0);

  // ------------------------------------------------------------------ L3

  /// `irradiance-room`: a white floor with a red wall standing along its
  /// left side, lit by nothing but an irradiance field whose probes by the
  /// wall hold its red — the bleed across the floor's width that a field
  /// read once per object could not show. `irradiance_per_pixel_test.dart`'s
  /// field, with a third column of probes between the red and the white.
  static Future<GoldenStaged> irradianceRoom(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene
      ..ambientIntensity = 1.0
      ..irradianceField = _redWallField();
    final device = stage.device;
    final white = Material(
      lighting: LightingModel.lambert,
      baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
    );
    return GoldenStaged(
      nodes: <SceneNode>[
        _slab(device, Vector3(4.0, 0.1, 4.0), Vector3(0.0, -0.05, 0.0), white),
        _slab(
          device,
          Vector3(0.1, 1.6, 4.0),
          Vector3(-2.05, 0.8, 0.0),
          Material(
            lighting: LightingModel.lambert,
            baseColor: Vector4(0.9, 0.12, 0.1, 1.0),
          ),
        ),
        _slab(device, Vector3(4.0, 1.6, 0.1), Vector3(0.0, 0.8, -2.05), white),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.6, 3.2, 4.4), Vector3(-0.2, 0.2, -0.3)),
    );
  }

  static IrradianceField _redWallField() {
    final field = IrradianceField(
      origin: Vector3(-2.0, -1.0, -2.0),
      spacing: Vector3(2.0, 2.0, 2.0),
      countX: 3,
      countY: 2,
      countZ: 3,
      tile: 4,
      depthTile: 4,
    );
    final colours = <Vector3>[
      Vector3(1.0, 0.1, 0.1),
      Vector3(1.0, 0.6, 0.55),
      Vector3(1.0, 1.0, 1.0),
    ];
    for (var z = 0; z < field.countZ; z++) {
      for (var y = 0; y < field.countY; y++) {
        for (var x = 0; x < field.countX; x++) {
          final probe = field.probeIndex(x, y, z);
          for (var ty = 0; ty < field.tile; ty++) {
            for (var tx = 0; tx < field.tile; tx++) {
              field.writeIrradianceTexel(probe, tx, ty, colours[x]);
            }
          }
          // Far walls: nothing between any probe and any point.
          for (var ty = 0; ty < field.depthTile; ty++) {
            for (var tx = 0; tx < field.depthTile; tx++) {
              field.writeDepthTexel(probe, tx, ty, 100.0, 10000.0);
            }
          }
        }
      }
    }
    field.fillGutters();
    return field;
  }

  // ------------------------------------------------------------------ L5

  /// `ssil-room`: a white floor with a red wall across the back, lit from
  /// behind the camera — `ssil_test.dart`'s room: the floor at the wall's
  /// foot reddens by what the wall bounces, and the crease darkens.
  static Future<GoldenStaged> ssilRoom(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.05;
    final device = stage.device;
    Material lambert(Vector4 colour) =>
        Material(lighting: LightingModel.lambert, baseColor: colour);
    return GoldenStaged(
      nodes: <SceneNode>[
        _slab(
          device,
          Vector3(8.0, 0.1, 8.0),
          Vector3(0.0, -0.05, 0.0),
          lambert(Vector4(1.0, 1.0, 1.0, 1.0)),
        ),
        _slab(
          device,
          Vector3(8.0, 2.0, 0.2),
          Vector3(0.0, 1.0, -1.0),
          lambert(Vector4(0.9, 0.1, 0.08, 1.0)),
        ),
        LightNode(intensity: 1.0, castsShadow: false)
          ..setRotationYawPitchRoll(0.0, -0.6, 0.0),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 2.5, 3.0), Vector3(0.0, 0.0, -0.5)),
    );
  }

  static RenderSettings ssilRoomSettings(RenderSettings settings) =>
      settings.copyWith(
        ambientOcclusion: const AmbientOcclusionSettings(
          enabled: true,
          radius: 0.6,
          strength: 1.0,
          method: AmbientOcclusionMethod.ssil,
        ),
      );

  // ------------------------------------------------------------------ L6, S4

  /// Sixty-four small lights over a white floor, each its own hue —
  /// `clustered_lights_test.dart`'s floor, where the per-draw list keeps
  /// thirty-two and leaves half the grid dark.
  static List<SceneNode> _lightGrid(
    GraphicsDevice device, {
    required double intensity,
    required double range,
  }) => <SceneNode>[
    _slab(
      device,
      Vector3(12.0, 0.1, 12.0),
      Vector3(0.0, -0.05, 0.0),
      Material(lighting: LightingModel.lambert),
    ),
    for (var i = 0; i < 8; i++)
      for (var j = 0; j < 8; j++)
        LightNode(
            type: LightType.point,
            intensity: intensity,
            range: range,
            color: _hue((i * 8 + j) / 64.0),
          )
          ..castsShadow = false
          ..setPosition(i - 3.5, 0.3, j - 3.5),
  ];

  /// A saturated colour at [t] round the hue circle.
  static Vector3 _hue(double t) {
    double channel(double offset) =>
        (0.5 + 0.5 * math.cos(2 * math.pi * (t + offset))).clamp(0.0, 1.0);
    return Vector3(channel(0.0), channel(2 / 3), channel(1 / 3));
  }

  /// `many-lights`: the grid with the cells on, every spot lit — the
  /// test's reach of 0.8 m, so each light is its own spot on the floor.
  static Future<GoldenStaged> manyLights(GoldenStage stage) =>
      _lightFloor(stage, intensity: 1.5, range: 0.8);

  /// The fog test's lights, which reach a metre and a half, at half its
  /// intensity: at the test's, the floor under them is white at the demo's
  /// exposure and the glow in the air has nothing darker to show against.
  static Future<GoldenStaged> fogTorches(GoldenStage stage) =>
      _lightFloor(stage, intensity: 1.0, range: 1.5);

  static Future<GoldenStaged> _lightFloor(
    GoldenStage stage, {
    required double intensity,
    required double range,
  }) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.03;
    return GoldenStaged(
      nodes: _lightGrid(stage.device, intensity: intensity, range: range),
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 9.0, 4.0), Vector3.zero()),
    );
  }

  static RenderSettings manyLightsSettings(RenderSettings settings) =>
      settings.copyWith(clusteredLights: true);

  /// `fog-torches`: the same grid in thin air that glows around each light
  /// the cells hold — `volumetric_fog_test.dart`'s torches.
  static RenderSettings fogTorchesSettings(RenderSettings settings) =>
      settings.copyWith(
        clusteredLights: true,
        volumetricFog: const VolumetricFogSettings(
          enabled: true,
          density: 0.3,
          heightFalloff: 1.0,
          steps: 16,
          distance: 20.0,
        ).copyWith(color: Vector3.all(1.0)),
      );

  // ------------------------------------------------------------------ L7

  /// `area-light-gloss`: a rectangle light over a floor of three strips,
  /// polished, satin and rough, seen past the panel's reflection in them —
  /// `ltc_test.dart`'s panel, a metre wide, facing down where the mirror
  /// direction points.
  static Future<GoldenStaged> areaLightGloss(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.03;
    final device = stage.device;
    return GoldenStaged(
      nodes: <SceneNode>[
        for (final (x, roughness) in <(double, double)>[
          (-1.25, 0.1),
          (0.0, 0.35),
          (1.25, 0.7),
        ])
          _slab(
            device,
            Vector3(1.2, 0.1, 5.0),
            Vector3(x, -0.05, 0.0),
            Material(
              baseColor: Vector4(0.25, 0.25, 0.27, 1.0),
              roughness: roughness,
            ),
          ),
        LightNode(type: LightType.area, intensity: 12.0, name: 'panel')
          ..width = 2.6
          ..height = 0.6
          ..setPosition(0.0, 1.5, -1.8)
          ..setRotationYawPitchRoll(0.0, -math.pi / 2.0, 0.0),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 1.3, 3.6), Vector3(0.0, 0.0, -0.4)),
    );
  }

  // ------------------------------------------------------------------ S1

  /// The last frame before `cascade-walk` starts walking.
  static const int _walkStart = 82;

  /// `cascade-walk`: a camera stepping along a row of blocks on a wide
  /// floor for the last eight frames before the capture, the sun's cascades
  /// kept and scrolled rather than redrawn — `cascade_walk_test.dart`'s
  /// scene and walk.
  static Future<GoldenStaged> cascadeWalk(GoldenStage stage) async {
    final device = stage.device;
    // The test's light, from (4, 5, 0.01) towards the origin.
    stage.sun.setLocalForward(Vector3(-4.0, -5.0, -0.01).normalized());
    final block = DeviceMesh.upload(device, CuboidShape().build());
    final floor =
        MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3(40, 0.1, 40)).build(),
            ),
            Material(name: 'floor', baseColor: Vector4(0.9, 0.9, 0.9, 1.0)),
            name: 'floor',
          )
          ..setPosition(0.0, -1.0, 0.0)
          ..shadowCasting = ShadowCastingMode.off;
    return GoldenStaged(
      nodes: <SceneNode>[
        floor,
        for (var i = 0; i < 6; i++)
          MeshNode(block, Material(name: 'block $i'))
            ..setPosition(-5.0 + i * 2.0, 0.0, -2.0),
        MeshNode(block, Material(name: 'corner'))
          ..setPosition(15.0, 0.0, -15.0),
        MeshNode(block, Material(name: 'far'))..setPosition(10.0, 0.0, -12.0),
      ],
      everyFrame: (frame, _) {
        final step = (frame - _walkStart).clamp(0, 7);
        final x = -4.0 + step * 0.6;
        _look(stage.camera, Vector3(x, 2.0, 4.0), Vector3(x, 0.0, -2.0));
      },
    );
  }

  // ------------------------------------------------------------------ S2, S3

  /// `evsm-soft`: a box held above a floor under a sun from nearly
  /// overhead, its shadow filtered as blurred exponential moments —
  /// `evsm_shadow_test.dart`'s floor and box, seen at an angle rather than
  /// from straight above so the frame also shows the box.
  static Future<GoldenStaged> evsmSoft(GoldenStage stage) async {
    final device = stage.device;
    stage.sun.setLocalForward(Vector3(-0.85, -1.0, -0.2).normalized());
    return GoldenStaged(
      nodes: <SceneNode>[
        _slab(
          device,
          Vector3(14.0, 0.2, 14.0),
          Vector3(0.0, -0.1, 0.0),
          Material(name: 'floor', baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
        ),
        _slab(
          device,
          Vector3(1.6, 0.2, 1.6),
          Vector3(0.0, 0.6, 0.0),
          Material(name: 'box', baseColor: Vector4(0.7, 0.7, 0.7, 1.0)),
        ),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(1.5, 6.0, 5.5), Vector3(0.0, 0.0, 0.0)),
    );
  }

  static RenderSettings evsmSoftSettings(RenderSettings settings) =>
      settings.copyWith(
        shadows: settings.shadows.copyWith(
          cascades: 1,
          viewDistance: 20.0,
          filter: ShadowFilter.evsm,
          evsmBlurRadius: 4,
        ),
      );

  /// `sun-contact-hardening`: a pole leaning from the floor up to a height
  /// of three metres and a slab held two metres up, under a sun of a
  /// visible size: the pole's shadow is sharp at its foot and spreads along
  /// its length, and the slab's is soft all round.
  static Future<GoldenStaged> sunContactHardening(GoldenStage stage) async {
    final device = stage.device;
    stage.sun.setLocalForward(Vector3(-0.6, -1.0, -0.35).normalized());
    final stone = Material(baseColor: Vector4(0.75, 0.73, 0.7, 1.0));
    return GoldenStaged(
      nodes: <SceneNode>[
        _slab(
          device,
          Vector3(12.0, 0.2, 12.0),
          Vector3(0.0, -0.1, 0.0),
          Material(baseColor: Vector4(0.82, 0.82, 0.82, 1.0), roughness: 0.9),
        ),
        _slab(device, Vector3(0.25, 3.2, 0.25), Vector3(-1.2, 1.5, 0.0), stone)
          ..setRotationYawPitchRoll(0.0, 0.0, -0.35),
        _slab(device, Vector3(1.2, 0.1, 1.2), Vector3(1.2, 2.0, -0.4), stone),
        _slab(device, Vector3(0.2, 2.0, 0.2), Vector3(1.2, 1.0, -0.4), stone),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(1.0, 4.5, 6.5), Vector3(0.0, 0.5, 0.0)),
    );
  }

  static RenderSettings sunContactHardeningSettings(RenderSettings settings) =>
      settings.copyWith(
        shadows: settings.shadows.copyWith(
          cascades: 1,
          viewDistance: 20.0,
          filter: ShadowFilter.pcss,
          directionalLightRadius: 0.04,
        ),
      );

  // ------------------------------------------------------------------ M1–M3

  /// Two spheres, [bare] on the left and [layered] on the right, lit by a
  /// light from the camera's upper right — `material_layers_test.dart`'s
  /// sphere, beside the one it is measured against.
  static Future<GoldenStaged> _layerPair(
    GoldenStage stage,
    List<Material> materials,
  ) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.15;
    final device = stage.device;
    final spacing = 1.2;
    return GoldenStaged(
      nodes: <SceneNode>[
        for (var i = 0; i < materials.length; i++)
          _sphere(
            device,
            Vector3((i - (materials.length - 1) / 2) * spacing, 0.0, 0.0),
            materials[i],
          ),
        _directional(Vector3(-0.35, -0.45, -1.0)),
      ],
      everyFrame: (_, _) => _look(
        stage.camera,
        Vector3(0.0, 0.2, 1.6 + materials.length * 0.9),
        Vector3.zero(),
      ),
    );
  }

  static Material _paint({
    MaterialExtensions? layers,
    double roughness = 0.6,
  }) => Material(
    lighting: LightingModel.pbrLayered,
    baseColor: Vector4(0.8, 0.05, 0.05, 1.0),
    roughness: roughness,
    extensions: layers,
  );

  /// `clearcoat-car-paint`: red paint, bare and under a sharp coat.
  static Future<GoldenStaged> clearcoat(GoldenStage stage) =>
      _layerPair(stage, <Material>[
        _paint(),
        _paint(
          layers: MaterialExtensions(clearcoat: 1.0, clearcoatRoughness: 0.15),
        ),
      ]);

  /// `sheen-fabric`: the red cloth, bare and with a blue sheen at its rim.
  static Future<GoldenStaged> sheen(GoldenStage stage) =>
      _layerPair(stage, <Material>[
        _paint(),
        _paint(
          layers: MaterialExtensions(
            sheenColor: Vector3(0.2, 0.4, 1.0),
            sheenRoughness: 0.5,
          ),
        ),
      ]);

  /// `anisotropy-disc`: the brushed lobe isotropic, then stretched along the
  /// tangent, then turned a quarter across it.
  static Future<GoldenStaged> anisotropy(GoldenStage stage) =>
      _layerPair(stage, <Material>[
        _paint(roughness: 0.3),
        _paint(
          roughness: 0.3,
          layers: MaterialExtensions(anisotropyStrength: 0.9),
        ),
        _paint(
          roughness: 0.3,
          layers: MaterialExtensions(
            anisotropyStrength: 0.9,
            anisotropyRotation: math.pi / 2,
          ),
        ),
      ]);

  /// `transmission-glass`: three panes of the layered model in front of a
  /// wall that is red on the left and blue on the right — clear, frosted,
  /// and thick with an index that bends what is behind it — reading the
  /// copy of the scene drawn before them. `transmission_glass_test.dart`'s
  /// wall and pane, three times.
  static Future<GoldenStaged> transmissionGlass(GoldenStage stage) async {
    stage.sun.setLocalForward(Vector3(-0.3, -0.6, -1.0).normalized());
    stage.scene.ambientIntensity = 0.2;
    final device = stage.device;
    final pane = DeviceMesh.upload(
      device,
      const PlaneShape(width: 1.2, depth: 1.6).build(),
    );
    final half = DeviceMesh.upload(
      device,
      const PlaneShape(width: 4.0, depth: 9.0).build(),
    );
    MeshNode wall(double x, Vector4 colour) => MeshNode(half, _unlit(colour))
      ..setPosition(x, 0.0, -4.0)
      ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0);
    MeshNode glass(double x, MaterialExtensions layers, double roughness) =>
        MeshNode(
            pane,
            Material(
              lighting: LightingModel.pbrLayered,
              baseColor: Vector4(1.0, 1.0, 1.0, 1.0),
              roughness: roughness,
              extensions: layers,
              doubleSided: true,
            ),
          )
          ..setPosition(x, 0.0, -2.0)
          ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0);
    // Stripes on the wall, so a blur and a bend have edges to act on.
    final stripes = <SceneNode>[
      for (var i = 0; i < 7; i++)
        MeshNode(
            DeviceMesh.upload(
              device,
              const PlaneShape(width: 0.12, depth: 9.0).build(),
            ),
            _unlit(Vector4(0.95, 0.95, 0.9, 1.0)),
          )
          ..setPosition(-3.0 + i, 0.0, -3.98)
          ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    ];
    return GoldenStaged(
      nodes: <SceneNode>[
        wall(-2.0, Vector4(0.8, 0.1, 0.1, 1.0)),
        wall(2.0, Vector4(0.1, 0.2, 0.9, 1.0)),
        ...stripes,
        glass(-1.35, MaterialExtensions(transmission: 1.0), 0.0),
        glass(0.0, MaterialExtensions(transmission: 1.0), 0.35),
        glass(
          1.35,
          MaterialExtensions(transmission: 1.0, thickness: 1.0, ior: 1.8),
          0.0,
        ),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.0, 2.5), Vector3(0.0, 0.0, -2.0)),
    );
  }

  // ------------------------------------------------------------------ C1, N5

  /// `splat-gltf`: `splat_gltf_test.dart`'s file — nine splats on a grid,
  /// red, green and blue by column, the middle one long and turned — placed
  /// by its node, in front of a dark wall that gives the frame bounds.
  static Future<GoldenStaged> splatGltf(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.0;
    final bytes = await rootBundle.load('assets/models/splat_grid.glb');
    final asset = await GltfLoader().load(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final splat = asset.splats.single;
    final placement = asset.nodes[splat.node];
    final node = SceneNode(name: 'splats')
      ..setPosition(
        placement.translation.x,
        placement.translation.y,
        placement.translation.z,
      )
      ..setScale(placement.scale.x, placement.scale.y, placement.scale.z);
    stage.renderer.addContributor(SplatContributor(splat.cloud, node: node));
    return GoldenStaged(
      nodes: <SceneNode>[node, _backdrop(stage.device, z: -3.0)],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.5, 0.0, 4.0), Vector3(0.5, 0.0, 0.0)),
    );
  }

  /// A wide unlit wall, nearly black: something with bounds for the demo to
  /// measure, behind content that has none.
  static MeshNode _backdrop(GraphicsDevice device, {required double z}) =>
      _slab(
        device,
        Vector3(40.0, 40.0, 0.1),
        Vector3(0.0, 0.0, z),
        _unlit(Vector4(0.04, 0.04, 0.05, 1.0)),
        name: 'backdrop',
      );

  /// `splat-stochastic`: three half-transparent splats, listed far to near,
  /// kept or dropped per pixel by a hash of the frame and averaged by the
  /// temporal resolve — `splat_stochastic_test.dart`'s layers.
  static Future<GoldenStaged> splatStochastic(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.0;
    final splats = <(Vector3, Vector4)>[
      (Vector3(0.3, 0.2, -1.0), Vector4(0.0, 0.0, 1.0, 0.9)),
      (Vector3(0.0, 0.0, 1.0), Vector4(1.0, 0.0, 0.0, 0.5)),
      (Vector3(-0.3, -0.1, 0.0), Vector4(0.0, 1.0, 0.0, 0.5)),
    ];
    const sigma = 0.6;
    final n = splats.length;
    final centres = Float32List(n * 3);
    final colours = Float32List(n * 4);
    final scales = Float32List(n * 3);
    final rotations = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      final (where, colour) = splats[i];
      centres.setAll(i * 3, <double>[where.x, where.y, where.z]);
      colours.setAll(i * 4, <double>[colour.x, colour.y, colour.z, colour.w]);
      scales.setAll(i * 3, <double>[sigma, sigma, sigma]);
      rotations[i * 4 + 3] = 1.0;
    }
    stage.renderer.addContributor(
      SplatContributor(
        SplatCloud(
          centres: centres,
          colours: colours,
          scales: scales,
          rotations: rotations,
        ),
      ),
    );
    return GoldenStaged(
      nodes: <SceneNode>[_backdrop(stage.device, z: -8.0)],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.0, 5.0), Vector3.zero()),
    );
  }

  static RenderSettings splatStochasticSettings(RenderSettings settings) =>
      _temporal(
        settings,
      ).copyWith(bloom: settings.bloom.copyWith(enabled: false));

  // ------------------------------------------------------------------ C4

  /// `impostor-forest`: five trees baked into an octahedral atlas on the
  /// software rasteriser and drawn as cards, each turned so the atlas is
  /// read from a different side, at the distance their chain switches to
  /// the card — `impostor_bake_test.dart`'s tree and forest.
  ///
  /// Baked here rather than read from a file, because the bake is the
  /// software device's and so the same bytes on every backend: the
  /// difference between two backends' pictures is then only the drawing.
  static Future<GoldenStaged> impostorForest(GoldenStage stage) async {
    stage.sun.setLocalForward(Vector3(-0.4, -1.0, -0.5).normalized());
    stage.scene.ambientIntensity = 0.2;
    final baked = await bakeImpostors(_tree(), cell: 32);
    final lod = baked.nodes.single.lods.single;
    final impostor = lod.impostor!;
    TextureHandle upload(EncodedImage image) {
      final decoded = decodePng(image.bytes)!;
      return stage.device.createTextureFromPixels(
        width: decoded.width,
        height: decoded.height,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(decoded.rgba),
      )!;
    }

    final albedo = upload(baked.images[impostor.albedoImage]);
    final normalDepth = upload(baked.images[impostor.normalDepthImage]);
    final distance =
        impostor.radius /
        (math.tan(20 * math.pi / 180) * lod.maxScreenFraction);
    const forest = <(double, double, double)>[
      (-7.0, 0.0, 0.3),
      (-3.5, 2.0, 1.4),
      (0.0, -1.0, 2.6),
      (3.5, 1.5, 4.0),
      (7.0, -0.5, 5.3),
    ];
    return GoldenStaged(
      nodes: <SceneNode>[
        for (final (x, z, yaw) in forest)
          ImpostorNode(
            stage.device,
            albedo: albedo,
            normalDepth: normalDepth,
            centre: impostor.centre,
            radius: impostor.radius,
          )..setLocalMatrix(Matrix4.translationValues(x, 0, z)..rotateY(yaw)),
      ],
      everyFrame: (_, _) => _look(
        stage.camera,
        Vector3(0.0, 4.0, distance),
        Vector3(0.0, 1.6, 0.0),
        fovY: 40 * math.pi / 180,
        near: 0.5,
        far: distance * 4,
      ),
    );
  }

  /// A trunk, a cone of a crown and a red ball hung off one side, which is
  /// what makes the tree look different from each side.
  static PlainModelDocument _tree() {
    final trunk = const CylinderShape(
      radiusTop: 0.12,
      radiusBottom: 0.18,
      height: 1.2,
      segments: 12,
    ).build(layout: VertexLayout.standard);
    final crown = const CylinderShape(
      radiusTop: 0.0,
      radiusBottom: 0.9,
      height: 2.2,
      segments: 16,
    ).build(layout: VertexLayout.standard);
    return PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: trunk.transformed(Matrix4.translationValues(0, 0.6, 0)),
          materialIndex: 0,
          name: 'trunk',
        ),
        ModelSurface(
          mesh: crown.transformed(Matrix4.translationValues(0, 2.2, 0)),
          materialIndex: 1,
          name: 'crown',
        ),
        ModelSurface(
          mesh: const SphereShape(radius: 0.4, segments: 12, rings: 8)
              .build(layout: VertexLayout.standard)
              .transformed(Matrix4.translationValues(0.95, 1.5, 0)),
          materialIndex: 2,
          name: 'fruit',
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(name: 'bark', baseColor: Vector4(0.45, 0.3, 0.18, 1)),
        SurfaceMaterial(name: 'leaves', baseColor: Vector4(0.25, 0.6, 0.2, 1)),
        SurfaceMaterial(name: 'fruit', baseColor: Vector4(0.85, 0.15, 0.1, 1)),
      ],
      nodes: <ModelNode>[
        ModelNode(name: 'tree', surfaces: <int>[0, 1, 2]),
      ],
    );
  }

  // ------------------------------------------------------------------ R4

  /// `taa-embers`: three embers crossing a dark wall, each a little more
  /// than its own width a frame, twelve steps and round again, under the
  /// resolve with the reactive mask at full — `reactive_mask_test.dart`'s
  /// ember, three rows of it.
  static Future<GoldenStaged> taaEmbers(GoldenStage stage) async {
    stage.sun.visible = false;
    final particles = ParticleSystem(capacity: 8, seed: 1);
    final ember = ParticleEffect(
      count: 1,
      emitter: const SphereEmitter(speed: Range.exact(0.0)),
      lifetime: const Range.exact(10.0),
      size: const Range.exact(0.3),
      color: Vector4(1.0, 0.6, 0.2, 1.0),
    );
    stage.renderer.addContributor(ParticleContributor(particles));
    return GoldenStaged(
      nodes: <SceneNode>[
        _slab(
          stage.device,
          Vector3(20.0, 20.0, 1.0),
          Vector3(0.0, 0.0, -6.5),
          _unlit(Vector4(0.2, 0.2, 0.2, 1.0)),
        ),
      ],
      everyFrame: (frame, _) {
        _look(stage.camera, Vector3.zero(), Vector3(0.0, 0.0, -1.0));
        particles.clear();
        for (final (row, offset) in <(double, int)>[
          (0.8, 0),
          (0.0, 4),
          (-0.8, 8),
        ]) {
          particles.burst(
            ember,
            Vector3(-2.2 + 0.4 * ((frame + offset) % 12), row, -5.0),
          );
        }
      },
    );
  }

  static RenderSettings taaEmbersSettings(RenderSettings settings) => _temporal(
    settings,
    temporal: const TemporalSettings(enabled: true, reactive: 1.0),
  ).copyWith(bloom: settings.bloom.copyWith(enabled: false));

  // ------------------------------------------------------------------ R5

  /// `easu-half`: `shadow-teapot` drawn at half its size and brought back up
  /// by the edge-adaptive filter and its sharpen.
  static RenderSettings easuHalf(RenderSettings settings) => settings.copyWith(
    renderScale: 0.5,
    spatialUpscale: const SpatialUpscaleSettings(enabled: true),
  );

  // ------------------------------------------------------------------ R6

  /// `motion-blur-spin`: a wheel of three spokes round a hub, turning at a
  /// steady rate, blurred along what each pixel travelled between frames:
  /// the rim streaks and the hub stays sharp — `motion_blur_test.dart`'s
  /// spoke, made a wheel.
  static Future<GoldenStaged> motionBlurSpin(GoldenStage stage) async {
    stage.sun.setLocalForward(Vector3(-2.0, -3.0, -4.0).normalized());
    final device = stage.device;
    final spoke = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(3.0, 0.3, 0.3)).build(),
    );
    final wheel = SceneNode(name: 'wheel')..setPosition(0.0, 0.0, -5.0);
    for (var i = 0; i < 3; i++) {
      wheel.add(
        MeshNode(
          spoke,
          Material(
            baseColor: <Vector4>[
              Vector4(0.9, 0.8, 0.2, 1.0),
              Vector4(0.2, 0.7, 0.9, 1.0),
              Vector4(0.9, 0.3, 0.3, 1.0),
            ][i],
          ),
        )..setRotationYawPitchRoll(0.0, 0.0, i * math.pi / 3),
      );
    }
    wheel.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const CylinderShape(
            radiusTop: 0.35,
            radiusBottom: 0.35,
            height: 0.5,
          ).build(),
        ),
        Material(baseColor: Vector4(0.5, 0.5, 0.5, 1.0)),
      )..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
    );
    return GoldenStaged(
      nodes: <SceneNode>[wheel],
      everyFrame: (frame, _) {
        _look(stage.camera, Vector3.zero(), Vector3(0.0, 0.0, -1.0));
        wheel.setRotationYawPitchRoll(0.0, 0.0, frame * 0.12);
      },
    );
  }

  static RenderSettings motionBlurSpinSettings(RenderSettings settings) =>
      settings.copyWith(
        surfaceBuffer: true,
        motionBlur: const MotionBlurSettings(enabled: true),
      );

  // ------------------------------------------------------------------ R7

  /// `window-interior`: a room lit through one window by the sun, seen from
  /// inside against the bright sky beyond it — the frame a global exposure
  /// has to choose between, and local exposure need not.
  static Future<GoldenStaged> windowInterior(GoldenStage stage) async {
    stage.sun
      ..intensity = 6.0
      ..setLocalForward(Vector3(0.25, -0.55, 1.0).normalized());
    stage.scene.ambientIntensity = 0.03;
    final device = stage.device;
    final plaster = Material(
      baseColor: Vector4(0.75, 0.72, 0.68, 1.0),
      roughness: 0.9,
    );
    // The back wall is four pieces round a window a metre and a half wide.
    //
    // **Every slab runs a wall's thickness past the ones it meets**, because
    // two slabs that only touch leave a seam the sun comes through: the
    // first recording had a dotted line of light along every corner of the
    // room, which a shadow map cannot close and which was nothing to do
    // with exposure.
    const width = 6.0;
    const height = 3.0;
    const depth = 6.0;
    const t = 0.2;
    const outer = width / 2 + t;
    return GoldenStaged(
      nodes: <SceneNode>[
        _slab(
          device,
          Vector3(width + 4 * t, t, depth + 4 * t),
          Vector3(0, -t / 2, 0),
          plaster,
        ),
        _slab(
          device,
          Vector3(width + 4 * t, t, depth + 4 * t),
          Vector3(0, height + t / 2, 0),
          plaster,
        ),
        for (final side in <double>[-1.0, 1.0])
          _slab(
            device,
            Vector3(t, height + 2 * t, depth + 2 * t),
            Vector3(side * (width / 2 + t / 2), height / 2, 0),
            plaster,
          ),
        // Back wall: left, right, below and above the opening.
        for (final side in <double>[-1.0, 1.0])
          _slab(
            device,
            Vector3(outer - 0.75, height + 2 * t, t),
            Vector3(side * (outer + 0.75) / 2, height / 2, -depth / 2),
            plaster,
          ),
        _slab(
          device,
          Vector3(1.6, 0.9, t),
          Vector3(0.0, 0.45, -depth / 2),
          plaster,
        ),
        _slab(
          device,
          Vector3(1.6, 0.7, t),
          Vector3(0.0, height - 0.35, -depth / 2),
          plaster,
        ),
        // The sky seen through it.
        _slab(
          device,
          Vector3(8.0, 8.0, 0.1),
          Vector3(0.0, 1.5, -depth / 2 - 2.0),
          Material(
            baseColor: Vector4(0.0, 0.0, 0.0, 1.0),
            emissive: Vector3(5.0, 6.0, 8.0),
          ),
        )..shadowCasting = ShadowCastingMode.off,
        // Something in the dark half of the room for the lift to find.
        _slab(
          device,
          Vector3(0.8, 0.8, 0.8),
          Vector3(-1.8, 0.4, -1.2),
          Material(baseColor: Vector4(0.6, 0.25, 0.15, 1.0)),
        ),
      ],
      everyFrame: (_, _) => _look(
        stage.camera,
        Vector3(0.8, 1.5, 2.6),
        Vector3(-0.2, 1.1, -3.0),
        fovY: 1.1,
      ),
    );
  }

  static RenderSettings windowInteriorSettings(RenderSettings settings) =>
      settings.copyWith(
        exposure: 1.0,
        bloom: settings.bloom.copyWith(enabled: false),
        localExposure: const LocalExposureSettings(
          enabled: true,
          strength: 1.0,
        ),
      );

  // ------------------------------------------------------------------ R8

  /// `glass-stack-oit`: three overlapping panes at three depths and two
  /// crossing through each other, in front of a grey wall, composited
  /// without a sort — `weighted_blended_test.dart`'s stack.
  static Future<GoldenStaged> glassStack(GoldenStage stage) async {
    stage.sun.visible = false;
    final device = stage.device;
    final quad = DeviceMesh.upload(
      device,
      const PlaneShape(width: 1.2, depth: 1.2).build(),
    );
    final panes = <({double x, double z, double yaw, Vector4 colour})>[
      (x: -0.3, z: -1.0, yaw: 0.0, colour: Vector4(0.9, 0.1, 0.1, 0.5)),
      (x: 0.0, z: -1.6, yaw: 0.0, colour: Vector4(0.1, 0.9, 0.1, 0.45)),
      (x: 0.3, z: -2.2, yaw: 0.0, colour: Vector4(0.1, 0.2, 0.9, 0.6)),
      (x: 0.1, z: -1.3, yaw: 0.6, colour: Vector4(0.9, 0.8, 0.1, 0.4)),
      (x: 0.1, z: -1.3, yaw: -0.6, colour: Vector4(0.8, 0.1, 0.9, 0.35)),
    ];
    return GoldenStaged(
      nodes: <SceneNode>[
        MeshNode(
            DeviceMesh.upload(
              device,
              const PlaneShape(width: 8, depth: 8).build(),
            ),
            _unlit(Vector4(0.45, 0.45, 0.45, 1.0), doubleSided: true),
          )
          ..setPosition(0.0, 0.0, -3.0)
          ..setRotationYawPitchRoll(0.0, math.pi / 2, 0.0),
        for (final pane in panes)
          MeshNode(
              quad,
              Material(
                lighting: LightingModel.unlit,
                baseColor: pane.colour,
                alphaMode: MaterialAlphaMode.blend,
                doubleSided: true,
              ),
            )
            ..setPosition(pane.x, 0.0, pane.z)
            ..setRotationYawPitchRoll(pane.yaw, math.pi / 2, 0.0),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 0.0)),
    );
  }

  static RenderSettings glassStackSettings(RenderSettings settings) =>
      settings.copyWith(transparency: TransparencyMode.weightedBlended);

  // ------------------------------------------------------------------ C8

  /// Four texels, one colour each, read without filtering.
  static TextureHandle _quadrants(GraphicsDevice device) =>
      device.createTextureFromPixels(
        width: 2,
        height: 2,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(
          Uint8List.fromList(<int>[
            ...<int>[230, 20, 20, 255],
            ...<int>[20, 230, 20, 255],
            ...<int>[20, 20, 230, 255],
            ...<int>[230, 230, 230, 255],
          ]),
        ),
      )!;

  /// A normal map whose four texels lean four different ways.
  static TextureHandle _leaningNormals(GraphicsDevice device) =>
      device.createTextureFromPixels(
        width: 2,
        height: 2,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData.sublistView(
          Uint8List.fromList(<int>[
            ...<int>[220, 128, 190, 255],
            ...<int>[128, 220, 190, 255],
            ...<int>[40, 128, 190, 255],
            ...<int>[128, 40, 190, 255],
          ]),
        ),
      )!;

  /// `texture-transform-per-map`: four plates from above, left to right —
  /// the quadrant texture as it is; turned, scaled and moved by its own
  /// transform; its colour and its glow moved two different ways; and a
  /// leaning normal map turned by its transform, lit from one side —
  /// `texture_transform_test.dart`'s plane and maps.
  static Future<GoldenStaged> textureTransforms(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene.ambientIntensity = 0.25;
    final device = stage.device;
    final plane = DeviceMesh.upload(
      device,
      const PlaneShape(width: 2.0, depth: 2.0).build(),
    );
    final turned = TextureTransform(
      offset: Vector2(0.75, 0.25),
      scale: Vector2(0.5, -0.75),
      rotation: math.pi / 2,
    );
    MeshNode plate(double x, Material material) =>
        MeshNode(plane, material)..setPosition(x, 0.0, 0.0);
    return GoldenStaged(
      nodes: <SceneNode>[
        plate(
          -3.3,
          Material(
            lighting: LightingModel.pbrLayered,
            albedo: _quadrants(device),
            albedoSampler: SamplerOptions.nearestClamp,
          ),
        ),
        plate(
          -1.1,
          Material(
            lighting: LightingModel.pbrLayered,
            albedo: _quadrants(device),
            albedoSampler: SamplerOptions.nearestClamp,
            textureTransforms: <MaterialMap, TextureTransform>{
              MaterialMap.baseColor: turned,
            },
          ),
        ),
        plate(
          1.1,
          Material(
            lighting: LightingModel.pbrLayered,
            baseColor: Vector4(0.3, 0.3, 0.3, 1.0),
            albedo: _quadrants(device),
            albedoSampler: SamplerOptions.nearestClamp,
            emissiveTexture: _quadrants(device),
            emissiveSampler: SamplerOptions.nearestClamp,
            emissive: Vector3(0.5, 0.5, 0.5),
            textureTransforms: <MaterialMap, TextureTransform>{
              MaterialMap.baseColor: TextureTransform(
                offset: Vector2(0.5, 0.0),
                scale: Vector2(0.5, 1.0),
              ),
              MaterialMap.emissive: TextureTransform(
                offset: Vector2(0.0, 0.5),
                scale: Vector2(1.0, 0.5),
              ),
            },
          ),
        ),
        plate(
          3.3,
          Material(
            lighting: LightingModel.pbrLayered,
            normal: _leaningNormals(device),
            normalSampler: SamplerOptions.nearestClamp,
            textureTransforms: <MaterialMap, TextureTransform>{
              MaterialMap.normal: turned,
            },
          ),
        ),
        LightNode(intensity: 3.0, castsShadow: false)
          ..setRotationYawPitchRoll(0.4, -1.0, 0.0),
      ],
      everyFrame: (_, _) => _look(
        stage.camera,
        Vector3(0.0, 8.0, 0.0),
        Vector3.zero(),
        up: Vector3(0.0, 0.0, -1.0),
      ),
    );
  }

  // ------------------------------------------------------------------ C9

  /// A lumpy sphere of about thirty thousand triangles: what a scan of a
  /// stone looks like to the renderer — `scan_chunks_test.dart`'s scan.
  static MeshData _scan() {
    final sphere = const SphereShape(
      radius: 1.0,
      segments: 160,
      rings: 96,
    ).build();
    final vertices = Float32List.fromList(sphere.vertices);
    final stride = sphere.layout.floatsPerVertex;
    for (var o = 0; o < vertices.length; o += stride) {
      final x = vertices[o], y = vertices[o + 1], z = vertices[o + 2];
      final bump =
          1.0 + 0.05 * math.sin(5 * x) * math.sin(4 * y) * math.sin(6 * z);
      vertices[o] = x * bump;
      vertices[o + 1] = y * bump;
      vertices[o + 2] = z * bump;
    }
    return MeshData(
      layout: sphere.layout,
      vertices: vertices,
      indices: sphere.indices,
    );
  }

  /// `scan-chunks`: the scan split into clusters of 128 to 512 triangles,
  /// culled by the frustum, their cones and the occlusion test behind a
  /// slab across the left of the view. The picture is the unsplit scan's.
  static Future<GoldenStaged> scanChunks(GoldenStage stage) async {
    stage.sun.visible = false;
    final device = stage.device;
    final split = clusterMesh(_scan(), maxTriangles: 512, minTriangles: 128);
    return GoldenStaged(
      nodes: <SceneNode>[
        MeshNode(
          DeviceMesh.upload(device, split),
          Material(baseColor: Vector4(0.8, 0.75, 0.7, 1.0), roughness: 0.8),
        )..setRotationYawPitchRoll(0.3, 0.1, 0.0),
        _slab(
          device,
          Vector3(1.6, 3.0, 0.1),
          Vector3(-0.9, 0.0, 1.4),
          Material(baseColor: Vector4(0.3, 0.35, 0.4, 1.0)),
        )..occluder = true,
        LightNode(intensity: 1.2, castsShadow: false)
          ..setRotationYawPitchRoll(0.4, -0.7, 0.0),
      ],
      // The test's first eye, drawn back a little: the slab hides the
      // scan's left half and the frame crops its top and bottom, so both
      // the occlusion and the frustum cull have chunks to leave out.
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.2, 3.4), Vector3(0.2, 0.1, 0.0)),
    );
  }

  static RenderSettings scanChunksSettings(RenderSettings settings) =>
      settings.copyWith(occlusion: OcclusionMode.software);

  // ------------------------------------------------------------------ N6

  /// `smoke-six-way`: three puffs of the engine's own baked smoke in a row,
  /// a red light on the left and a blue one on the right: each side of each
  /// puff takes the light on that side — `smoke_six_way_test.dart`'s puffs.
  ///
  /// Baked here, for the reason the impostors are: it is plain Dart and so
  /// the same sheet on every backend.
  static Future<GoldenStaged> smokeSixWay(GoldenStage stage) async {
    stage.sun.visible = false;
    stage.scene
      ..ambientIntensity = 0.0
      ..defaultLightWhenUnlit = false;
    final device = stage.device;
    final sheet = bakeSixWay(
      density: smokePuff(),
      frames: 1,
      columns: 1,
      cell: 32,
    );
    TextureHandle upload(Uint8List bytes) => device.createTextureFromPixels(
      width: sheet.width,
      height: sheet.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(bytes),
    )!;
    final particles = ParticleSystem(capacity: 8);
    for (final x in <double>[-0.4, 0.0, 0.4]) {
      particles.burst(
        ParticleEffect(
          count: 1,
          emitter: const SphereEmitter(speed: Range.exact(0.0)),
          lifetime: const Range.exact(5.0),
          size: const Range.exact(1.6),
          color: Vector4(1.0, 1.0, 1.0, 1.0),
        ),
        Vector3(x, 0.0, x * 0.5),
      );
    }
    stage.renderer.addContributor(
      ParticleContributor(
        particles,
        sixWay: SixWayMaterial(
          positive: upload(sheet.positive),
          negative: upload(sheet.negative),
        ),
      ),
    );
    LightNode point(Vector3 at, Vector3 colour) =>
        LightNode(type: LightType.point, intensity: 12.0, color: colour)
          ..castsShadow = false
          ..setPosition(at.x, at.y, at.z);
    return GoldenStaged(
      nodes: <SceneNode>[
        _backdrop(device, z: -6.0),
        point(Vector3(-3.0, 0.0, 0.0), Vector3(1.0, 0.2, 0.1)),
        point(Vector3(3.0, 0.0, 0.0), Vector3(0.1, 0.2, 1.0)),
      ],
      everyFrame: (_, _) =>
          _look(stage.camera, Vector3(0.0, 0.0, 4.0), Vector3.zero()),
    );
  }
}
