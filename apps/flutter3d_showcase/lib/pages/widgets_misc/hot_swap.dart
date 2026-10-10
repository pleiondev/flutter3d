/// What a hot reload does to a running world: a texture and a model whose
/// files changed are put in place of the old ones in the nodes already on
/// screen, a material's fields are set from outside and survive the next
/// swap, and a tunable changes through the input. The "files" are bytes this
/// page holds, read through the same injected readers a game's assets are.
///
/// Quoted by `hot_swap.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class HotSwapDemo extends ShowcaseDemo {
  /// The coordinator every `SceneSurface` registers with. It holds nothing
  /// outside a debug build.
  final HotSwap _hot = HotSwap.instance;

  static const String _posterPath = 'assets/poster.png';
  static const String _hullPath = 'assets_src/hull.glb';

  // #region files
  /// The poster's "file": three bytes, the colour it decodes to.
  Uint8List _posterFile = Uint8List.fromList(<int>[220, 40, 30]);

  /// The model's "file": one byte, 1 red, 2 green, 3 blue.
  Uint8List _hullFile = Uint8List.fromList(<int>[1]);
  // #endregion files

  late final Scene _scene;
  late final SwappableTexture _poster;
  late final SwappableModel _hull;
  late final ModelInstance _ship;

  /// What the last swap did, for the line beside the viewport.
  String _said = 'nothing swapped yet';

  /// The two pixels [verify] reads, before and after each change.
  final List<(List<int>, List<int>)> _shots = <(List<int>, List<int>)>[];
  HotSwapReport? _firstSwap;
  int _overridden = 0;
  late final MeshNode _shipMeshBefore;

  // #region tunable
  /// A number the game lets somebody change while it runs. It arrives
  /// through the input, so a recorded run changes it at the same step.
  final Tunables _tunables = Tunables(<String, double>{'spin': 0.6});
  final InputState _input = InputState();
  // #endregion tunable

  static const int _probeWidth = 96;
  static const int _probeHeight = 64;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.1
      ..yaw = 0.0;
  }

  // #region decoders
  /// What the texture file decodes to: a small square of its colour.
  static TextureHandle? _decodePoster(GraphicsDevice device, Uint8List bytes) {
    if (bytes.length != 3) return null;
    final ByteData pixels = ByteData(4 * 4 * 4);
    for (var i = 0; i < 16; i++) {
      pixels
        ..setUint8(i * 4, bytes[0])
        ..setUint8(i * 4 + 1, bytes[1])
        ..setUint8(i * 4 + 2, bytes[2])
        ..setUint8(i * 4 + 3, 255);
    }
    return device.createTextureFromPixels(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: pixels,
    );
  }

  /// What the model file builds: one box called `hull`, in a material
  /// called `hull paint` of the colour its byte names.
  static Future<ModelAsset> _buildHull(GraphicsDevice device, Uint8List bytes) {
    if (bytes.isEmpty || bytes.first < 1 || bytes.first > 3) {
      throw const FormatException('not a model');
    }
    final Vector4 color = Vector4(0.08, 0.08, 0.08, 1.0)
      ..[bytes.first - 1] = 0.9;
    return ModelAsset.fromDocument(
      PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(
            mesh: CuboidShape(size: Vector3.all(1.0)).build(),
            materialIndex: 0,
          ),
        ],
        materials: <SurfaceMaterial>[
          SurfaceMaterial(
            baseColor: _fromSrgb(color),
            unlit: true,
            name: 'hull paint',
          ),
        ],
        nodes: <ModelNode>[
          ModelNode(name: 'hull', surfaces: <int>[0]),
        ],
      ),
      device: device,
    );
  }
  // #endregion decoders

  @override
  Future<void> prepare(DemoContext context) async {
    final GraphicsDevice device = context.device;
    // #region register
    final TextureHandle first = _decodePoster(device, _posterFile)!;
    _poster = _hot.registerTexture(
      _posterPath,
      first,
      read: () async => _posterFile,
      build: (Uint8List bytes) async => _decodePoster(device, bytes),
      loadedFrom: _posterFile,
    );
    _hull = _hot.registerModel(
      _hullPath,
      await _buildHull(device, _hullFile),
      read: () async => _hullFile,
      build: (Uint8List bytes) => _buildHull(device, bytes),
      device: device,
      loadedFrom: _hullFile,
    );
    _scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1.2, 1.2, 0.05)).build(),
          ),
          RenderMaterial(name: 'poster', lighting: LightingModel.unlit)
            ..albedo = first,
          name: 'poster',
        )..setPosition(-0.9, 0.0, 0.0),
      );
    _ship = _hull.instantiate(_scene);
    _ship.root.setPosition(0.9, 0.0, 0.0);
    // What a `SceneSurface` registers for itself.
    _hot
      ..registerScene(_scene)
      ..registerRenderer(context.renderer);
    // #endregion register
    if (!_hot.enabled) {
      _said = 'hot swap is off outside a debug build';
      return;
    }
    _shipMeshBefore = _ship.meshes.single;

    // #region swap
    _shots.add(await _shoot(context));
    // Both files change on "disk", and a hot reload runs the swap.
    _posterFile = Uint8List.fromList(<int>[30, 60, 230]);
    _hullFile = Uint8List.fromList(<int>[2]);
    _firstSwap = await _hot.swap();
    _shots.add(await _shoot(context));
    // #endregion swap

    // #region material
    // An inspector drags the paint to yellow, then the model is saved again:
    // the override is put back on the material the new file brought.
    _overridden = _hot.setMaterial('hull paint', <String, Object?>{
      'baseColor': <double>[0.9, 0.8, 0.1, 1.0],
    });
    _hullFile = Uint8List.fromList(<int>[3]);
    await _hot.swap();
    _shots.add(await _shoot(context));
    // #endregion material
    _said = _describe(_firstSwap!);
  }

  static String _describe(HotSwapReport report) =>
      'textures ${report.textures}, models '
      '${<String>[for (final ModelSwapReport m in report.models) '${m.path} in ${m.instances}']}'
      '${report.refused.isEmpty ? '' : ', refused ${report.refused}'}';

  /// The poster's and the hull's middle pixel, drawn through a camera of
  /// the page's own.
  Future<(List<int>, List<int>)> _shoot(DemoContext context) async {
    final CameraNode eye =
        CameraNode(projection: const PerspectiveProjection(fovY: 0.8))
          ..setPosition(0.0, 0.0, 4.0)
          ..lookAt(Vector3.zero());
    _scene.add(eye);
    final FrameResult frame = context.renderer.render(
      width: _probeWidth,
      height: _probeHeight,
      scene: _scene,
      views: <RenderView>[RenderView(camera: eye)],
    );
    eye.removeFromParent();
    final ByteData read = await context.device.readback(frame.frame);
    final Matrix4 vp = eye.viewProjection(_probeWidth / _probeHeight);
    List<int> at(Vector3 world) {
      final Vector4 clip = vp.transformed(
        Vector4(world.x, world.y, world.z, 1.0),
      );
      final int x = ((clip.x / clip.w + 1.0) * 0.5 * _probeWidth).floor();
      final int y = ((1.0 - clip.y / clip.w) * 0.5 * _probeHeight).floor();
      final int i = (y * _probeWidth + x) * 4;
      return <int>[
        read.getUint8(i),
        read.getUint8(i + 1),
        read.getUint8(i + 2),
      ];
    }

    return (at(Vector3(-0.9, 0.0, 0.03)), at(Vector3(0.9, 0.0, 0.5)));
  }

  @override
  Scene build(DemoContext context) {
    _scene
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit;
    return _scene;
  }

  // #region step
  @override
  void update(DemoContext context, double dt) {
    _tunables.readFrom(_input);
    _yaw += _tunables['spin'] * dt;
    _ship.root.setRotationYawPitchRoll(_yaw, 0.0, 0.0);
    _input.endStep();
  }

  double _yaw = 0.0;
  // #endregion step

  @override
  void dispose() {
    _hot
      ..forgetTexture(_poster)
      ..clearMaterial('hull paint');
  }

  Future<void> _swapNow() async {
    _said = _describe(await _hot.swap());
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Repaint the poster file — $_said',
      value: () => false,
      onChanged: (bool v) {
        final int r = _posterFile[0];
        _posterFile = Uint8List.fromList(<int>[
          _posterFile[2],
          r,
          _posterFile[1],
        ]);
        _swapNow();
      },
    ),
    ToggleControl(
      'Save the model in its next colour',
      value: () => false,
      onChanged: (bool v) {
        _hullFile = Uint8List.fromList(<int>[_hullFile.first % 3 + 1]);
        _swapNow();
      },
    ),
    ToggleControl(
      'Paint dragged to yellow (material.set)',
      value: () => _overridden > 0,
      onChanged: (bool v) {
        if (v) {
          _overridden = _hot.setMaterial('hull paint', <String, Object?>{
            'baseColor': <double>[0.9, 0.8, 0.1, 1.0],
          });
        } else {
          // The material keeps the yellow until its file is loaded again.
          _hot.clearMaterial('hull paint');
          _overridden = 0;
          _hullFile = Uint8List.fromList(<int>[_hullFile.first % 3 + 1]);
          _swapNow();
        }
      },
    ),
    SliderControl(
      'Spin (a tunable)',
      min: 0.0,
      max: 3.0,
      value: () => _tunables['spin'],
      onChanged: (double v) => _input.tune('spin', v),
    ),
  ];

  static int _strongest(List<int> rgb) =>
      rgb.indexOf(rgb.reduce((int a, int b) => a > b ? a : b));

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_hot.enabled) throw StateError(_said);
    final [(posterA, hullA), (posterB, hullB), (_, hullC)] = _shots;
    // Before: a red poster and a red hull.
    if (_strongest(posterA) != 0 || _strongest(hullA) != 0) {
      throw StateError('before the swap: $posterA, $hullA');
    }
    // After one swap: the new texture in the poster's material, the new
    // model in the node the scene already had.
    final HotSwapReport report = _firstSwap!;
    if (!report.textures.contains(_posterPath) ||
        report.models.single.instances != 1) {
      throw StateError('the swap did not take both files: $report');
    }
    if (_strongest(posterB) != 2 || _strongest(hullB) != 1) {
      throw StateError('after the swap: $posterB, $hullB');
    }
    if (!identical(_ship.meshes.single, _shipMeshBefore)) {
      throw StateError('the model was drawn in a new node, not adopted');
    }
    // The override outlived the next save of the model: yellow, not blue.
    if (_overridden != 1 || hullC[0] <= hullC[2] || hullC[1] <= hullC[2]) {
      throw StateError('the dragged paint did not survive the swap: $hullC');
    }
    // A tunable set through the input is read by the step that takes it.
    _input.tune('spin', 2.0);
    _tunables.readFrom(_input);
    _input.endStep();
    if (_tunables['spin'] != 2.0 || _tunables.toJson()['spin'] != 2.0) {
      throw StateError('the tunable did not change: ${_tunables.values}');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
