/// The physics core's fires, drawn: the tongues of each flame, the smoke
/// over it, the embers it throws, the light it gives, and the bodies it
/// chars.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeBody, NativeWorld, nativeFireFloats;
import 'package:vector_math/vector_math.dart';

/// How much of the fire is drawn at most, and how fine its smoke is baked.
final class FireDetail {
  const FireDetail({
    required this.flames,
    required this.embers,
    required this.smoke,
    required this.smokeCell,
  });

  /// A desktop or a console.
  static const FireDetail full = FireDetail(
    flames: 1500,
    embers: 600,
    smoke: 400,
    smokeCell: 40,
  );

  /// A phone, or a browser on one.
  static const FireDetail light = FireDetail(
    flames: 500,
    embers: 150,
    smoke: 150,
    smokeCell: 24,
  );

  /// The most tongues of flame, embers and puffs of smoke alive at once.
  final int flames, embers, smoke;

  /// Pixels a side of a frame of the smoke's six-way sheet, baked as the
  /// view is made.
  final int smokeCell;
}

/// The air a particle is in: it takes on the air's velocity at [rate] per
/// second, the air being the wind plus the hot gas's rise at the height the
/// particle has reached.
final class _CarriedBy extends ParticleAffector {
  _CarriedBy(this.air, {required this.rise, required this.rate});

  final Vector3 air;
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

/// A body whose look burns with it.
final class _Watched {
  _Watched(this.body, this.look, this.fuel, this.fresh, this.charred);

  final NativeBody body;
  final MeshNode look;
  final double fuel;
  final Vector4 fresh, charred;
}

/// Every fire of [world] drawn into [scene] through [renderer].
///
/// The core says where each fire is, the watts it gives off as hot gas and
/// how far its flame reaches along which axis — the flame it heats other
/// bodies with. The rest follows from what is measured of real fires:
///
/// * **Tongues** rise through the flame as fast as McCaffrey measured the
///   gas in a continuous flame rise, 6.84·√z m/s, which averages 4.56·√L
///   over a flame L long: each lives as long as rising its flame takes. A
///   fire puffs at about 1.5/√D Hz (Pagni), D its base, so they come in
///   breaths.
/// * **Smoke** leaves the flame's tip and rises at the plume's speed,
///   McCaffrey's 1.11·Q^(1/3)·z^(−1/3), slowing as it spreads; it is lit by
///   the scene's lights, the firelight among them, through a six-way sheet.
/// * **Embers** are thrown up and lag the plume.
/// * **Firelight**: a point light over the fires, a few watts of light in
///   every hundred of heat, flickering.
///
/// Everything that flies is carried by the wind where the fires are, and a
/// wind leans the flame as far as the core's flame leans.
final class FireView {
  FireView({
    required this._world,
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    this.detail = FireDetail.full,
    this.baseWidth = 0.4,
  }) : _flames = ParticleSystem(capacity: detail.flames, seed: 5),
       _embers = ParticleSystem(capacity: detail.embers, seed: 6),
       _smoke = ParticleSystem(capacity: detail.smoke, seed: 7) {
    light = LightNode(
      type: LightType.point,
      color: Vector3(1.0, 0.55, 0.22),
      intensity: 0.0,
      range: 18.0,
      castsShadow: false,
      name: 'firelight',
    );
    scene.add(light);
    final smoke = bakeSixWay(
      density: smokePuff(seed: 3),
      frames: 16,
      columns: 4,
      cell: detail.smokeCell,
    );
    TextureHandle upload(Uint8List bytes) => device.createTextureFromPixels(
      width: smoke.width,
      height: smoke.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(bytes),
    )!;
    final tongues = device.createTextureFromPixels(
      width: _tongueCell * _tongueFrames,
      height: _tongueCell,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _tongueAtlas(),
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
          texture: tongues,
          flipbook: Flipbook(columns: _tongueFrames, rows: 1, loops: 2),
          softness: 0.3,
        ),
      )
      ..addContributor(ParticleContributor(_embers));
  }

  final NativeWorld _world;

  /// How much is drawn at most.
  final FireDetail detail;

  /// How wide, m, what typically burns here is: a log's thickness, a
  /// crate's side. It sizes the tongues and sets how fast a fire puffs.
  final double baseWidth;

  /// The firelight.
  late final LightNode light;

  final ParticleSystem _flames, _embers, _smoke;
  final List<_Watched> _watched = <_Watched>[];
  final Set<int> _alight = <int>{};
  final math.Random _flicker = math.Random(11);
  double _clock = 0.0;

  /// The wind where the fires are.
  final Vector3 _air = Vector3.zero();

  /// The gas in a flame rises as fast all the way up; the plume over the
  /// fires slows as it spreads, from the lowest fire's height.
  double _flameRise = 0.0, _kw = 0.0, _base = 0.0;
  double _plume(double height) =>
      1.11 *
      math.pow(_kw, 1 / 3) *
      math.pow(math.max(height - _base, 0.5), -1 / 3);
  late final _CarriedBy _flameAir = _CarriedBy(
    _air,
    rise: (_) => _flameRise,
    rate: 6.0,
  );
  late final _CarriedBy _smokeAir = _CarriedBy(_air, rise: _plume, rate: 2.0);
  late final _CarriedBy _emberAir = _CarriedBy(_air, rise: _plume, rate: 0.8);

  /// The heat going up from every fire together, W, as of the last
  /// [update].
  double watts = 0.0;

  /// How many fires there were.
  int burning = 0;

  /// How many tongues, embers and puffs are alive.
  int get tongues => _flames.aliveCount;
  int get embers => _embers.aliveCount;
  int get puffs => _smoke.aliveCount;

  /// [look] draws [body], and chars with it: from [fresh] towards [charred]
  /// as its fuel goes, glowing while it burns.
  void watch(
    NativeBody body,
    MeshNode look, {
    Vector4? fresh,
    Vector4? charred,
  }) => _watched.add(
    _Watched(
      body,
      look,
      _world.fuelOf(body),
      fresh ?? look.material.baseColor.clone(),
      charred ?? Vector4(0.06, 0.05, 0.045, 1.0),
    ),
  );

  /// Stops charring [body]'s look.
  void forget(NativeBody body) => _watched.removeWhere((w) => w.body == body);

  /// The fires drawn as the world has them, [dt] seconds on.
  void update(double dt) {
    _clock += dt;
    final (:fires, :bodies) = _world.readFires();
    const n = nativeFireFloats;
    burning = bodies.length;
    watts = <double>[
      for (var k = 0; k < burning; k++) fires[n * k + 3],
    ].fold(0.0, (sum, q) => sum + q);
    _kw = watts / 1000.0;
    if (burning > 0) {
      _base = <double>[
        for (var k = 0; k < burning; k++) fires[n * k + 1],
      ].reduce(math.min);
      _air.setFrom(_world.windAt(Vector3(fires[0], fires[1], fires[2])));
    }
    final now = <int>{};
    var reach = 0.0;
    final centre = Vector3.zero();
    for (var k = 0; k < burning; k++) {
      final at = Vector3(fires[n * k], fires[n * k + 1], fires[n * k + 2]);
      // A compound's parts each burn: one key a part.
      final key = bodies[k].raw * 64 + k;
      now.add(key);
      centre.add(at);
      reach = math.max(reach, fires[n * k + 4]);
      _burn(
        key,
        at,
        fires[n * k + 3],
        fires[n * k + 4],
        Vector3(fires[n * k + 5], fires[n * k + 6], fires[n * k + 7]),
      );
    }
    // A fire gone out sends nothing more.
    for (final key in _alight.difference(now)) {
      _flames.stopEmitting(key);
      _smoke.stopEmitting(key);
      _embers.stopEmitting(key);
    }
    _alight
      ..clear()
      ..addAll(now);
    _char();
    final flicker = 0.8 + 0.4 * _flicker.nextDouble();
    light.intensity = _kw <= 0 ? 0.0 : 0.04 * _kw * flicker;
    if (burning > 0) {
      centre.scale(1.0 / burning);
      light.setPosition(centre.x, centre.y + 0.3 * reach, centre.z);
    }
    _flames.advance(dt);
    _embers.advance(dt);
    _smoke.advance(dt);
  }

  void _char() {
    for (final w in _watched) {
      final burnt = w.fuel > 0 ? 1.0 - _world.fuelOf(w.body) / w.fuel : 0.0;
      // Black long before the fuel is gone: char is a skin.
      final material = w.look.material;
      material.baseColor.setFrom(
        w.fresh + (w.charred - w.fresh) * math.min(1.0, burnt * 4.0),
      );
      final glow = _world.isBurning(w.body)
          ? 0.5 + 0.3 * _flicker.nextDouble()
          : 0.0;
      material.emissive.setValues(glow, 0.3 * glow, 0.06 * glow);
    }
  }

  void _burn(int key, Vector3 at, double q, double reach, Vector3 axis) {
    final kw = q / 1000.0;
    final length = math.max(reach, 0.5 * baseWidth);
    final rise = 4.56 * math.sqrt(length);
    _flameRise = rise;
    final puff =
        1.0 + 0.6 * math.sin(2 * math.pi * 1.5 / math.sqrt(baseWidth) * _clock);
    _flames.emit(
      key,
      _flameEffect(length / rise),
      at,
      perSecond: (90.0 + 0.6 * kw) * puff,
      direction: axis,
    );
    final tip = at + axis * (1.2 * reach);
    _smoke.emit(
      key,
      _smokeEffect(_plume(tip.y)),
      tip,
      perSecond: 10.0 + kw / 10.0,
      direction: Vector3(0.0, 1.0, 0.0),
    );
    _embers.emit(
      key,
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
    // As wide as what burns, and a little more.
    size: Range(2.0 * baseWidth, 3.3 * baseWidth),
    color: Vector4(1.0, 1.0, 1.0, 1.0),
    affectors: <ParticleAffector>[
      _flameAir,
      // From yellow-white at the base, through orange, to the dull red of
      // soot cooling as it leaves the flame — brighter than sunlit ground,
      // as a flame in daylight is.
      ParticleColorGradient(
        ParticleGradient(<GradientKey>[
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
    emitter: ConeEmitter(speed: Range(0.8 * rise, rise), halfAngleDegrees: 10),
    lifetime: const Range(5.0, 7.0),
    size: Range(3.0 * baseWidth, 4.0 * baseWidth),
    color: Vector4(0.5, 0.49, 0.48, 0.35),
    affectors: <ParticleAffector>[
      _smokeAir,
      const ParticleTurbulence(strength: 0.4, scale: 1.5),
      // A plume widens as it rises.
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

  static const int _tongueCell = 64, _tongueFrames = 8;

  /// Eight frames of a tongue of flame side by side: bright at its root,
  /// thinning to a tip that sways a little further each frame. The stage
  /// scales a texel's colour by its alpha too, so the brightness is in the
  /// colour and its square root in the alpha.
  static ByteData _tongueAtlas() {
    const width = _tongueCell * _tongueFrames;
    final bytes = Uint8List(width * _tongueCell * 4);
    for (var f = 0; f < _tongueFrames; f++) {
      final phase = 2 * math.pi * f / _tongueFrames;
      for (var y = 0; y < _tongueCell; y++) {
        // From the root (0) to the tip (1), the tip in the top row.
        final v = 1.0 - (y + 0.5) / _tongueCell;
        final half =
            0.8 *
            math.pow(1.0 - v, 0.7) *
            (0.85 + 0.15 * math.sin(phase + 5 * v));
        final sway = 0.15 * v * math.sin(phase + 4.0 * v);
        for (var x = 0; x < _tongueCell; x++) {
          final u = (x + 0.5) / _tongueCell * 2.0 - 1.0;
          final edge = half <= 0
              ? 0.0
              : (1.0 - (u - sway).abs() / half).clamp(0.0, 1.0);
          final i =
              (math.sqrt(edge) *
                      (v / 0.06).clamp(0.0, 1.0) *
                      math.pow(1.0 - v, 0.3))
                  .clamp(0.0, 1.0);
          final o = (y * width + f * _tongueCell + x) * 4;
          bytes
            ..[o] = (i * 255).round()
            ..[o + 1] = (i * 255).round()
            ..[o + 2] = (i * 255).round()
            ..[o + 3] = (math.sqrt(i) * 255).round();
        }
      }
    }
    return bytes.buffer.asByteData();
  }
}
