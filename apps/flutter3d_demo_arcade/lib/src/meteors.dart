/// The meteors over the yard: stones that come down red-hot where a shadow
/// on the floor has grown under them, burst into fragments that scatter as
/// bodies, and set the litter of the yard alight where they touch it —
/// fires that spread to the wooden crates standing about. All of it the
/// physics core's own: a world of its own with gravity in it, the yard's
/// being a top-down one without, drawn by [Elements] once there is a
/// renderer to draw it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

/// A thing in the yard's sky or on its floor, and what draws it.
final class _Piece {
  _Piece(this.body, this.node);

  final NativeBody body;
  final MeshNode node;

  /// Its body in the elements, once there are any: they keep [node] on it
  /// and char it as it burns.
  TrackedBody? tracked;
}

/// A meteor on its way: where it will land, how long until it does, and the
/// shadow growing there.
final class _Falling {
  _Falling(this.target, this.until, this.shadow);

  final Vector3 target;
  double until;
  final MeshNode shadow;
  _Piece? stone;
}

/// A shower of meteors over a yard [halfWidth] by [halfDepth] metres about
/// its middle, its floor at height nought.
final class MeteorShower {
  MeteorShower({
    required GraphicsDevice device,
    required Scene scene,
    required this.halfWidth,
    required this.halfDepth,
    this.every = 7.0,
  }) : _device = device,
       _scene = scene {
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setShape(floor, NativeShape.box(Vector3(halfWidth, 0.5, halfDepth)))
      ..setMaterial(floor, NativeMaterial.stone());
    _rockMesh = DeviceMesh.upload(
      device,
      const SphereShape(radius: 1.0, segments: 10, rings: 7).build(),
    );
    _discMesh = DeviceMesh.upload(
      device,
      const CylinderShape(
        radiusTop: 1.0,
        radiusBottom: 1.0,
        height: 0.02,
        segments: 24,
      ).build(),
    );
    final crateMesh = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(2 * _crateHalf)).build(),
    );
    // Crates about the yard, out of the ship's way at the start.
    for (final (x, z) in <(double, double)>[
      (-8.0, -4.0),
      (-7.0, 3.0),
      (8.5, -5.5),
      (9.5, 1.5),
      (-1.5, -6.5),
      (2.0, 2.5),
    ]) {
      final body = world.addBody(
        position: Vector3(x, _crateHalf, z),
        mass: 45.0,
      );
      world
        ..setShape(body, NativeShape.box(Vector3.all(_crateHalf)))
        ..setMaterial(body, NativeMaterial.wood());
      final node = MeshNode(
        crateMesh,
        RenderMaterial(
          name: 'crate',
          baseColor: LinearColor.fromSrgb(0.55, 0.40, 0.22, 1.0),
          roughness: 0.85,
        ),
        name: 'crate',
      );
      scene.add(node);
      _crates.add(_Piece(body, node));
    }
  }

  /// Seconds between meteors.
  final double every;

  final double halfWidth, halfDepth;

  /// The world the meteors fall through: the yard's floor, its crates, the
  /// stones, their fragments and the fires they light.
  final NativeWorld world = NativeWorld();

  final GraphicsDevice _device;
  final Scene _scene;
  late final DeviceMesh _rockMesh, _discMesh;
  final List<_Piece> _crates = <_Piece>[];
  final List<_Piece> _rocks = <_Piece>[];
  final List<_Piece> _craters = <_Piece>[];
  final List<_Falling> _falling = <_Falling>[];
  final math.Random _random = math.Random(3);
  double _since = 0.0;
  Elements? _elements;

  static const double _crateHalf = 0.4;

  /// How long a shadow grows on the floor before its meteor lands, s, and
  /// how fast a meteor comes down, m/s.
  static const double warning = 1.8, _speed = 30.0;

  /// The fires drawn, once the renderer they draw through is there; [load]
  /// reads the effects' compiled materials from the bundle. The world is
  /// the shower's, which [step] steps.
  Future<void> drawFires(
    Renderer renderer,
    Future<ByteData> Function(String asset) load,
  ) async {
    final elements = await Elements.adopt(
      world,
      device: _device,
      renderer: renderer,
      scene: _scene,
      load: load,
    );
    for (final p in <_Piece>[..._crates, ..._craters]) {
      p.tracked = elements.track(p.body, look: p.node, chars: p.node);
    }
    for (final r in _rocks) {
      r.tracked = elements.track(r.body, look: r.node);
    }
    _elements = elements;
  }

  /// The places a ship at [at] would be hurt this step: under a meteor as
  /// it lands, or over a fire's base.
  bool hurts(Vector3 at) {
    for (final f in _falling) {
      if (f.until <= 0.0 && _flat(f.target, at) < 1.3) return true;
    }
    for (final fire in world.fires()) {
      if (_flat(fire.at, at) < 0.5 * fire.base) return true;
    }
    return false;
  }

  static double _flat(Vector3 a, Vector3 b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z));

  void step(double dt) {
    _since += dt;
    if (_since >= every) {
      _since = 0.0;
      _announce();
    }
    for (final f in _falling.toList()) {
      final was = f.until;
      f.until -= dt;
      // The shadow grows and darkens as the stone nears.
      final near = (1.0 - f.until / warning).clamp(0.0, 1.0);
      f.shadow.setScale(0.3 + near, 1.0, 0.3 + near);
      if (was > _fallTime && f.until <= _fallTime) _launch(f);
      if (f.until <= 0.0 && was > 0.0) _land(f);
      if (f.until < -0.2) {
        _scene.remove(f.shadow);
        _falling.remove(f);
      }
    }
    world.step(dt);
    // Before there are elements to keep the looks on their bodies, kept
    // here.
    if (_elements == null) {
      for (final p in <_Piece>[..._crates, ..._rocks]) {
        final at = world.positionOf(p.body);
        p.node
          ..setPosition(at.x, at.y, at.z)
          ..setRotation(world.orientationOf(p.body));
      }
    }
    for (final r in _rocks) {
      // Glowing as hot as it is: its surface's luminance, the exitance εσT⁴
      // over π as a Lambertian surface's is, as the lumens a blackbody that
      // hot gives, in its colour.
      final t = world.surfaceTemperatureOf(r.body);
      final nits =
          _stoneEmissivity *
          stefanBoltzmann *
          t *
          t *
          t *
          t *
          Blackbody.efficacy(t) /
          math.pi;
      r.node.material.emissive = (Blackbody.color(
        t,
      )..scale(nits / Photometric.bulbAtOneMeter)).toLinearColor();
    }
    // No water here for the eye to see ripples on.
    _elements?.update(dt, eye: Vector3.zero());
  }

  /// A weathered stone's emissivity: the core's stone's.
  static const double _stoneEmissivity = 0.93;

  /// How long a stone is in the air above the yard, s: launched from high
  /// enough to come down at [_speed] in that time.
  static const double _fallTime = 0.7;

  void _announce() {
    final target = Vector3(
      (_random.nextDouble() * 2.0 - 1.0) * (halfWidth - 1.5),
      0.0,
      (_random.nextDouble() * 2.0 - 1.0) * (halfDepth - 1.5),
    );
    final shadow = MeshNode(
      _discMesh,
      RenderMaterial(
        name: 'shadow',
        baseColor: LinearColor.fromSrgb(0.02, 0.02, 0.03, 1.0),
        roughness: 1.0,
      ),
      name: 'meteor shadow',
    )..setPosition(target.x, 0.012, target.z);
    _scene.add(shadow);
    _falling.add(_Falling(target, warning, shadow));
  }

  /// The stone, high above its shadow and coming down at a slant.
  void _launch(_Falling f) {
    final slant = Vector3(0.35, -1.0, 0.2)..normalize();
    final from = f.target - slant * (_speed * _fallTime) + Vector3(0, 0.4, 0);
    f.stone = _rock(from, slant * _speed, radius: 0.4, mass: 160.0);
  }

  /// Where the stone lands it bursts: fragments fly out across the floor,
  /// and the dry litter it comes down on catches where the hot stone
  /// touches it.
  void _land(_Falling f) {
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 2 + _random.nextDouble();
      final turn = Portable.sinCos(a);
      final out = Vector3(turn.cos, 0.0, turn.sin);
      _rock(
        f.target + out * 0.5 + Vector3(0, 0.4, 0),
        out * (5.0 + _random.nextDouble() * 3.0) + Vector3(0, 3.0, 0),
        radius: 0.16,
        mass: 12.0,
      );
    }
    final crater = world.addBody(
      position: f.target + Vector3(0, 0.03, 0),
      type: NativeBodyType.fixed,
      mass: 30.0,
    );
    world
      ..setShape(crater, const NativeShape.cylinder(0.9, 0.03))
      // Dry litter: straw and splinters, that burn as paper does.
      ..setMaterial(crater, NativeMaterial.paper());
    final node =
        MeshNode(
            _discMesh,
            RenderMaterial(
              name: 'scorch',
              baseColor: LinearColor.fromSrgb(0.30, 0.24, 0.16, 1.0),
              roughness: 1.0,
            ),
            name: 'crater',
          )
          ..setPosition(f.target.x, 0.02, f.target.z)
          ..setScale(0.9, 1.0, 0.9);
    _scene.add(node);
    _craters.add(
      _Piece(crater, node)
        ..tracked = _elements?.track(crater, look: node, chars: node),
    );
    // A yard keeps a dozen fragments; the oldest are swept away.
    while (_rocks.length > 16) {
      final old = _rocks.removeAt(0);
      final tracked = old.tracked;
      if (tracked != null) {
        _elements!.remove(tracked);
      } else {
        world.removeBody(old.body);
      }
      _scene.remove(old.node);
    }
  }

  _Piece _rock(
    Vector3 at,
    Vector3 velocity, {
    required double radius,
    required double mass,
  }) {
    final body = world.addBody(position: at, mass: mass);
    world
      ..setShape(body, NativeShape.sphere(radius))
      ..setMaterial(body, NativeMaterial.stone())
      // The game's stones come down red-hot: where they start, not a
      // law. What they light, they light by touching it.
      ..setTemperature(body, 1400.0)
      ..setVelocity(body, velocity);
    final node = MeshNode(
      _rockMesh,
      RenderMaterial(
        name: 'meteor',
        baseColor: LinearColor.fromSrgb(0.18, 0.15, 0.13, 1.0),
        roughness: 0.9,
      ),
      name: 'meteor',
    )..setScale(radius, radius, radius);
    _scene.add(node);
    final piece = _Piece(body, node)
      ..tracked = _elements?.track(body, look: node);
    _rocks.add(piece);
    return piece;
  }

  void dispose() => world.dispose();
}
