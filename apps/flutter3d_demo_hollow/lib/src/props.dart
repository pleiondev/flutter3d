/// What stands in the valley besides the ground: the quarry's blocks, the
/// village's huts, and the volcano that wakes now and then.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'terrain.dart';

/// A body and what draws it.
final class Prop {
  Prop(this.body, this.node);

  final NativeBody body;
  final SceneNode node;
}

/// Granite blocks lying in the quarry, eight hundred kilograms each: one
/// the crane lifts and the car carries.
final class QuarryStones {
  QuarryStones(NativeWorld world, GraphicsDevice device, Scene scene)
    : _world = world {
    final size = Vector3(0.9, 0.55, 0.6);
    final mesh = DeviceMesh.upload(device, CuboidShape(size: size).build());
    final random = math.Random(41);
    for (var k = 0; k < 6; k++) {
      final x = quarryX - 2.5 + (k % 3) * 2.2 + random.nextDouble() * 0.4;
      final z = quarryZ - 1.2 + (k ~/ 3) * 2.4 + random.nextDouble() * 0.4;
      final body = world.addBody(
        position: Vector3(x, groundAt(x, z) + 0.5, z),
        mass: 2700.0 * size.x * size.y * size.z,
      );
      world
        ..setShape(body, NativeShape.box(size * 0.5))
        ..setRounding(body, 0.04)
        ..setMaterial(body, NativeMaterial.stone());
      final node = MeshNode(
        mesh,
        Material(
          name: 'granite',
          baseColor: Vector4(0.56, 0.54, 0.52, 1.0),
          roughness: 0.85,
        ),
        name: 'granite',
      );
      scene.add(node);
      stones.add(Prop(body, node));
    }
  }

  final NativeWorld _world;
  final List<Prop> stones = <Prop>[];

  List<NativeBody> get bodies => <NativeBody>[for (final s in stones) s.body];

  /// How many lie on the builder's ground.
  int get delivered => stones.where((s) {
    final p = _world.positionOf(s.body);
    return Vector2(p.x - siteX, p.z - siteZ).length < siteRadius;
  }).length;

  void update() {
    for (final s in stones) {
      final p = _world.positionOf(s.body);
      s.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(s.body));
    }
  }
}

/// Rafts of three pine logs lashed side by side, put on the river at the
/// spring now and then for the current to take over the falls, through the
/// lagoon and out by the ford. A handful at a time: the oldest is taken
/// away when another comes.
final class Rafts {
  Rafts(
    this._world,
    GraphicsDevice device,
    this._scene,
    this._hearing,
    this._river,
  ) : _logMesh = DeviceMesh.upload(
        device,
        const CylinderShape(
          radiusTop: _logRadius,
          radiusBottom: _logRadius,
          height: 2 * _logHalf,
          segments: 12,
        ).build(),
      );

  /// A log's radius and half its length, m, and how many rafts ride at once.
  static const double _logRadius = 0.15, _logHalf = 0.8;
  static const int _most = 5;

  /// Seconds between rafts.
  static const double _every = 25.0;

  final NativeWorld _world;
  final Scene _scene;
  final PhysicsHearing _hearing;
  final NativeShallowLiquid _river;
  final DeviceMesh _logMesh;
  final List<Prop> rafts = <Prop>[];
  double _since = _every - 3.0;

  late final NativeCompound _shape = _world.createCompound(<NativeCompoundPart>[
    // Logs as rounded bars along z, the current's way: a cylinder on its
    // side would roll on the bed, a raft does not.
    for (final x in <double>[-0.31, 0.0, 0.31])
      NativeCompoundPart(
        NativeShape.box(
          Vector3(_logRadius * 0.6, _logRadius * 0.6, _logHalf - 0.06),
        ),
        at: Vector3(x, 0, 0),
        rounding: _logRadius * 0.4,
      ),
  ]);

  void update(double dt) {
    _since += dt;
    if (_since >= _every) {
      _since = 0.0;
      _launch();
    }
    for (final r in rafts) {
      final p = _world.positionOf(r.body);
      r.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(r.body));
    }
  }

  void _launch() {
    if (rafts.length >= _most) {
      final oldest = rafts.removeAt(0);
      _hearing.forget(oldest.body);
      _world.removeBody(oldest.body);
      _scene.remove(oldest.node);
    }
    const z = springZ + 3.0;
    final x = riverX(z);
    final body = _world.addBody(
      position: Vector3(x, groundAt(x, z) + 0.8, z),
      // Pine at 450 kg/m³.
      mass: 3 * 450.0 * math.pi * _logRadius * _logRadius * 2 * _logHalf,
    );
    _world
      ..setCompound(body, _shape)
      ..setMaterial(body, NativeMaterial.wood());
    final node = SceneNode(name: 'raft');
    for (final x in <double>[-0.31, 0.0, 0.31]) {
      node.add(
        MeshNode(
            _logMesh,
            Material(
              name: 'log',
              baseColor: Vector4(0.42, 0.29, 0.17, 1.0),
              roughness: 0.85,
            ),
            name: 'log',
          )
          ..setPosition(x, 0, 0)
          ..setRotation(
            Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
          ),
      );
    }
    _scene.add(node);
    rafts.add(Prop(body, node));
    _hearing.watch(body, _river);
  }
}

/// The elder's idol: carved granite lying on the lagoon's floor where the
/// bank shelves, to be lifted onto the car and brought to the village.
final class Idol {
  Idol(this._world, GraphicsDevice device, Scene scene) {
    final at = Vector3(lagoonX - 2.0, 0.0, lagoonZ + 5.1);
    at.y = groundAt(at.x, at.z) + _half.y;
    body = _world.addBody(
      position: at,
      mass: 2700.0 * 8 * _half.x * _half.y * _half.z,
    );
    _world
      ..setShape(body, NativeShape.box(_half))
      ..setRounding(body, 0.03)
      ..setMaterial(body, NativeMaterial.stone());
    _look = MeshNode(
      DeviceMesh.upload(device, CuboidShape(size: _half * 2.0).build()),
      Material(
        name: 'idol',
        baseColor: Vector4(0.42, 0.40, 0.36, 1.0),
        roughness: 0.8,
      ),
      name: 'idol',
    );
    scene.add(_look);
  }

  /// Half its width, height and depth, m.
  static Vector3 get _half => Vector3(0.15, 0.25, 0.15);

  final NativeWorld _world;
  late final NativeBody body;
  late final MeshNode _look;
  NativeJoint? _lashed;

  Vector3 get position => _world.positionOf(body);

  /// Whether it rides on the car, and whether it stands in the village.
  bool get carried => _lashed != null;
  bool get home =>
      !carried &&
      Vector2(position.x - villageX, position.z - villageZ).length < 4.0;

  /// Lashed upright to the car's deck at [deck], when the car is near.
  bool lift(NativeBody car, Vector3 deck, Vector3 from) {
    if (carried ||
        Vector2(position.x - from.x, position.z - from.z).length > 3.0) {
      return false;
    }
    _world
      ..setPosition(body, deck + Vector3(0.0, _half.y, 0.0))
      ..setOrientation(body, _world.orientationOf(car))
      ..setVelocity(body, _world.velocityOf(car));
    _lashed = _world.createJoint(
      NativeJointType.fixed,
      car,
      body,
      anchor: deck,
    );
    return true;
  }

  /// Untied, to stand where the car stopped.
  void setDown() {
    final lashed = _lashed;
    if (lashed == null) return;
    _world.removeJoint(lashed);
    _lashed = null;
  }

  void update() => _look
    ..setPosition(position.x, position.y, position.z)
    ..setRotation(_world.orientationOf(body));
}

/// One hut: wooden walls and a thatched roof, each a body of its own, so
/// the roof catches first.
final class Hut {
  Hut(this.walls, this.roof, this.at, this.roofTop);

  final NativeBody walls, roof;

  /// Where it stands on the ground, and the peak of its roof.
  final Vector3 at, roofTop;
}

/// The village: four huts round a yard, fixed to the ground.
final class Village {
  Village(this._world, GraphicsDevice device, Scene scene, FireView fire) {
    const half = 1.4, wall = 1.1;
    final wallMesh = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(2 * half, 2 * wall, 2 * half)).build(),
    );
    final roofMesh = DeviceMesh.upload(
      device,
      const CylinderShape(
        radiusTop: 0.05,
        radiusBottom: 2.3,
        height: 1.8,
        segments: 20,
      ).build(),
    );
    final thatch = _thatch();
    for (var k = 0; k < 4; k++) {
      final angle = k * math.pi / 2 + math.pi / 4;
      final x = villageX + 5.0 * math.cos(angle);
      final z = villageZ + 5.0 * math.sin(angle);
      final g = groundAt(x, z);
      // Fixed, but of a mass: a fixed body of none is a reservoir to heat,
      // and these warm and burn as wood and straw do.
      final walls = _world.addBody(
        position: Vector3(x, g + wall, z),
        type: NativeBodyType.fixed,
        mass: 600.0,
      );
      _world
        ..setShape(walls, NativeShape.box(Vector3(half, wall, half)))
        ..setMaterial(walls, NativeMaterial.wood());
      // The thatch in sectors, each warming and catching on its own: a
      // red-hot stone in one heats the straw round it, not the whole roof
      // at once, and the fire goes on from sector to sector.
      final roof = _world.addBody(
        position: Vector3(x, g + 2 * wall, z),
        type: NativeBodyType.fixed,
        mass: 80.0,
      );
      _world
        ..setCompound(roof, thatch)
        // Dry stalks, that catch as paper does.
        ..setMaterial(roof, NativeMaterial.paper());
      final wallLook = MeshNode(
        wallMesh,
        Material(
          name: 'hut',
          baseColor: Vector4(0.48, 0.36, 0.22, 1.0),
          roughness: 0.9,
        ),
        name: 'hut',
      )..setPosition(x, g + wall, z);
      final roofLook = MeshNode(
        roofMesh,
        Material(
          name: 'thatch',
          baseColor: Vector4(0.72, 0.60, 0.33, 1.0),
          roughness: 0.95,
        ),
        name: 'thatch',
      )..setPosition(x, g + 2 * wall + 0.9, z);
      scene
        ..add(wallLook)
        ..add(roofLook);
      fire
        ..watch(walls, wallLook)
        ..watch(roof, roofLook);
      huts.add(
        Hut(walls, roof, Vector3(x, g, z), Vector3(x, g + 2 * wall + _peak, z)),
      );
    }
  }

  final NativeWorld _world;
  final List<Hut> huts = <Hut>[];

  /// The roof's cone: its radius at the eaves and its height, m, and how
  /// many sectors its thatch is in.
  static const double _eaves = 2.3, _peak = 1.8;
  static const int _sectors = 6;

  /// One roof's thatch: [_sectors] wedges of the cone from its peak to its
  /// eaves, each its own part, the cone's base on the walls' top.
  NativeCompound _thatch() {
    const arc = 4;
    final wedge = _world.createHull(<Vector3>[
      Vector3(0, _peak, 0),
      Vector3.zero(),
      for (var i = 0; i <= arc; i++)
        Vector3(
          _eaves * math.cos(2 * math.pi / _sectors * i / arc),
          0,
          _eaves * math.sin(2 * math.pi / _sectors * i / arc),
        ),
    ]);
    final centre = _world.hullOffset(wedge);
    NativeCompoundPart sector(int k) {
      final turn = Quaternion.axisAngle(
        Vector3(0, 1, 0),
        -2 * math.pi / _sectors * k,
      );
      return NativeCompoundPart.hull(
        wedge,
        at: turn.rotated(centre),
        turn: turn,
      );
    }

    return _world.createCompound(<NativeCompoundPart>[
      for (var k = 0; k < _sectors; k++) sector(k),
    ]);
  }

  /// How many huts burn.
  int get burning => huts
      .where((h) => _world.isBurning(h.walls) || _world.isBurning(h.roof))
      .length;

  /// Water thrown over the hut nearest [at] within [reach]; whether there
  /// was one.
  bool douse(Vector3 at, {double reach = 6.0, double kilograms = 50.0}) {
    Hut? nearest;
    var best = reach;
    for (final h in huts) {
      final d = Vector2(h.at.x - at.x, h.at.z - at.z).length;
      if (d < best) {
        best = d;
        nearest = h;
      }
    }
    if (nearest == null) return false;
    _world
      ..addWater(nearest.roof, 0.4 * kilograms)
      ..addWater(nearest.walls, 0.6 * kilograms);
    return true;
  }
}

/// The volcano: quiet, then for a while it pours lava from its crater and
/// throws red-hot bombs towards the village.
final class Volcano {
  Volcano(
    this._world,
    GraphicsDevice device,
    Scene scene,
    this._lava,
    this._huts,
  ) : _bombMesh = DeviceMesh.upload(
        device,
        const SphereShape(radius: 0.35, segments: 12, rings: 8).build(),
      ),
      _scene = scene;

  final NativeWorld _world;
  final Scene _scene;
  final NativeShallowLiquid _lava;
  final DeviceMesh _bombMesh;

  /// What it throws at: the huts' roofs.
  final List<Hut> _huts;
  final List<Prop> bombs = <Prop>[];

  /// How far a bomb sinks into the thatch that catches it, m.
  static const double _sinks = 0.04;

  /// The bombs a roof has caught, so each is caught once.
  final Set<NativeBody> _caught = <NativeBody>{};
  final math.Random _random = math.Random(7);

  /// Seconds into the run, and when it next wakes and for how long.
  double _clock = 0.0, _next = 40.0;
  static const double _erupting = 20.0, _quiet = 100.0;

  /// Whether it is erupting now, and how long until it next does.
  bool get erupting => _clock >= _next && _clock < _next + _erupting;
  double get untilNext => _clock < _next ? _next - _clock : 0.0;

  /// The crater's middle, a little above its floor.
  Vector3 get crater =>
      Vector3(volcanoX, groundAt(volcanoX, volcanoZ) + 0.8, volcanoZ);

  double _sinceBomb = 0.0;

  void update(double dt) {
    _clock += dt;
    final on = erupting;
    _world.setShallowSource(
      _lava,
      0,
      x: volcanoX,
      z: volcanoZ,
      radius: 1.2,
      rate: on ? 0.12 : 0.0,
    );
    if (on) {
      _sinceBomb += dt;
      if (_sinceBomb > 3.5) {
        _sinceBomb = 0.0;
        _throw();
      }
    }
    if (_clock >= _next + _erupting) _next = _clock + _quiet;
    _lodge();
    for (final b in bombs) {
      final p = _world.positionOf(b.body);
      b.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(b.body));
      // Glowing as hot as it is: red at a thousand kelvin, dark below six
      // hundred.
      final t = _world.surfaceTemperatureOf(b.body);
      final glow = ((t - 600.0) / 700.0).clamp(0.0, 1.0);
      (b.node as MeshNode).material.emissive.setValues(
        4.0 * glow,
        1.0 * glow * glow,
        0.2 * glow * glow * glow,
      );
    }
  }

  /// A bomb that comes down into thatch stays in it, as a red-hot stone
  /// sinks into dry straw rather than bouncing off it: held where it
  /// struck, still touching, so the stone's heat goes into the straw it
  /// lies in as well as across the air.
  void _lodge() {
    if (_caught.length == bombs.length) return;
    final roofs = <NativeBody, Hut>{for (final h in _huts) h.roof: h};
    for (final contact in _world.readContacts()) {
      final (bomb, roof) = roofs.containsKey(contact.a)
          ? (contact.b, contact.a)
          : (contact.a, contact.b);
      if (!roofs.containsKey(roof) || _caught.contains(bomb)) continue;
      if (!bombs.any((b) => b.body == bomb)) continue;
      // Sunk a few centimetres into the straw, and held there. A bomb this
      // fast is found a step before it strikes, the gap still between it
      // and the roof: it closes that first.
      final at = _world.positionOf(bomb);
      final gap = math.max(0.0, -contact.depth);
      _world
        ..setPosition(
          bomb,
          at - (at - contact.point).normalized() * (gap + _sinks),
        )
        ..setVelocity(bomb, Vector3.zero())
        ..setAngularVelocity(bomb, Vector3.zero());
      _world.setJointCollide(
        _world.createJoint(
          NativeJointType.fixed,
          roof,
          bomb,
          anchor: contact.point,
        ),
        collide: true,
      );
      _caught.add(bomb);
    }
  }

  /// A bomb thrown from the crater to come down on a roof, give or take a
  /// metre, in three and a half seconds: v = Δ/t − ½gt.
  void _throw() {
    final from = crater + Vector3(0, 1.0, 0);
    final target =
        _huts[_random.nextInt(_huts.length)].roofTop +
        Vector3(
          (_random.nextDouble() - 0.5) * 2.0,
          0.0,
          (_random.nextDouble() - 0.5) * 2.0,
        );
    const t = 3.5;
    final v = (target - from) / t + Vector3(0, 0.5 * 9.81 * t, 0);
    final body = _world.addBody(position: from, mass: 400.0);
    _world
      ..setShape(body, const NativeShape.sphere(0.35))
      ..setMaterial(body, NativeMaterial.stone())
      ..setTemperature(body, 1300.0)
      ..setVelocity(body, v);
    final node = MeshNode(
      _bombMesh,
      Material(
        name: 'bomb',
        baseColor: Vector4(0.15, 0.12, 0.11, 1.0),
        roughness: 0.9,
      ),
      name: 'bomb',
    );
    _scene.add(node);
    bombs.add(Prop(body, node));
  }
}
