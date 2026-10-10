/// What stands in the valley besides the ground: the quarry's blocks, the
/// village's huts, and the volcano that wakes now and then.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show GameRandom;

import 'looks.dart';
import 'terrain.dart';

/// A body and what draws it.
final class Prop {
  Prop(this.body, this.node);

  final NativeBody body;
  final SceneNode node;
}

/// Granite blocks lying in the quarry, eight hundred kilograms each: one
/// the crane lifts and the car carries.
///
/// Each is drawn as a boulder squeezed to the block the core has, turned a
/// different way so no two lie alike, in granite.
final class QuarryStones {
  QuarryStones(NativeWorld world, Scene scene, HollowLooks looks)
    : _world = world {
    final size = Vector3(0.9, 0.55, 0.6);
    final boulder = looks.boulder;
    final bounds = boulder.localBounds;
    final extent = bounds.max - bounds.min;
    final center = (bounds.min + bounds.max)..scale(0.5);
    final granite = covered(
      'granite',
      looks.granite,
      tint: Vector4(0.9, 0.88, 0.85, 1.0),
      repeat: Vector2(2.0, 2.0),
    );
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
      // Half turns only, about each axis, so the boulder still fills the
      // block's three sides; which half turn differs from block to block.
      final flip = _turn(
        <Vector3>[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)][k % 3],
        k < 3 ? math.pi : 0.0,
      );
      final fit = SceneNode(name: 'granite fit')
        ..setRotation(flip)
        ..setScale(
          size.x / extent.x * 1.06,
          size.y / extent.y * 1.06,
          size.z / extent.z * 1.06,
        );
      final node = SceneNode(name: 'granite')..add(fit);
      scene.add(node);
      final drawn = boulder.instantiate(scene, parent: fit, name: 'granite');
      drawn.root.setPosition(-center.x, -center.y, -center.z);
      for (final mesh in drawn.meshes) {
        mesh.material = granite;
      }
      stones.add(Prop(body, node));
    }
  }

  final NativeWorld _world;
  final List<Prop> stones = <Prop>[];

  List<NativeBody> get bodies => <NativeBody>[for (final s in stones) s.body];

  /// How many lie on the builder's ground.
  int get delivered => stones.where((s) {
    final p = _world.localPositionOf(s.body);
    return Vector2(p.x - siteX, p.z - siteZ).length < siteRadius;
  }).length;

  void update() {
    for (final s in stones) {
      final p = _world.localPositionOf(s.body);
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
  Rafts(this._world, GraphicsDevice device, this._scene, HollowLooks looks)
    : _logMesh = DeviceMesh.upload(
        device,
        const CylinderShape(
          radiusTop: _logRadius * 0.92,
          radiusBottom: _logRadius,
          height: 2 * _logHalf,
          segments: 12,
        ).build(),
      ),
      _bark = covered('log', looks.bark, repeat: Vector2(2.0, 1.5));

  /// A log's radius and half its length, m, and how many rafts ride at once.
  static const double _logRadius = 0.15, _logHalf = 0.8;
  static const int _most = 5;

  /// Seconds between rafts.
  static const double _every = 25.0;

  final NativeWorld _world;
  final Scene _scene;
  final DeviceMesh _logMesh;
  final RenderMaterial _bark;
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
      final p = _world.localPositionOf(r.body);
      r.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(r.body));
    }
  }

  void _launch() {
    if (rafts.length >= _most) {
      final oldest = rafts.removeAt(0);
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
    rafts.add(_drawn(body));
  }

  /// [body] with three logs drawn on it, in the scene.
  Prop _drawn(NativeBody body) {
    final node = SceneNode(name: 'raft');
    for (final x in <double>[-0.31, 0.0, 0.31]) {
      node.add(
        MeshNode(_logMesh, _bark, name: 'log')
          ..setPosition(x, 0, 0)
          ..setRotation(_turn(Vector3(1.0, 0.0, 0.0), math.pi / 2)),
      );
    }
    _scene.add(node);
    return Prop(body, node);
  }

  /// The time since the last raft and the rafts afloat, by their bodies.
  Map<String, Object?> save() => <String, Object?>{
    'since': _since,
    'bodies': <int>[for (final r in rafts) r.body.raw],
  };

  /// Back to what [save] wrote, the world already restored under it: the
  /// rafts drawn again for the bodies it names.
  void restore(Object? saved) {
    if (saved case {
      'since': final num since,
      'bodies': final List<Object?> bodies,
    }) {
      _since = since.toDouble();
      for (final r in rafts) {
        _scene.remove(r.node);
      }
      rafts
        ..clear()
        ..addAll(<Prop>[
          for (final raw in bodies.whereType<num>())
            _drawn(NativeBody(raw.toInt())),
        ]);
    }
  }
}

/// Pines over the grass: a trunk and a crown of resinous needles, fixed
/// where they grow, wood that a stray bomb can light as it lights a roof.
///
/// The core holds each as a trunk and a cone; what is drawn is one of two
/// pine models, a little taller than the cone, at heights that differ from
/// tree to tree.
final class Trees {
  Trees(this._world, Scene scene, FireView fire, HollowLooks looks) {
    final shape = _world.createCompound(<NativeCompoundPart>[
      NativeCompoundPart(
        const NativeShape.cylinder(_trunkRadius, _trunkHeight / 2),
        at: Vector3(0, _trunkHeight / 2, 0),
      ),
      // A cone's place is its centre of mass, a quarter up from its base.
      NativeCompoundPart(
        const NativeShape.cone(_crownRadius, _crownHeight),
        at: Vector3(0, _crownBase + _crownHeight / 4, 0),
      ),
    ]);
    final lift = _world.compoundOffset(shape);
    final random = math.Random(5);
    // Apart from [random], so the pines stand where they always stood.
    final heights = math.Random(6);
    var tries = 0;
    while (trees.length < _count && tries++ < 2000) {
      final x = 6.0 + random.nextDouble() * (hollowSize - 12.0);
      final z = 6.0 + random.nextDouble() * (hollowSize - 12.0);
      if (!_room(x, z)) continue;
      final g = groundAt(x, z);
      final body = _world.addBody(
        position: Vector3(x, g, z) + lift,
        type: NativeBodyType.fixed,
        mass: 260.0,
      );
      _world
        ..setCompound(body, shape)
        ..setMaterial(body, NativeMaterial.wood());
      final turn = _turn(Vector3(0, 1, 0), random.nextDouble() * 2 * math.pi);
      final node = SceneNode(name: 'pine')
        ..setPosition(x, g, z)
        ..setRotation(turn);
      scene.add(node);
      // Materials of its own, so a pine that burns chars alone.
      final drawn = looks.pines[trees.length % looks.pines.length]
          .instantiateFitted(
            scene,
            length: 5.0 + 1.4 * heights.nextDouble(),
            axis: 1,
            onGround: true,
            parent: node,
            name: 'pine',
            shareMaterials: false,
          );
      // Sunk a hand's breadth, so no root shows on a slope.
      drawn.root.translate(0, -0.1, 0);
      for (final look in drawn.meshes) {
        fire.watch(body, look);
      }
      trees.add(Prop(body, node));
    }
  }

  static const int _count = 28;
  static const double _trunkRadius = 0.16, _trunkHeight = 2.2;
  static const double _crownRadius = 1.2, _crownHeight = 3.4, _crownBase = 1.3;

  final NativeWorld _world;
  final List<Prop> trees = <Prop>[];

  /// Whether a pine may grow at (x, z): on the valley's open grass, clear
  /// of the river and its cliff, the lagoon and its ford, the quarry, the
  /// village, the builder's ground and the volcano, and of the other pines.
  bool _room(double x, double z) {
    double far(double ax, double az) => Vector2(x - ax, z - az).length;
    if (z < cliffTop && (x - riverX(z)).abs() < 4.0) return false;
    if (z > cliffTop - 2.0 && z < cliffFoot + 2.0) return false;
    if (far(lagoonX, lagoonZ) < lagoonRadius + 3.0) return false;
    if (x > lagoonX && (z - (lagoonZ + 0.1 * (x - lagoonX))).abs() < 5.0) {
      return false;
    }
    if ((x - quarryX).abs() < quarryHalfX + 3.0 &&
        (z - quarryZ).abs() < quarryHalfZ + 4.0) {
      return false;
    }
    if (far(villageX, villageZ) < 12.0 || far(siteX, siteZ) < 8.0) {
      return false;
    }
    if (far(volcanoX, volcanoZ) < volcanoRadius + 1.0) return false;
    for (final t in trees) {
      final p = _world.localPositionOf(t.body);
      if (far(p.x, p.z) < 4.0) return false;
    }
    return true;
  }
}

/// The elder's idol: carved granite lying on the lagoon's floor where the
/// bank shelves, to be lifted onto the car and brought to the village.
final class Idol {
  Idol(this._world, GraphicsDevice device, Scene scene, HollowLooks looks) {
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
    // A squat figure turned from the stone: a broad base, the hips, a
    // narrow waist, the shoulders and a round head, as tall as the block
    // the core holds.
    _look = MeshNode(
      DeviceMesh.upload(
        device,
        LatheShape(
          profile: <Vector2>[
            Vector2(0.0, -0.25),
            Vector2(0.13, -0.25),
            Vector2(0.13, -0.25),
            Vector2(0.15, -0.17),
            Vector2(0.14, -0.06),
            Vector2(0.09, 0.02),
            Vector2(0.13, 0.08),
            Vector2(0.11, 0.12),
            Vector2(0.06, 0.14),
            Vector2(0.08, 0.17),
            Vector2(0.075, 0.22),
            Vector2(0.04, 0.245),
            Vector2(0.0, 0.25),
          ],
          segments: 16,
        ).build(),
      ),
      covered(
        'idol',
        looks.granite,
        tint: Vector4(0.62, 0.58, 0.52, 1.0),
        repeat: Vector2(1.0, 0.5),
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

  Vector3 get position => _world.localPositionOf(body);

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

  /// The lashing to the car, by its joint, or null.
  Object? save() => _lashed?.raw;

  /// Back to what [save] wrote, the world already restored under it.
  void restore(Object? saved) =>
      _lashed = saved is num ? NativeJoint(saved.toInt()) : null;
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
///
/// The core holds a hut's walls as a box; what is drawn is round, wattle
/// daubed with clay, a doorway facing the yard, under a cone of thatch
/// that hangs over the walls as the core's cone does.
final class Village {
  Village(
    this._world,
    GraphicsDevice device,
    Scene scene,
    FireView fire,
    HollowLooks looks,
  ) {
    const half = 1.4, wall = 1.1;
    // The wall, a little narrower at the top, open at both ends: the roof
    // covers the one and the ground the other.
    final wallMesh = DeviceMesh.upload(
      device,
      LatheShape(
        profile: <Vector2>[
          Vector2(_round + 0.05, -wall),
          Vector2(_round, wall),
        ],
        segments: 28,
      ).build(),
    );
    // The thatch: from under the eaves, where it rests on the wall, out
    // over the drip edge and up to a knot of straw at the peak.
    final roofMesh = DeviceMesh.upload(
      device,
      LatheShape(
        profile: <Vector2>[
          Vector2(_round - 0.1, 0.05),
          Vector2(_eaves + 0.1, -0.28),
          Vector2(_eaves + 0.14, -0.16),
          Vector2(_eaves + 0.06, -0.04),
          Vector2(0.22, _peak - 0.05),
          Vector2(0.12, _peak + 0.12),
          Vector2(0.0, _peak + 0.18),
        ],
        segments: 32,
      ).build().withGeneratedTangents(),
    );
    final doorway = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(0.8, 1.4, 0.14)).build(),
    );
    // The doorway's frame: a post either side and a lintel over them, the
    // bark left on.
    final post = DeviceMesh.upload(
      device,
      const CylinderShape(
        radiusTop: 0.05,
        radiusBottom: 0.055,
        height: 1.5,
        segments: 8,
      ).build(),
    );
    final lintel = DeviceMesh.upload(
      device,
      const CylinderShape(
        radiusTop: 0.055,
        radiusBottom: 0.055,
        height: 1.1,
        segments: 8,
      ).build(),
    );
    final frame = covered('door frame', looks.bark, repeat: Vector2(1.0, 2.0));
    // The core puts a cone's origin at its centre of mass, a quarter of its
    // height over its base: the body stands that far above the walls' top
    // for the cone to sit on it.
    final lift = Vector3(0.0, _peak / 4.0, 0.0);
    for (var k = 0; k < 4; k++) {
      final angle = k * math.pi / 2 + math.pi / 4;
      final corner = Portable.sinCos(angle);
      final x = villageX + 5.0 * corner.cos;
      final z = villageZ + 5.0 * corner.sin;
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
      // The thatch, one cone: where a red-hot stone lies on it the straw
      // under the stone catches, and the fire creeps out over the roof from
      // there as fast as flame spreads over straw.
      final roof = _world.addBody(
        position: Vector3(x, g + 2 * wall, z) + lift,
        type: NativeBodyType.fixed,
        mass:
            _thatch *
            math.pi *
            _eaves *
            math.sqrt(_eaves * _eaves + _peak * _peak),
      );
      _world
        ..setShape(roof, const NativeShape.cone(_eaves, _peak))
        // Dry stalks, that catch as paper does, laid as a bed of fine fuel:
        // Anderson's fuel model 3, tall grass, σ = 1500 ft⁻¹ = 4921 m⁻¹,
        // and Rothermel's particle density, 32 lb/ft³ = 513 kg/m³ (USDA
        // INT-122, 1982; INT-115, 1972). A bed's stalks heat through and
        // no crust of char closes over them, so a roof a stone sets alight
        // burns on over the thatch rather than out under its own char.
        ..setMaterial(
          roof,
          NativeMaterial.paper().copyWith(
            elementSurface: 4921.0,
            elementDensity: 513.0,
          ),
        );
      final wallLook = MeshNode(
        wallMesh,
        covered(
          'hut',
          looks.daub,
          tint: Vector4(1.0, 0.9, 0.78, 1.0),
          repeat: Vector2(5.0, 1.0),
        ),
        name: 'hut',
      )..setPosition(x, g + wall, z);
      final roofLook = MeshNode(
        roofMesh,
        covered(
          'thatch',
          looks.thatch,
          // The photograph's straw is old and grey; this is a summer's.
          tint: Vector4(1.25, 1.02, 0.66, 1.0),
          repeat: Vector2(9.0, 1.6),
          relief: looks.thatchRelief,
          roughness: 1.0,
        ),
        name: 'thatch',
      )..setPosition(x, g + 2 * wall, z);
      // The doorway on the side that faces the yard: the dark inside, flush
      // with the wall, in a frame of barked poles.
      final toYard = Portable.atan2(villageX - x, villageZ - z);
      final facing = Portable.sinCos(toYard);
      final door = SceneNode(name: 'doorway')
        ..setPosition(
          x + (_round + 0.02) * facing.sin,
          g,
          z + (_round + 0.02) * facing.cos,
        )
        ..setRotation(_turn(Vector3(0, 1, 0), toYard))
        ..add(
          MeshNode(
            doorway,
            RenderMaterial(
              name: 'doorway',
              baseColor: LinearColor.fromSrgb(0.05, 0.04, 0.03, 1.0),
              roughness: 1.0,
            ),
            name: 'doorway',
          )..setPosition(0, 0.7, -0.02),
        )
        ..add(MeshNode(post, frame, name: 'post')..setPosition(-0.45, 0.75, 0))
        ..add(MeshNode(post, frame, name: 'post')..setPosition(0.45, 0.75, 0))
        ..add(
          MeshNode(lintel, frame, name: 'lintel')
            ..setPosition(0, 1.46, 0)
            ..setRotation(_turn(Vector3(0, 0, 1), math.pi / 2)),
        );
      scene
        ..add(wallLook)
        ..add(roofLook)
        ..add(door);
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

  /// The roof's cone: its radius at the eaves and its height, m.
  static const double _eaves = 2.3, _peak = 1.8;

  /// What a square metre of thatch weighs, kg: 24–34 kg/m², 5–7 lb a
  /// square foot (Thatch Advice Centre, Thatch Thursdays, June 2017), the
  /// middle of it here. Over the cone's slope, π·r·√(r² + h²) = 21 m², that
  /// is about 600 kg of straw for a red-hot stone lying in it to set
  /// alight.
  static const double _thatch = 29.0;

  /// The drawn wall's radius at its top, m: as far out as the core's box
  /// reaches at the middle of a side, and a little more.
  static const double _round = 1.6;

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
/// blows red-hot bombs out of it, through the breach in its rim on the
/// village's side.
final class Volcano {
  Volcano(
    this._world,
    GraphicsDevice device,
    Scene scene,
    this._lava,
    this._huts,
    HollowLooks looks,
  ) : _bombMesh = DeviceMesh.upload(
        device,
        const SphereShape(radius: 0.35, segments: 12, rings: 8).build(),
      ),
      _basalt = looks.basalt,
      _scene = scene;

  final NativeWorld _world;
  final Scene _scene;

  /// The lava, and the vent in the crater it wells up from.
  final WaterBody _lava;
  late final int _vent = _lava.addSpring(
    at: Vector3(volcanoX, 0.0, volcanoZ),
    discharge: 0.0,
    radius: 1.2,
  );
  bool _pouring = false;
  final DeviceMesh _bombMesh;

  /// What a bomb is: the volcano's own black rock.
  final TextureHandle? _basalt;

  /// The huts its bombs come down among.
  final List<Hut> _huts;
  final List<Prop> bombs = <Prop>[];

  /// Which hut a bomb is aimed at and how far off: the simulation's own
  /// dice, whose state a snapshot keeps.
  final GameRandom _random = GameRandom(7);

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
    if (on != _pouring) {
      _pouring = on;
      _lava.setSpring(_vent, discharge: on ? 0.12 : 0.0);
    }
    if (on) {
      _sinceBomb += dt;
      if (_sinceBomb > 3.5) {
        _sinceBomb = 0.0;
        _throw();
      }
    }
    if (_clock >= _next + _erupting) _next = _clock + _quiet;
    // The ground ends at the valley's edge: a bomb that rolls off it falls
    // for ever, faster than anything in the valley moves, and is gone.
    bombs.removeWhere((b) {
      final p = _world.localPositionOf(b.body);
      final off =
          p.x < 0.0 || p.x > hollowSize || p.z < 0.0 || p.z > hollowSize;
      if (off) {
        _world.removeBody(b.body);
        _scene.remove(b.node);
      }
      return off;
    });
    _lodge();
    for (final b in bombs) {
      final p = _world.localPositionOf(b.body);
      b.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(b.body));
      // Glowing as hot as it is: red at a thousand kelvin, dark below six
      // hundred.
      final t = _world.surfaceTemperatureOf(b.body);
      final glow = ((t - 600.0) / 700.0).clamp(0.0, 1.0);
      (b.node as MeshNode).material.emissive = LinearColor(
        4.0 * glow,
        1.0 * glow * glow,
        0.2 * glow * glow * glow,
      );
    }
  }

  /// Bombs that have come down on a roof, and stay in its thatch.
  final Set<NativeBody> _lodged = <NativeBody>{};

  /// A bomb that strikes a roof sinks into the thatch: a bed of loose
  /// stalks a hand or two deep takes a falling stone in rather than
  /// throwing it back, and holds it where it struck, so it neither bounces
  /// off nor rolls down the slope as off a hard cone. The core's roof is a
  /// hard cone, so the straw's hold is a slider along the roof's normal
  /// where the bomb struck: the bomb cannot roll or slide down, but bears
  /// on the roof with its weight, which is what presses the two together
  /// for heat to pass between them.
  void _lodge() {
    if (bombs.length == _lodged.length) return;
    final roofs = <NativeBody>{for (final h in _huts) h.roof};
    final flying = <NativeBody>{
      for (final b in bombs)
        if (!_lodged.contains(b.body)) b.body,
    };
    for (final c in _world.readContacts()) {
      final bomb = flying.contains(c.a) && roofs.contains(c.b)
          ? c.a
          : flying.contains(c.b) && roofs.contains(c.a)
          ? c.b
          : null;
      if (bomb == null || !_lodged.add(bomb)) continue;
      final roof = bomb == c.a ? c.b : c.a;
      _world
        ..setVelocity(bomb, Vector3.zero())
        ..setAngularVelocity(bomb, Vector3.zero());
      final hold = _world.createJoint(
        NativeJointType.prismatic,
        roof,
        bomb,
        anchor: _world.localPositionOf(bomb),
        axis: c.normal,
      );
      _world.setJointCollide(hold, collide: true);
    }
  }

  /// A bomb of molten rock in the crater, as hot as the lava it is torn
  /// from, and a pocket of gas half a metre under it going off: the blast
  /// throws it as the share of its momentum the bomb stands across says.
  ///
  /// The breach points it at one of the huts, a different one from bomb to
  /// bomb, within a few degrees either way; the blast is as strong as
  /// throws a bomb onto that hut's roof at forty-five degrees. The yard
  /// between the huts is empty, so a bomb aimed at their middle comes down
  /// on bare ground; and the crater stands some seventeen metres over the
  /// roofs, so the level-ground range v = √(g·D) throws it ten metres past
  /// them. A projectile launched at θ that comes down h lower over D
  /// needs v² = g·D² / (2·cos²θ·(D·tanθ + h)), which at forty-five degrees
  /// is g·D² / (D + h).
  void _throw() {
    final from = crater + Vector3(0, 1.0, 0);
    final hut = _huts[_random.nextInt(_huts.length)];
    final away = Vector3(hut.roofTop.x - from.x, 0.0, hut.roofTop.z - from.z);
    final reach = away.length;
    final drop = from.y - hut.roofTop.y;
    final speed = reach * math.sqrt(_world.gravityMagnitude / (reach + drop));
    final spread = (_random.nextDouble() - 0.5) * 2.0 * _aim;
    final heading = Portable.sinCos(Portable.atan2(away.z, away.x) + spread);
    final up = Portable.sinCos(
      math.pi / 4 + (_random.nextDouble() - 0.5) * 2.0 * _aim,
    );
    final along = Vector3(up.cos * heading.cos, up.sin, up.cos * heading.sin);
    final body = _world.addBody(position: from, mass: _bombMass);
    _world
      ..setShape(body, const NativeShape.sphere(_bombRadius))
      ..setMaterial(body, NativeMaterial.stone())
      ..setTemperature(body, 1300.0);
    bombs.add(_drawn(body));
    // The share of the blast's momentum a ball of the bomb's radius takes
    // from [_pocket] off, its solid angle over the sphere's; and the
    // momentum of a charge of energy E, √(2·0.71·E·m) with m = E / 4.184 MJ,
    // TNT's Gurney share and its equivalent.
    const r = _bombRadius / _pocket;
    final share = 0.5 * (1.0 - math.sqrt(1.0 - r * r));
    final momentum = _bombMass * speed / share;
    final energy = momentum / math.sqrt(2.0 * 0.7115 / 4.184e6);
    _world.explode(
      from - along * _pocket,
      NativeExplosion(energy: energy, mass: energy / 4.184e6),
    );
  }

  /// [body] drawn as a bomb, in the scene.
  Prop _drawn(NativeBody body) {
    final node = MeshNode(
      _bombMesh,
      covered('bomb', _basalt, repeat: Vector2(2.0, 1.0)),
      name: 'bomb',
    );
    _scene.add(node);
    return Prop(body, node);
  }

  /// The clock, the dice, the vent and the bombs, flying and lodged, by
  /// their bodies.
  Map<String, Object?> save() => <String, Object?>{
    'clock': _clock,
    'next': _next,
    'sinceBomb': _sinceBomb,
    'pouring': _pouring,
    'random': _random.state,
    'bombs': <int>[for (final b in bombs) b.body.raw],
    'lodged': <int>[for (final b in _lodged) b.raw],
  };

  /// Back to what [save] wrote, the world already restored under it: the
  /// bombs drawn again for the bodies it names. The vent's flow came back
  /// with the world.
  void restore(Object? saved) {
    if (saved case {
      'clock': final num clock,
      'next': final num next,
      'sinceBomb': final num sinceBomb,
      'pouring': final bool pouring,
      'random': final num random,
      'bombs': final List<Object?> flying,
      'lodged': final List<Object?> lodged,
    }) {
      _clock = clock.toDouble();
      _next = next.toDouble();
      _sinceBomb = sinceBomb.toDouble();
      _pouring = pouring;
      _random.state = random.toInt();
      for (final b in bombs) {
        _scene.remove(b.node);
      }
      bombs
        ..clear()
        ..addAll(<Prop>[
          for (final raw in flying.whereType<num>())
            _drawn(NativeBody(raw.toInt())),
        ]);
      _lodged
        ..clear()
        ..addAll(<NativeBody>[
          for (final raw in lodged.whereType<num>()) NativeBody(raw.toInt()),
        ]);
    }
  }

  /// A bomb's mass, kg, and radius, m; and how far under it the gas that
  /// throws it is, m.
  static const double _bombMass = 400.0, _bombRadius = 0.35, _pocket = 0.5;

  /// How far off its line the breach lets a bomb go, either way, rad: three
  /// degrees, the "few degrees" above.
  static const double _aim = 3.0 * math.pi / 180.0;
}

/// A turn of [angle] about the unit [axis], with `Portable`'s sine and
/// cosine: `Quaternion.axisAngle` asks `dart:math`, whose last bits differ
/// between the VM and a browser.
Quaternion _turn(Vector3 axis, double angle) {
  final (:sin, :cos) = Portable.sinCos(angle * 0.5);
  return Quaternion(axis.x * sin, axis.y * sin, axis.z * sin, cos);
}
