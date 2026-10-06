/// A wooden board and a steel one either side of a block of stone at a
/// thousand degrees. The wood heats, catches, burns and loses mass; the
/// steel heats as well and never catches; water put on the wood puts it
/// out. The flames are particles carried up by a wind grid.
///
/// Quoted by `heat_and_fire.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// One flame particle: where it is and how long it has left, s.
final class _Flame {
  _Flame(this.node);

  final MeshNode node;
  final Vector3 position = Vector3.zero();
  double life = 0.0;
}

final class HeatAndFireDemo extends ShowcaseDemo {
  NativeWorld? _world;
  late NativeBody _heater;
  late NativeBody _wood;
  late NativeBody _steel;

  /// Why there is no fire, or null when the core started.
  String? fallback;

  /// The uniform wind, m/s along x, on top of the grid's.
  double wind = 0.0;

  /// Seconds of the world since the boards were put up.
  double _clock = 0.0;

  /// When the wood caught, and when it was put out; null until then.
  double? _caught;
  double? _doused;

  final List<_Flame> _flames = <_Flame>[];
  int _nextFlame = 0;
  final math.Random _random = math.Random(7);

  late Material _woodLook;
  late Material _steelLook;
  late MeshNode _woodNode;
  late MeshNode _steelNode;

  /// Each frame steps the world by this much: twenty times as fast as the
  /// clock on the wall, so a board takes seconds to catch and not minutes.
  static const double _lapse = 1 / 3;

  /// The heater's temperature, K: stone at a bright orange.
  static const double _hot = 1300.0;

  /// Half a board: twenty centimetres square and four thick.
  static Vector3 get _board => Vector3(0.02, 0.1, 0.1);
  static const double _apart = 0.3;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 1.6
      ..pitch = 0.35
      ..yaw = 0.3;
    context.orbit.target.setValues(0.0, 0.2, 0.0);
  }

  // #region bench
  /// The heater and the two boards, all fixed: nothing here has to move to
  /// burn. The heater has no mass, which makes it a reservoir: whatever it
  /// gives, it stays at its temperature.
  void _setUp() {
    _world?.dispose();
    final world = NativeWorld();
    _world = world;
    _heater = world.addBody(
      position: Vector3(0.0, 0.15, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setShape(_heater, NativeShape.box(Vector3.all(0.15)))
      ..setMaterial(_heater, NativeMaterial.stone())
      ..setTemperature(_heater, _hot);
    NativeBody board(double x, NativeMaterial material, double density) {
      final NativeBody b = world.addBody(
        position: Vector3(x, 0.1, 0.0),
        type: NativeBodyType.fixed,
        // A fixed body's mass is its thermal mass, and what burns away.
        mass: density * 8.0 * _board.x * _board.y * _board.z,
      );
      world
        ..setShape(b, NativeShape.box(_board))
        ..setMaterial(b, material);
      return b;
    }

    _wood = board(-_apart, NativeMaterial.wood(), 500.0);
    _steel = board(_apart, NativeMaterial.steel(), 7800.0);
    _setWind();
    _clock = 0.0;
    _caught = null;
    _doused = null;
  }
  // #endregion bench

  // #region wind
  /// A breeze that grows with height, from still air at the floor to a
  /// metre and a half a second a metre up, read trilinearly between the
  /// grid's two samples; and the uniform [wind] added everywhere.
  void _setWind() {
    _world!
      ..setWindGrid(
        origin: Vector3.zero(),
        cell: 1.0,
        nx: 1,
        ny: 2,
        nz: 1,
        velocities: Float32List.fromList(<double>[0, 0, 0, 1.5, 0, 0]),
      )
      ..wind = Vector3(wind, 0.0, 0.0);
  }
  // #endregion wind

  // #region douse
  /// Half a litre of water on the wood, and the heater let cool to the air.
  /// The water holds the board at its boiling point, below where wood
  /// burns, so the next step puts the fire out.
  void _douse() {
    final NativeWorld world = _world!;
    world
      ..addWater(_wood, 0.5)
      ..setTemperature(_heater, world.airTemperature);
    _doused = _clock;
  }
  // #endregion douse

  /// One step of [dt]: the world on, and what it said happened. The core
  /// passes the heater's radiation to the boards itself.
  List<NativeEvent> _advance(double dt) {
    // #region step
    _world!.step(dt);
    final List<NativeEvent> fire = <NativeEvent>[
      for (final NativeEvent e in _world!.readEvents())
        if (e.kind == NativeEventKind.ignited ||
            e.kind == NativeEventKind.extinguished ||
            e.kind == NativeEventKind.burntOut)
          e,
    ];
    // #endregion step
    _clock += dt;
    if (fire.any((e) => e.body == _wood && e.kind == NativeEventKind.ignited)) {
      _caught ??= _clock;
    }
    return fire;
  }

  @override
  void dispose() => _world?.dispose();

  @override
  Scene build(DemoContext context) {
    try {
      _setUp();
    } on Object catch (e) {
      _world = null;
      fallback = physicsCoreLoaded
          ? '$e'
          : 'the core is not loaded in this browser yet';
    }
    final DeviceMesh board = DeviceMesh.upload(
      context.device,
      CuboidShape(size: _board * 2.0).build(),
    );
    _woodLook = Material(
      name: 'wood',
      baseColor: Vector4(0.55, 0.36, 0.2, 1.0),
      roughness: 0.8,
    );
    _steelLook = Material(
      name: 'steel',
      baseColor: Vector4(0.6, 0.62, 0.65, 1.0),
      metallic: 0.8,
      roughness: 0.4,
    );
    _woodNode = MeshNode(board, _woodLook, name: 'wood')
      ..setPosition(-_apart, 0.1, 0.0);
    _steelNode = MeshNode(board, _steelLook, name: 'steel')
      ..setPosition(_apart, 0.1, 0.0);
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        LightNode(name: 'sun', intensity: 2.0)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.2, 0.04, 0.6)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.35, 0.35, 0.37, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.02, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3.all(0.3)).build(),
          ),
          Material(
            name: 'heater',
            baseColor: Vector4(0.4, 0.2, 0.15, 1.0),
            emissive: Vector3(1.0, 0.35, 0.08),
            emissiveStrength: 2.0,
          ),
          name: 'heater',
        )..setPosition(0.0, 0.15, 0.0),
      )
      ..add(_woodNode)
      ..add(_steelNode);
    final DeviceMesh spark = DeviceMesh.upload(
      context.device,
      const SphereShape(radius: 0.012, segments: 8, rings: 4).build(),
    );
    for (var i = 0; i < 80; i++) {
      final flame = _Flame(
        MeshNode(
          spark,
          Material(
            name: 'flame $i',
            baseColor: Vector4(1.0, 0.6, 0.2, 1.0),
            emissive: Vector3(1.0, 0.45, 0.1),
            emissiveStrength: 3.0,
          ),
          name: 'flame $i',
        )..visible = false,
      );
      _flames.add(flame);
      scene.add(flame.node);
    }
    return scene;
  }

  /// A board glows from dull red at 700 K to orange at 1100 K, and is
  /// darkened by the water on it.
  void _look(Material look, NativeBody body) {
    final NativeWorld world = _world!;
    final double t = world.temperatureOf(body);
    final double glow = ((t - 700.0) / 400.0).clamp(0.0, 1.0);
    look.emissive.setValues(glow, 0.3 * glow * glow, 0.0);
    final double wet = world.waterOf(body) > 0.0 ? 0.6 : 1.0;
    look.emissiveStrength = 2.0 * wet;
  }

  // #region flames
  /// Flames from every burning body, as many as its fire gives off heat,
  /// risen by their own heat and carried by the wind where they are.
  void _flicker(double seconds) {
    final NativeWorld world = _world!;
    final ({Float32List fires, List<NativeBody> bodies}) burning = world
        .readFires();
    for (var i = 0; i < burning.bodies.length; i++) {
      final double watts = burning.fires[i * nativeFireFloats + 3];
      final int count = (watts / 5000.0).ceil().clamp(1, 4);
      for (var k = 0; k < count; k++) {
        final _Flame f = _flames[_nextFlame];
        _nextFlame = (_nextFlame + 1) % _flames.length;
        f
          ..life = 0.8
          ..position.setValues(
            burning.fires[i * nativeFireFloats] + (_random.nextDouble() - 0.5) * 0.05,
            burning.fires[i * nativeFireFloats + 1] + _board.y * _random.nextDouble(),
            burning.fires[i * nativeFireFloats + 2] + (_random.nextDouble() - 0.5) * 0.18,
          );
      }
    }
    for (final _Flame f in _flames) {
      if (f.life <= 0.0) {
        f.node.visible = false;
        continue;
      }
      final Vector3 carry = world.windAt(f.position);
      f.position
        ..x += carry.x * seconds
        ..y += 0.5 * seconds
        ..z += carry.z * seconds;
      f.life -= seconds;
      f.node
        ..visible = true
        ..setPosition(f.position.x, f.position.y, f.position.z)
        ..setUniformScale(math.max(f.life, 0.0) / 0.8);
    }
  }
  // #endregion flames

  @override
  void update(DemoContext context, double dt) {
    if (_world == null) return;
    _advance(_lapse);
    // Burnt for a minute, it is put out; half a minute later it all starts
    // again.
    final double? caught = _caught;
    if (caught != null && _doused == null && _clock - caught > 60.0) _douse();
    final double? doused = _doused;
    if (doused != null && _clock - doused > 30.0) _setUp();
    _look(_woodLook, _wood);
    _look(_steelLook, _steel);
    _flicker(dt);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      fallback == null ? 'Wind' : 'Wind (unavailable: $fallback)',
      min: 0.0,
      max: 8.0,
      value: () => wind,
      onChanged: (double v) {
        wind = v;
        if (_world != null) _setWind();
      },
      format: (double v) => '${v.toStringAsFixed(1)} m/s',
    ),
    ToggleControl(
      'Water on the wood',
      value: () => _doused != null,
      onChanged: (bool v) {
        if (v && _world != null && _doused == null) _douse();
      },
    ),
    ToggleControl(
      'Start again',
      value: () => false,
      onChanged: (bool v) {
        if (v && _world != null) _setUp();
      },
    ),
  ];

  /// The wood's and the steel's temperatures, K, for a test that reads them.
  @visibleForTesting
  (double wood, double steel) get temperatures =>
      (_world!.temperatureOf(_wood), _world!.temperatureOf(_steel));

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_world == null) throw StateError('the core did not start: $fallback');
    // #region check
    // From cold, in still air but for the grid's breeze, a second a step.
    wind = 0.0;
    _setUp();
    final NativeWorld world = _world!;
    final List<NativeEvent> said = <NativeEvent>[];
    var steps = 0;
    while (_caught == null && steps < 600) {
      said.addAll(_advance(1.0));
      steps++;
    }
    if (_caught == null) throw StateError('the wood never caught');
    // Burning, it loses mass: eleven grams a second per square metre.
    final double atIgnition = world.massOf(_wood);
    for (var i = 0; i < 20; i++) {
      said.addAll(_advance(1.0));
    }
    if (!world.isBurning(_wood)) throw StateError('the wood went out');
    if (world.massOf(_wood) >= atIgnition - 0.01) {
      throw StateError('the wood burnt nothing: ${world.massOf(_wood)} kg');
    }
    // The steel had the same heater, and was warmed by it, but never caught.
    if (world.temperatureOf(_steel) < world.airTemperature + 20.0) {
      throw StateError('the steel was never warmed');
    }
    if (world.isBurning(_steel) || said.any((e) => e.body == _steel)) {
      throw StateError('the steel caught fire');
    }
    // Water puts the fire out on the next step, and says so.
    _douse();
    final List<NativeEvent> after = _advance(1.0);
    if (world.isBurning(_wood) ||
        !after.any(
          (e) => e.body == _wood && e.kind == NativeEventKind.extinguished,
        )) {
      throw StateError('the water did not put the fire out');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
