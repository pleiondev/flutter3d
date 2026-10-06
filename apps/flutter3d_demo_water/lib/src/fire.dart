/// A bonfire on the pond's bank: logs of the physics core's wood, which
/// catch, burn down and spread fire to each other by the core's heat, and
/// what is drawn of each fire, read off the watts the core says it gives.
///
/// The core says where each fire is and how much heat goes up from it; the
/// rest follows from what is measured of real fires. The flame stands as
/// tall as Heskestad's correlation gives, the gas in it rises as McCaffrey
/// measured, it pulses at the frequency a pool fire of its width puffs at,
/// and the smoke above it rises at the plume's speed. Everything that flies
/// is carried by the air: the wind the core blows, plus its own buoyancy, so
/// a wind leans the flame as far as it is strong against the flame's rise.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
// The six-way smoke baker is plain Dart: the density field and the bake.
// ignore: implementation_imports
import 'package:flutter3d_build/src/six_way_bake.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeBody, NativeMaterial, NativeShape, NativeWorld;
import 'package:vector_math/vector_math.dart';

/// Where the bonfire stands: on the sand past the pond's east shore.
const double fireX = 23.5, fireZ = 24.0;

/// The ground under it, m.
const double fireGround = 0.5;

/// A log's size, m: long, and as thick as a forearm is long.
Vector3 get _logSize => Vector3(1.4, 0.3, 0.3);

/// How wide the fire's base is, m: what Heskestad's correlation calls D.
const double _base = 0.6;

/// One log of the pile and what it looked like before it burnt.
final class _Log {
  _Log(this.body, this.node, this.fuel);

  final NativeBody body;
  final MeshNode node;

  /// The fuel it started with, kg.
  final double fuel;
}

/// The air a particle is in: it takes on the air's velocity at [rate] per
/// second, the air being the wind plus the hot gas's rise at the height the
/// particle has reached.
final class _CarriedBy extends ParticleAffector {
  _CarriedBy(this.air, {required this.rise, required this.rate});

  /// The wind, shared and moved as the wind changes.
  final Vector3 air;

  /// How fast the hot gas rises through still air at a height, m/s.
  final double Function(double height) rise;

  final double rate;

  @override
  void apply(Particle particle, double dt) {
    final k = math.min(1.0, rate * dt);
    particle.velocity
      ..x += (air.x - particle.velocity.x) * k
      ..y += (air.y + rise(particle.position.y) - particle.velocity.y) * k
      ..z += (air.z - particle.velocity.z) * k;
  }
}

/// The bonfire, its fires and what is drawn of them.
final class Bonfire {
  Bonfire(this._world, GraphicsDevice device, this._scene, Renderer renderer) {
    final mesh = DeviceMesh.upload(device, CuboidShape(size: _logSize).build());
    // Three layers, crosswise, as a fire is laid: two logs along x, two
    // along z on them, two along x on top.
    final half = _logSize * 0.5;
    for (var layer = 0; layer < 3; layer++) {
      final alongX = layer.isEven;
      for (final side in <double>[-0.4, 0.4]) {
        final y = fireGround + half.y + layer * _logSize.y + 0.01;
        final body = _world.addBody(
          position: alongX
              ? Vector3(fireX, y, fireZ + side)
              : Vector3(fireX + side, y, fireZ),
          // Seasoned wood, 450 kg/m³.
          mass: 450.0 * _logSize.x * _logSize.y * _logSize.z,
        );
        _world
          ..setShape(body, NativeShape.box(half))
          ..setMaterial(body, NativeMaterial.wood());
        if (!alongX) {
          _world.setOrientation(
            body,
            Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
          );
        }
        final node = MeshNode(
          mesh,
          Material(name: 'log', baseColor: _wood, roughness: 0.9),
          name: 'log',
        );
        _scene.add(node);
        _logs.add(_Log(body, node, _world.fuelOf(body)));
      }
    }

    // The glow over it, as bright as the fire is big.
    _light = LightNode(
      type: LightType.point,
      color: Vector3(1.0, 0.55, 0.22),
      intensity: 0.0,
      range: 18.0,
      castsShadow: false,
      name: 'firelight',
    )..setPosition(fireX, fireGround + 1.0, fireZ);
    _scene.add(_light);

    final smoke = bakeSixWay(
      density: smokePuff(seed: 3),
      frames: 16,
      columns: 4,
      cell: 40,
    );
    TextureHandle upload(Uint8List bytes) => device.createTextureFromPixels(
      width: smoke.width,
      height: smoke.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(bytes),
    )!;
    final flameSheet = device.createTextureFromPixels(
      width: _flameCell * _flameFrames,
      height: _flameCell,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _flameAtlas(),
    )!;
    // The smoke first, over what is behind it; the flame and the embers
    // after, added on top: a flame shines through the smoke it makes.
    renderer
      ..addContributor(
        ParticleContributor(
          _smoke,
          sixWay: SixWayMaterial(
            positive: upload(smoke.positive),
            negative: upload(smoke.negative),
          ),
          flipbook: Flipbook(columns: 4, rows: 4),
          softness: 0.6,
        ),
      )
      ..addContributor(
        ParticleContributor(
          _flames,
          texture: flameSheet,
          flipbook: Flipbook(columns: _flameFrames, rows: 1, loops: 2),
          softness: 0.3,
        ),
      )
      ..addContributor(ParticleContributor(_embers));
  }

  final NativeWorld _world;
  final Scene _scene;
  final List<_Log> _logs = <_Log>[];
  late final LightNode _light;
  final math.Random _flicker = math.Random(11);
  double _clock = 0.0;

  final ParticleSystem _flames = ParticleSystem(capacity: 1500, seed: 5);
  final ParticleSystem _embers = ParticleSystem(capacity: 600, seed: 6);
  final ParticleSystem _smoke = ParticleSystem(capacity: 400, seed: 7);

  /// The wind every particle is carried by.
  final Vector3 _air = Vector3.zero();

  /// The flame's gas rises as fast all the way up; the plume above it
  /// slows as it spreads, McCaffrey's u = 1.11·Q^(1/3)·z^(−1/3), Q in kW
  /// and z over the fire's base. Smoke follows it closely, an ember lags.
  double _flameRise = 0.0, _kw = 0.0;
  double _plume(double height) =>
      1.11 *
      math.pow(_kw, 1 / 3) *
      math.pow(math.max(height - fireGround, 0.5), -1 / 3);
  late final _CarriedBy _flameAir = _CarriedBy(
    _air,
    rise: (_) => _flameRise,
    rate: 6.0,
  );
  late final _CarriedBy _smokeAir = _CarriedBy(_air, rise: _plume, rate: 2.0);
  late final _CarriedBy _emberAir = _CarriedBy(_air, rise: _plume, rate: 0.8);

  static Vector4 get _wood => Vector4(0.42, 0.28, 0.16, 1.0);
  static Vector4 get _char => Vector4(0.06, 0.05, 0.045, 1.0);

  /// The heat going up from the whole fire, W.
  double watts = 0.0;

  /// How many logs are burning.
  int burning = 0;

  /// Lights the fire: a match held to the bottom log until it catches —
  /// the log's surface brought past wood's ignition temperature.
  void light() {
    final log = _logs.first.body;
    _world.setTemperature(log, 650.0);
  }

  /// A bucket of water over every log that burns.
  void douse() {
    for (final log in _logs) {
      if (_world.isBurning(log.body)) _world.addWater(log.body, 8.0);
    }
  }

  /// The fire drawn as the core has it after a step of [dt] with [wind].
  void step(double dt, Vector3 wind) {
    _clock += dt;
    _air.setFrom(wind);
    final (:fires, :bodies) = _world.readFires();
    burning = bodies.length;
    // The plume over the pile is the whole fire's: its heat summed.
    watts = <double>[
      for (var k = 0; k < bodies.length; k++) fires[4 * k + 3],
    ].fold(0.0, (sum, q) => sum + q);
    _kw = watts / 1000.0;
    for (var k = 0; k < bodies.length; k++) {
      _burn(
        bodies[k],
        Vector3(fires[4 * k], fires[4 * k + 1], fires[4 * k + 2]),
        fires[4 * k + 3],
      );
    }
    // A fire not in the list has gone out: nothing more from it.
    for (final log in _logs) {
      if (!bodies.contains(log.body)) {
        _flames.emit(
          log.body.raw,
          _flameEffect(1.0),
          Vector3.zero(),
          perSecond: 0,
        );
        _smoke.emit(
          log.body.raw,
          _smokeEffect(1.0),
          Vector3.zero(),
          perSecond: 0,
        );
        _embers.emit(log.body.raw, _emberEffect, Vector3.zero(), perSecond: 0);
      }
      // Charred as far as it has burnt; glowing where it burns.
      final burnt = log.fuel > 0
          ? 1.0 - _world.fuelOf(log.body) / log.fuel
          : 0.0;
      final material = log.node.material;
      material.baseColor.setFrom(
        _wood + (_char - _wood) * math.min(1.0, burnt * 4.0),
      );
      final glow = _world.isBurning(log.body)
          ? 0.5 + 0.3 * _flicker.nextDouble()
          : 0.0;
      material.emissive.setValues(1.0 * glow, 0.3 * glow, 0.06 * glow);
      final p = _world.positionOf(log.body);
      log.node
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(log.body));
    }
    // The firelight: a few watts of light in every hundred of heat, and
    // flickering as the flame does.
    final kw = watts / 1000.0;
    _light
      ..intensity = kw <= 0
          ? 0.0
          : 0.04 * kw * (0.8 + 0.4 * _flicker.nextDouble())
      ..setPosition(fireX, fireGround + 0.5 + 0.3 * _flameLength(kw), fireZ);
    _flames.advance(dt);
    _embers.advance(dt);
    _smoke.advance(dt);
  }

  /// Heskestad's flame length, m, for [kw] kilowatts over the fire's base:
  /// L = 0.235·Q^(2/5) − 1.02·D, and never shorter than nothing.
  static double _flameLength(double kw) =>
      kw <= 0 ? 0.0 : math.max(0.0, 0.235 * math.pow(kw, 0.4) - 1.02 * _base);

  void _burn(NativeBody body, Vector3 at, double q) {
    final kw = q / 1000.0;
    final length = math.max(_flameLength(kw), 0.3);
    // McCaffrey's continuous flame: the gas rises at 6.84·√z m/s, which
    // averages 4.56·√L over the flame — so a tongue lives as long as it
    // takes to rise the flame's length.
    final rise = 4.56 * math.sqrt(length);
    _flameRise = rise;
    // The tongues rise off the log's upper face.
    final root = at + Vector3(0.0, 0.5 * _logSize.y, 0.0);
    // A fire puffs at about 1.5/√D Hz (Pagni): the tongues come in breaths.
    final puff =
        1.0 + 0.6 * math.sin(2 * math.pi * 1.5 / math.sqrt(_base) * _clock);
    _flames.emit(
      body.raw,
      _flameEffect(length / rise),
      root,
      perSecond: (90.0 + 0.6 * kw) * puff,
      direction: Vector3(0.0, 1.0, 0.0),
    );
    // Above the flame, the plume: McCaffrey's u = 1.11·Q^(1/3)·z^(−1/3).
    final tip = at + Vector3(0.0, 1.2 * length, 0.0);
    _smoke.emit(
      body.raw,
      _smokeEffect(_plume(tip.y)),
      tip,
      perSecond: 10.0 + kw / 10.0,
      direction: Vector3(0.0, 1.0, 0.0),
    );
    _embers.emit(
      body.raw,
      _emberEffect,
      at,
      perSecond: kw / 25.0,
      direction: Vector3(0.0, 1.0, 0.0),
    );
  }

  ParticleEffect _flameEffect(double life) => ParticleEffect(
    count: 1,
    emitter: ConeEmitter(
      speed: Range(0.5 * _flameRise, _flameRise),
      halfAngleDegrees: 12.0,
    ),
    lifetime: Range(0.7 * life, 1.2 * life),
    // As wide as the fire's base, and a little more.
    size: const Range(0.6, 1.0),
    color: Vector4(1.0, 1.0, 1.0, 1.0),
    affectors: <ParticleAffector>[
      _flameAir,
      // From yellow-white at the base, through orange, to the dull red
      // of soot cooling as it leaves the flame.
      ParticleColorGradient(
        ParticleGradient(<GradientKey>[
          // Brighter than sunlit sand, as a flame is: a fire in daylight
          // is still the brightest thing in the valley.
          GradientKey(0.0, Vector4(2.6, 1.6, 0.5, 1.0)),
          GradientKey(0.35, Vector4(2.4, 0.8, 0.12, 1.0)),
          GradientKey(1.0, Vector4(0.5, 0.06, 0.01, 0.0)),
        ]),
      ),
      const ParticleSizeOverLife(from: 1.0, to: 0.45),
    ],
  );

  ParticleEffect _smokeEffect(double rise) => ParticleEffect(
    count: 1,
    emitter: ConeEmitter(
      speed: Range(0.8 * rise, rise),
      halfAngleDegrees: 10.0,
    ),
    lifetime: const Range(5.0, 7.0),
    size: const Range(1.2, 1.6),
    color: Vector4(0.5, 0.49, 0.48, 0.35),
    affectors: <ParticleAffector>[
      _smokeAir,
      const ParticleTurbulence(strength: 0.4, scale: 1.5),
      // A plume widens as it rises, its edge spreading at about 0.12 of its
      // height (the core's own plume spread).
      ParticleSizeCurve(ParticleCurve.linear(1.0, 4.0)),
      const ParticleFade(startsAt: 0.4),
    ],
  );

  late final ParticleEffect _emberEffect = ParticleEffect(
    count: 1,
    emitter: const ConeEmitter(speed: Range(2.0, 5.0), halfAngleDegrees: 25.0),
    lifetime: const Range(1.0, 2.5),
    size: const Range(0.02, 0.04),
    color: Vector4(1.0, 0.6, 0.2, 1.0),
    affectors: <ParticleAffector>[
      _emberAir,
      const ParticleTurbulence(strength: 3.0, scale: 0.5),
      ParticleColorOverLife(
        Vector4(1.0, 0.7, 0.25, 1.0),
        Vector4(0.6, 0.1, 0.02, 0.0),
      ),
    ],
  );

  static const int _flameCell = 64, _flameFrames = 8;

  /// Eight frames of a tongue of flame, side by side: bright at its root,
  /// thinning to a tip that sways a little further each frame.
  static ByteData _flameAtlas() {
    final bytes = Uint8List(_flameCell * _flameFrames * _flameCell * 4);
    const width = _flameCell * _flameFrames;
    for (var f = 0; f < _flameFrames; f++) {
      final phase = 2 * math.pi * f / _flameFrames;
      for (var y = 0; y < _flameCell; y++) {
        // v from the root (0) to the tip (1), the tip at the top row.
        final v = 1.0 - (y + 0.5) / _flameCell;
        final half =
            0.8 *
            math.pow(1.0 - v, 0.7) *
            (0.85 + 0.15 * math.sin(phase + 5 * v));
        final sway = 0.15 * v * math.sin(phase + 4.0 * v);
        for (var x = 0; x < _flameCell; x++) {
          final u = (x + 0.5) / _flameCell * 2.0 - 1.0;
          final off = (u - sway).abs();
          final edge = half <= 0 ? 0.0 : (1.0 - off / half).clamp(0.0, 1.0);
          final root = (v / 0.06).clamp(0.0, 1.0);
          final i = math.sqrt(edge) * root * math.pow(1.0 - v, 0.3);
          // The stage scales the colour by the texel's alpha too: brightness
          // in the colour, its square root in the alpha.
          final byte = (i.clamp(0.0, 1.0) * 255).round();
          final cover = (math.sqrt(i.clamp(0.0, 1.0)) * 255).round();
          final o = (y * width + f * _flameCell + x) * 4;
          bytes
            ..[o] = byte
            ..[o + 1] = byte
            ..[o + 2] = byte
            ..[o + 3] = cover;
        }
      }
    }
    return bytes.buffer.asByteData();
  }
}
