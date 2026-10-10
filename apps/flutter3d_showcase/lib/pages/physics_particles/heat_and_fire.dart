/// A wooden board and a steel one either side of a block of stone at a
/// thousand degrees. The wood heats, catches, burns and loses mass; the
/// steel heats as well and never catches; water put on the wood puts it
/// out. The page steps the core's world itself; the effects package's
/// elements, adopting it, draw the fire.
///
/// Quoted by `heat_and_fire.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class HeatAndFireDemo extends ShowcaseDemo {
  NativeWorld? _world;
  Elements? _elements;
  Scene? _scene;
  late TrackedBody _heaterBody, _woodBody, _steelBody;
  NativeBody get _heater => _heaterBody.native;
  NativeBody get _wood => _woodBody.native;
  NativeBody get _steel => _steelBody.native;

  /// Why there is no fire, or null when the core started.
  String? fallback;

  /// The uniform wind, m/s along x, on top of the grid's.
  double wind = 0.0;

  /// Seconds of the world since the boards were put up.
  double _clock = 0.0;

  /// When the wood caught, and when it was put out; null until then.
  double? _caught;
  double? _doused;

  late RenderMaterial _steelLook;
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
  /// The world, once, and the elements that draw its fires, adopting it:
  /// the page steps it itself, faster than the clock.
  @override
  Future<void> prepare(DemoContext context) async {
    try {
      final world = NativeWorld();
      _world = world;
      final scene = _scene = Scene();
      _elements = await Elements.adopt(
        world,
        device: context.device,
        renderer: context.renderer,
        scene: scene,
        load: rootBundle.load,
        quality: const ElementsQuality(
          liquid: LiquidDetail.light,
          fire: FireDetail.light,
        ),
      );
    } on Object catch (e) {
      _world?.dispose();
      _world = null;
      fallback = physicsCoreLoaded
          ? '$e'
          : 'the core is not loaded in this browser yet';
    }
  }

  /// The heater and the two boards, all fixed: nothing here has to move to
  /// burn. The heater has no mass, which makes it a reservoir: whatever it
  /// gives, it stays at its temperature.
  void _setUp() {
    final elements = _elements!;
    for (final TrackedBody body in _bodies) {
      elements.remove(body);
    }
    _heaterBody = elements.addBody(
      Solid.box(
        Vector3.all(0.15),
        material: NativeMaterial.stone(),
        density: 0,
      ),
      at: Vector3(0.0, 0.15, 0.0),
      type: NativeBodyType.fixed,
    );
    elements.world.setTemperature(_heater, _hot);
    // A fixed body's mass is its thermal mass, and what burns away.
    _woodBody = elements.addBody(
      Solid.box(_board, material: NativeMaterial.wood(), density: 500.0),
      at: Vector3(-_apart, 0.1, 0.0),
      type: NativeBodyType.fixed,
      look: _woodNode,
    );
    _steelBody = elements.addBody(
      Solid.box(_board, material: NativeMaterial.steel(), density: 7800.0),
      at: Vector3(_apart, 0.1, 0.0),
      type: NativeBodyType.fixed,
      look: _steelNode,
    );
    _bodies = <TrackedBody>[_heaterBody, _woodBody, _steelBody];
    _setWind();
    _clock = 0.0;
    _caught = null;
    _doused = null;
  }

  List<TrackedBody> _bodies = const <TrackedBody>[];

  /// What the steps since the elements last drew said happened: the page
  /// reads the world's events, and hands them on.
  final List<NativeEvent> _said = <NativeEvent>[];
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
    final List<NativeEvent> said = _world!.readEvents();
    _said.addAll(said);
    final List<NativeEvent> fire = <NativeEvent>[
      for (final NativeEvent e in said)
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
  void dispose() {
    // The elements adopted the world, and leave it to the page.
    _elements?.dispose();
    _world?.dispose();
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh board = DeviceMesh.upload(
      context.device,
      CuboidShape(size: _board * 2.0).build(),
    );
    _steelLook = RenderMaterial(
      name: 'steel',
      baseColor: LinearColor.fromSrgb(0.6, 0.62, 0.65, 1.0),
      metallic: 0.8,
      roughness: 0.4,
    );
    // The wood chars and glows as it burns, as the elements draw it.
    _woodNode = MeshNode(
      board,
      RenderMaterial(
        name: 'wood',
        baseColor: LinearColor.fromSrgb(0.55, 0.36, 0.2, 1.0),
        roughness: 0.8,
      ),
      name: 'wood',
    )..setPosition(-_apart, 0.1, 0.0);
    _steelNode = MeshNode(board, _steelLook, name: 'steel')
      ..setPosition(_apart, 0.1, 0.0);
    final Scene scene = (_scene ?? Scene())
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.0 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(1.2, 0.04, 0.6)).build(),
          ),
          RenderMaterial(
            name: 'floor',
            baseColor: LinearColor.fromSrgb(0.35, 0.35, 0.37, 1.0),
          ),
          name: 'floor',
        )..setPosition(0.0, -0.02, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3.all(0.3)).build(),
          ),
          RenderMaterial(
            name: 'heater',
            baseColor: LinearColor.fromSrgb(0.4, 0.2, 0.15, 1.0),
            emissive: LinearColor(1.0, 0.35, 0.08),
            emissiveStrength: 2.0 * Photometric.legacyNits,
          ),
          name: 'heater',
        )..setPosition(0.0, 0.15, 0.0),
      )
      ..add(_woodNode)
      ..add(_steelNode);
    if (_elements != null) _setUp();
    return scene;
  }

  // #region glow
  /// The steel glows as hot metal does: a grey body at its surface's
  /// temperature, ε·σT⁴·η(T)/π candela a square metre, η the lumens a
  /// radiated watt is worth at T, in the renderer's units — nothing to see
  /// at the room's temperature, a dull red past 800 K. Its surface's
  /// temperature is what the core says, held at boiling while water is on
  /// it.
  void _look(RenderMaterial look, NativeBody body) {
    final NativeWorld world = _world!;
    final double t = world.surfaceTemperatureOf(body);
    final double nits =
        NativeMaterial.steel().emissivity *
        stefanBoltzmann *
        t *
        t *
        t *
        t *
        Blackbody.efficacy(t) /
        math.pi;
    final Vector3 color = Blackbody.color(t);
    final double y = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z;
    // Over `bulbAtOneMeter` and drawn at `legacyNits`: about 29 times the
    // true luminance, the gain `FireView` draws its flames with, so the hot
    // block glows beside them as it would beside a fire.
    look.emissive =
        (color * (y > 0.0 ? nits / Photometric.bulbAtOneMeter / y : 0.0))
            .toLinearColor();
    look.emissiveStrength = 1.0 * Photometric.legacyNits;
  }
  // #endregion glow

  // #region flames
  /// The fires drawn as the world has them: the elements adopted the world,
  /// so they draw and do not step it. Each flame stands on the patch alight
  /// and is as long as the core says, its smoke and embers carried by the
  /// wind where it is, its light the radiant share of its heat.
  void _flicker(double seconds, Vector3 eye) {
    _elements?.update(seconds, eye: eye, events: List<NativeEvent>.of(_said));
    _said.clear();
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
    _look(_steelLook, _steel);
    _flicker(dt, context.camera.readWorldPosition());
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
    // Burning, it loses what it gives off, over a patch that is still
    // small twenty seconds after it caught.
    final double atIgnition = world.massOf(_wood);
    for (var i = 0; i < 20; i++) {
      said.addAll(_advance(1.0));
    }
    if (!world.isBurning(_wood)) throw StateError('the wood went out');
    if (world.massOf(_wood) >= atIgnition) {
      throw StateError('the wood burnt nothing: ${world.massOf(_wood)} kg');
    }
    // The steel had the same heater, and was warmed by it, but never caught:
    // with fifteen times the wood's mass it warms slowly, a few kelvin in
    // the half minute the wood took to catch and burn.
    if (world.temperatureOf(_steel) <= world.airTemperature + 1.0) {
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
