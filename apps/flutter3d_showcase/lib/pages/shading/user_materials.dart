/// A material written by the game in the engine's language: a `uniform` the
/// game sets, a `light` block that cuts the light into bands, and four
/// numbers per copy read as `instance`, drawn on three spheres of one
/// instanced batch.
///
/// Quoted by `user_materials.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show materialLanguageCompiler;
import 'package:flutter3d_cpu/flutter3d_cpu.dart'
    show CpuDevice, CpuLoadedShaderLibrary;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class UserMaterialsDemo extends ShowcaseDemo {
  // #region source
  /// The `.f3dmat` this page draws. `user_materials.f3dshaders` beside this
  /// file is what the build compiled it into, and carries this text in it.
  static const String source = '''
material ToonInstances {
  param float bands = 3.0;
  uniform vec3 paint = vec3(1.0, 1.0, 1.0);

  light {
    let banded = floor(nDotL * bands + 0.5) / bands;
    return albedo * paint * banded / max(nDotL, 0.001);
  }

  fragment {
    let rim = pow(1.0 - clamp(nDotV, 0.0, 1.0), 4.0) * instance.w;
    return vec4(lit * instance.rgb + vec3(rim), 1.0);
  }
}
''';
  // #endregion source

  static const String _name = 'ToonInstances';
  static const String _bundlePath =
      'lib/pages/shading/user_materials.f3dshaders';

  /// Each copy's own four numbers: a colour, and how strongly its rim glows.
  static const List<(double, double, double, double)> _numbers =
      <(double, double, double, double)>[
        (0.95, 0.3, 0.2, 0.0),
        (0.3, 0.85, 0.35, 0.6),
        (0.3, 0.5, 0.95, 1.2),
      ];

  static const int _probeWidth = 160;
  static const int _probeHeight = 80;

  late final ByteData _bytes;
  late final RenderMaterial _toon;

  /// How the stage reached this device, or why it did not.
  String _how = '';
  bool _drawn = false;

  /// The probe frame [verify] reads, and where each copy's centre is in it.
  late final Uint8List _probe;
  late final List<(int, int)> _centers;
  late final int _radius;

  double _warmth = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.15
      ..yaw = 0.0;
  }

  // #region compile
  /// The bundle on [device]: the GPU sections where there is a GPU, and the
  /// source compiled into a Dart stage on the software rasteriser.
  Future<LoadedShaderLibrary> _load(GraphicsDevice device) async {
    try {
      final LoadedShaderLibrary library = await device.loadShaders(_bytes);
      _how = 'loaded from the bundle';
      return library;
    } on ShaderBundleException {
      // A software device opened without a material compiler refuses the
      // source; this one is given the compiler `openDevice` would give it.
      if (device case final CpuDevice cpu when cpu.materialCompiler == null) {
        _how = 'compiled from the source on the software rasteriser';
        return CpuLoadedShaderLibrary.load(
          cpu.shaders,
          _bytes,
          compiler: materialLanguageCompiler,
        );
      }
      rethrow;
    }
  }
  // #endregion compile

  @override
  Future<void> prepare(DemoContext context) async {
    _bytes = await rootBundle.load(_bundlePath);
    // #region bind
    final BundledMaterials materials = BundledMaterials.read(_bytes);
    _toon = RenderMaterial(
      name: 'toon',
      lighting: materials[_name],
      // `paint` at its default, in a list of the material's own.
      parameters: materials.parameters(_name),
    );
    try {
      context.renderer.renderSteps.addMaterials(await _load(context.device));
      _drawn = true;
    } on ShaderBundleException catch (refusal) {
      _how = 'not drawn here: ${refusal.reason}';
      _toon.lighting = LightingModel.toon;
    }
    // #endregion bind

    final CameraNode eye =
        CameraNode(projection: const PerspectiveProjection(fovY: 0.7))
          ..setPosition(0.0, 0.0, 5.0)
          ..lookAt(Vector3.zero());
    final Scene probe = _scene(context.device)..add(eye);
    final FrameResult frame = context.renderer.render(
      width: _probeWidth,
      height: _probeHeight,
      scene: probe,
      views: <RenderView>[
        RenderView(camera: eye, clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0)),
      ],
      // No dither and no bloom, so a band is one value from edge to edge.
      settings: const RenderSettings(
        bloom: BloomSettings(enabled: false),
        look: LookSettings(dither: 0.0),
      ),
    );
    final ByteData read = await context.device.readback(frame.frame);
    _probe = read.buffer.asUint8List(read.offsetInBytes, read.lengthInBytes);
    final Matrix4 vp = eye.viewProjection(_probeWidth / _probeHeight);
    _centers = <(int, int)>[
      for (var i = 0; i < _numbers.length; i++)
        _pixelOf(vp, Vector3(_x(i), 0, 0)),
    ];
    _radius = _pixelOf(vp, Vector3(_x(0) + 0.5, 0, 0)).$1 - _centers[0].$1;
  }

  static double _x(int i) => (i - 1) * 1.3;

  static (int, int) _pixelOf(Matrix4 vp, Vector3 world) {
    final Vector4 clip = vp.transformed(
      Vector4(world.x, world.y, world.z, 1.0),
    );
    return (
      ((clip.x / clip.w + 1.0) * 0.5 * _probeWidth).floor(),
      ((1.0 - clip.y / clip.w) * 0.5 * _probeHeight).floor(),
    );
  }

  // #region instances
  /// One batch, one draw: the copies differ only in the numbers given each.
  InstancedMeshNode _batch(GraphicsDevice device) {
    final InstancedMeshNode batch = InstancedMeshNode(
      DeviceMesh.upload(
        device,
        SphereShape(radius: 0.5, segments: 48, rings: 24).build(),
      ),
      _toon,
      capacity: _numbers.length,
      name: 'copies',
    );
    for (final (int i, (double r, double g, double b, double rim))
        in _numbers.indexed) {
      batch.addInstance(
        Matrix4.translationValues(_x(i), 0.0, 0.0),
        data: Vector4(r, g, b, rim),
      );
    }
    return batch;
  }
  // #endregion instances

  Scene _scene(GraphicsDevice device) => Scene()
    ..ambientColor = LinearColor(0.6, 0.65, 0.8)
    ..ambientIntensity = 0.08 * Photometric.legacyUnit
    ..add(_batch(device))
    ..add(
      LightNode(
        name: 'sun',
        intensity: 1.4 * Photometric.legacyUnit,
        castsShadow: false,
      )..setLocalForward(Vector3(0.55, -0.45, -0.7)),
    );

  @override
  Scene build(DemoContext context) => _scene(context.device);

  // #region uniform
  /// Warmer paint, written into the list `RenderMaterial.parameters` holds; the
  /// renderer binds it every frame, so nothing is rebuilt.
  void _setWarmth(double warmth) {
    _warmth = warmth;
    _toon.parameters['paint']!.setAll(0, <double>[
      1.0,
      1.0 - 0.35 * warmth,
      1.0 - 0.7 * warmth,
    ]);
  }
  // #endregion uniform

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Paint warmth (a uniform) — $_how',
      min: 0.0,
      max: 1.0,
      value: () => _warmth,
      onChanged: _setWarmth,
    ),
  ];

  /// The red byte of the probe at ([x], [y]), and its three channels.
  List<int> _rgb(int x, int y) {
    final int at = (y * _probeWidth + x) * 4;
    return <int>[_probe[at], _probe[at + 1], _probe[at + 2]];
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final String? carried = decodeMaterialSection(
      ShaderBundle.decode(_bytes),
    )[_name];
    if (carried?.trim() != source.trim()) {
      throw StateError('the bundle was not built from the source on the page');
    }
    if (!_drawn || _probe.isEmpty) throw StateError('not drawn: $_how');
    // Each copy is painted by its own numbers: its strongest channel is the
    // one its own colour says.
    for (final (int i, (double r, double g, double b, _)) in _numbers.indexed) {
      final (int x, int y) = _centers[i];
      final List<int> got = _rgb(x, y);
      final List<double> want = <double>[r, g, b];
      final int wanted = want.indexOf(want.reduce((a, b) => a > b ? a : b));
      final int strongest = got.indexOf(got.reduce((a, b) => a > b ? a : b));
      if (strongest != wanted) {
        throw StateError('copy $i reads $got, not its own colour $want');
      }
    }
    // The light comes in bands: across the first copy, which has no rim,
    // the shade takes a handful of values where n·l alone would give one
    // for nearly every pixel.
    final (int cx, int cy) = _centers[0];
    final int reach = (_radius * 0.85).floor();
    final Set<int> shades = <int>{
      for (int x = cx - reach; x <= cx + reach; x++) _rgb(x, cy)[0],
    };
    if (shades.length < 2 || shades.length > 5) {
      throw StateError(
        '${2 * reach + 1} pixels across the sphere take ${shades.length} '
        'shades; three bands and the unlit side are at most five',
      );
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
