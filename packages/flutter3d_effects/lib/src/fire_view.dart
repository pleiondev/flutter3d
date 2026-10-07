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
/// second, the air being the wind plus the rise of the hot gas of the fire
/// that sent the particle, where the particle now is.
final class _CarriedBy extends ParticleAffector {
  _CarriedBy(this.air, {required this.rise, required this.rate});

  final Vector3 air;
  final double Function(Particle particle) rise;
  final double rate;

  @override
  void apply(Particle particle, double dt) {
    final k = math.min(1.0, rate * dt);
    particle.velocity
      ..x += (air.x - particle.velocity.x) * k
      ..y += (air.y + rise(particle) - particle.velocity.y) * k
      ..z += (air.z - particle.velocity.z) * k;
  }
}

/// A puff of smoke as dark as the soot in it lets it be.
///
/// The soot in a puff stays the same as it spreads, so the light it stops
/// does too: its optical depth falls as the square of its width, and a puff
/// three times as wide as it left the flame is a ninth as deep. Opacity is 1 − e^(−depth), faded in as the puff
/// leaves the flame and out before it is dropped.
final class _Thins extends ParticleAffector {
  const _Thins(this.depth);

  /// The puff's optical depth through its middle as it leaves the flame.
  final double depth;

  @override
  void apply(Particle particle, double dt) {
    final spread = particle.size <= 0
        ? 0.0
        : particle.birthSize / particle.size;
    final life = particle.life;
    particle.color.w =
        (1.0 - math.exp(-depth * spread * spread)) *
        math.min(1.0, life / 0.3) *
        math.min(1.0, (1.0 - life) / 0.3);
  }
}

/// Tongues of flame standing on a fire's base: each from a point of a disc
/// [radius] across the flame's axis, lifted [lift] along it so the root of
/// its sprite is at the fire, and going up the axis at [speed].
final class _Tongues extends ParticleEmitter {
  const _Tongues({
    required this.radius,
    required this.lift,
    required this.speed,
  });

  final double radius, lift;
  final Range speed;

  @override
  void emit(
    Particle particle,
    Vector3 origin,
    Vector3 direction,
    math.Random random,
  ) {
    // Two directions across the axis, from whichever world axis it is
    // furthest from.
    final across = direction.x.abs() < 0.9
        ? Vector3(1.0, 0.0, 0.0)
        : Vector3(0.0, 0.0, 1.0);
    final first = direction.cross(across)..normalize();
    final second = direction.cross(first);
    final r = radius * math.sqrt(random.nextDouble());
    final angle = 2 * math.pi * random.nextDouble();
    particle.position
      ..setFrom(origin)
      ..addScaled(first, r * math.cos(angle))
      ..addScaled(second, r * math.sin(angle))
      ..addScaled(direction, lift);
    // A tongue leans a little off the axis: a few degrees, as the gas
    // eddies at a flame's edge.
    randomDirection(particle.velocity, random);
    particle.velocity
      ..scale(0.12)
      ..add(direction)
      ..normalize()
      ..scale(speed.sample(random));
  }
}

/// What a fire is to what it sent up: its heat, kW, the height of its base,
/// m, and how long its flame is, m.
typedef _Fire = ({double kw, double base, double length});

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
/// * **Size**: a fire stands on a base about Heskestad's D* across, the
///   width his correlations make of its heat, and its flame is 2.9 D* long.
///   Each tongue is as wide as what burns here, [baseWidth], at most; a fire
///   wider than that is more tongues side by side, not fatter ones.
/// * **Tongues** rise through the flame as fast as McCaffrey measured the
///   gas in a continuous flame rise, 6.84·√z m/s, which averages 4.56·√L
///   over a flame L long: each lives as long as rising its flame takes. A
///   fire puffs at about 1.5/√D Hz (Pagni), D its base, so they come in
///   breaths. They are yellow at the root and the core, where the soot in
///   them is hottest, orange in the body and dull red at the tips, and as
///   many as cover the flame about twice over, so the overlap of their
///   light does not wash the flame out to white.
/// * **Smoke** leaves the flame's tip and rises at the speed of that fire's
///   own plume, McCaffrey's 1.11·Q^(1/3)·z^(−1/3), slower off its axis than
///   on it. As much is made as the soot a flaming wood fire gives off, about
///   1.5% of the wood it burns, and soot stops light over 8.7 m² a gram: it
///   is dark grey, and thins as it spreads. It is lit by the scene's lights,
///   the firelight among them, through a six-way sheet.
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
    //
    // Both are soft against the scene over a distance of the size of what
    // they are, not more: a torch's flame stands a hand from the wall it is
    // fixed to, and faded over 0.3 m it was all but gone against it.
    renderer
      ..addContributor(
        ParticleContributor(
          _smoke,
          sixWay: SixWayMaterial(
            positive: upload(smoke.positive),
            negative: upload(smoke.negative),
          ),
          flipbook: Flipbook(columns: 4, rows: 4),
          softness: (2.0 * baseWidth).clamp(0.1, 0.6),
        ),
      )
      ..addContributor(
        ParticleContributor(
          _flames,
          texture: tongues,
          flipbook: Flipbook(columns: _tongueFrames, rows: 1, loops: 2),
          softness: 0.15 * baseWidth,
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

  /// Every fire as of the last [update], by the key its particles carry.
  final Map<Object, _Fire> _fires = <Object, _Fire>{};

  /// How fast the gas in the flame [particle] is in rises: McCaffrey's
  /// 6.84·√z m/s at z over the fire's base, faster up the flame. Nought once
  /// its fire is out.
  double _flameRise(Particle particle) {
    final fire = _fires[particle.source];
    if (fire == null) return 0.0;
    final z = (particle.position.y - fire.base).clamp(
      0.05 * fire.length,
      fire.length,
    );
    return 6.84 * math.sqrt(z);
  }

  /// How fast the plume [particle] is in rises: McCaffrey's centreline
  /// 1.11·Q^(1/3)·z^(−1/3) m/s, Q in kW, from the heat of the fire that sent
  /// it alone, and from no lower than where his plume begins, 0.2·Q^(2/5)
  /// over the base. Off the axis the plume is slower, as the Gaussian across
  /// it falls; how far off a particle is, is its seed. Nought once its fire
  /// is out: the smoke drifts on in the wind.
  double _plumeRise(Particle particle) {
    final fire = _fires[particle.source];
    if (fire == null) return 0.0;
    final off = particle.seed;
    return _plumeAt(fire.kw, particle.position.y - fire.base) *
        math.exp(-1.4 * off * off);
  }

  late final _CarriedBy _flameAir = _CarriedBy(
    _air,
    rise: _flameRise,
    rate: 6.0,
  );
  late final _CarriedBy _smokeAir = _CarriedBy(
    _air,
    rise: _plumeRise,
    rate: 2.0,
  );
  late final _CarriedBy _emberAir = _CarriedBy(
    _air,
    rise: _plumeRise,
    rate: 0.8,
  );

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
    if (burning > 0) {
      _air.setFrom(_world.windAt(Vector3(fires[0], fires[1], fires[2])));
    }
    // A compound's parts each burn: one key a part, numbered within its
    // body, so a fire keeps its key when another one goes out.
    final parts = <int, int>{};
    final keys = <int>[
      for (final body in bodies)
        body.raw * 64 + (parts[body.raw] = (parts[body.raw] ?? -1) + 1),
    ];
    _fires
      ..clear()
      ..addAll(<Object, _Fire>{
        for (var k = 0; k < burning; k++)
          keys[k]: (
            kw: fires[n * k + 3] / 1000.0,
            base: fires[n * k + 1],
            length: _shape(fires[n * k + 3] / 1000.0, fires[n * k + 4]).length,
          ),
      });
    // As many puffs as the smoke needs, or fewer and larger ones carrying
    // the same soot where there would be more than the view can hold.
    final wanted = <double>[
      for (var k = 0; k < burning; k++)
        _puffsPerSecond(
              fires[n * k + 3] / 1000.0,
              _shape(fires[n * k + 3] / 1000.0, fires[n * k + 4]).spread,
            ) *
            _puffLife,
    ].fold(0.0, (sum, alive) => sum + alive);
    final coarser = math.max(1.0, wanted / (0.7 * detail.smoke));
    final now = keys.toSet();
    var reach = 0.0;
    final centre = Vector3.zero();
    for (var k = 0; k < burning; k++) {
      final at = Vector3(fires[n * k], fires[n * k + 1], fires[n * k + 2]);
      centre.add(at);
      reach = math.max(reach, fires[n * k + 4]);
      _burn(
        keys[k],
        at,
        fires[n * k + 3],
        fires[n * k + 4],
        Vector3(fires[n * k + 5], fires[n * k + 6], fires[n * k + 7]),
        coarser,
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
    // One light stands for every fire, from their middle: as bright as the
    // heat up to a burning crate's hundred kilowatts, and past that as its
    // square root and no brighter than twice a crate. Many fires apart are
    // not one fire as bright as their sum at one point, and a village alight
    // lit as one turned every wall in it orange.
    final kw = watts / 1000.0;
    final glow = kw <= 100.0 ? 0.04 * kw : 4.0 * math.sqrt(kw / 100.0);
    light.intensity = watts <= 0 ? 0.0 : math.min(glow, 8.0) * flicker;
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
      // Glowing as much of it as the flame has spread over.
      final share = math.min(
        1.0,
        _across(_world.heatReleaseOf(w.body) / 1000.0) / baseWidth,
      );
      final glow = _world.isBurning(w.body)
          ? (0.5 + 0.3 * _flicker.nextDouble()) * share * share
          : 0.0;
      material.emissive.setValues(glow, 0.3 * glow, 0.06 * glow);
    }
  }

  /// A fire's own width, m, from its heat [kw]: Heskestad's characteristic
  /// diameter D* = (Q / (ρ c_p Tₐ √g))^(2/5), about the width of the base
  /// a fire of that size burns on — a few centimetres for a flame just
  /// caught, half a metre for a crate alight all over.
  static double _across(double kw) =>
      kw <= 0 ? 0.0 : math.pow(kw / 1100.0, 0.4).toDouble();

  /// A fire of [kw] whose flame the core has [reach] m long, as drawn: the
  /// width of one tongue, never wider than what burns here; the width of
  /// the base the tongues stand on, D*, wider when the fire is; and the
  /// flame's length, Heskestad's 2.9 D* over that base, never longer than
  /// the core's. A fire just caught is a small flame, and grows with the
  /// patch it burns on.
  ({double width, double spread, double length}) _shape(
    double kw,
    double reach,
  ) {
    final across = _across(kw);
    final width = across.clamp(0.02, baseWidth);
    final spread = across.clamp(width, 3.0 * baseWidth);
    return (
      width: width,
      spread: spread,
      length: math.max(
        math.min(reach, 2.9 * spread + 0.5 * baseWidth),
        1.5 * width,
      ),
    );
  }

  /// McCaffrey's plume centreline velocity, m/s, z m over a fire of [kw],
  /// from no lower than where his plume begins, 0.2·Q^(2/5): below that, in
  /// the flame's intermittent top, the gas rises as fast as it does there.
  static double _plumeAt(double kw, double z) =>
      1.11 *
      math.pow(kw, 1 / 3) *
      math.pow(math.max(z, math.max(0.2 * math.pow(kw, 0.4), 0.05)), -1 / 3);

  /// The light a flaming wood fire's smoke stops, m² a second for every kW:
  /// soot is about 1.5% of the wood burnt (Tewarson), wood gives 12.4 kJ a
  /// gram as it burns, and a gram of soot stops light over 8.7 m²
  /// (Mulholland).
  static const double _sootArea = 0.015 / 12.4 * 8.7;

  /// A puff's optical depth as it leaves the flame, how much of its square
  /// its sheet covers, and how long it lives on average, s.
  static const double _puffDepth = 0.6, _puffFill = 0.5, _puffLife = 6.0;

  /// How many puffs a second carry the soot of a fire of [kw] on a base
  /// [spread] across, each born as wide as the base.
  static double _puffsPerSecond(double kw, double spread) =>
      _sootArea * kw / (_puffDepth * _puffFill * math.pow(1.2 * spread, 2));

  void _burn(
    int key,
    Vector3 at,
    double q,
    double reach,
    Vector3 axis,
    double coarser,
  ) {
    final kw = q / 1000.0;
    final (:width, :spread, :length) = _shape(kw, reach);
    final rise = 4.56 * math.sqrt(length);
    final life = length / rise;
    // A tongue's sprite as wide as two of the tongue, and no taller than
    // the flame; a big fire's eddies are as big as it is, so its tongues
    // are at least two fifths of its flame. As many tongues as cover the
    // flame about twice over.
    final side = math.min(math.max(2.2 * width, 0.4 * length), length);
    final alive = (2.2 * 0.6 * (spread + width) * length / (0.2 * side * side))
        .clamp(4.0, 60.0);
    final puff =
        1.0 + 0.6 * math.sin(2 * math.pi * 1.5 / math.sqrt(spread) * _clock);
    _flames.emit(
      key,
      _flameEffect(life, side, 0.5 * (spread - width) + 0.15 * width, rise),
      at,
      perSecond: alive / life * puff,
      direction: axis,
    );
    final tip = at + axis * math.min(1.2 * reach, length + 0.5 * baseWidth);
    _smoke.emit(
      key,
      _smokeEffect(spread * math.sqrt(coarser), _plumeAt(kw, tip.y - at.y)),
      tip,
      perSecond: _puffsPerSecond(kw, spread) / coarser,
      direction: Vector3(0.0, 1.0, 0.0),
    );
    _embers.emit(
      key,
      _emberEffect(rise),
      at,
      perSecond: kw / 25.0,
      direction: Vector3(0.0, 1.0, 0.0),
    );
  }

  /// Tongues [side] across, living [life] s, standing on a disc [radius]
  /// across and leaving it at [rise] m/s.
  ParticleEffect _flameEffect(
    double life,
    double side,
    double radius,
    double rise,
  ) => ParticleEffect(
    count: 1,
    emitter: _Tongues(
      radius: radius,
      lift: 0.4 * side,
      speed: Range(0.5 * rise, rise),
    ),
    lifetime: Range(0.7 * life, 1.2 * life),
    size: Range(0.8 * side, 1.2 * side),
    color: Vector4(0.0, 0.0, 0.0, 0.0),
    affectors: <ParticleAffector>[
      _flameAir,
      // The sheet holds the hue, yellow at the root and the core, orange
      // and red to the edges; this is how bright a tongue is as it rises,
      // and how its soot cools from the yellow of 1300 K towards the dull
      // red of 900 K as it leaves the flame. A tongue alone stays below
      // white; two overlapping are the brightest the flame gets.
      ParticleColorGradient(
        ParticleGradient(<GradientKey>[
          GradientKey(0.0, Vector4(1.1, 0.95, 0.8, 0.0)),
          GradientKey(0.12, Vector4(1.1, 0.95, 0.8, 1.0)),
          GradientKey(0.5, Vector4(0.95, 0.6, 0.4, 0.75)),
          GradientKey(1.0, Vector4(0.5, 0.12, 0.04, 0.0)),
        ]),
      ),
      const ParticleSizeOverLife(from: 1.0, to: 0.5),
    ],
  );

  /// Puffs [width] across as they leave the flame, rising at [rise] m/s.
  ParticleEffect _smokeEffect(double width, double rise) => ParticleEffect(
    count: 1,
    emitter: ConeEmitter(speed: Range(0.6 * rise, rise), halfAngleDegrees: 10),
    lifetime: const Range(_puffLife - 1.0, _puffLife + 1.0),
    size: Range(width, 1.4 * width),
    // Soot-laden smoke scatters less of the light it stops than it
    // absorbs, but mixed with the steam and tar of burning wood it is a
    // mid grey in daylight, not soot-black: seen from above, a black puff
    // over every fire read as a hole in the ground.
    color: Vector4(0.34, 0.33, 0.32, 0.0),
    affectors: <ParticleAffector>[
      _smokeAir,
      const ParticleTurbulence(strength: 0.4, scale: 1.5),
      // A plume widens as it rises, Heskestad's 0.12 z each side.
      ParticleSizeCurve(ParticleCurve.linear(1.0, 3.0)),
      const _Thins(_puffDepth),
    ],
  );

  /// Embers thrown up at about the speed the flame's gas rises, [rise].
  ParticleEffect _emberEffect(double rise) => ParticleEffect(
    count: 1,
    emitter: ConeEmitter(
      speed: Range(0.6 * rise, 1.2 * rise),
      halfAngleDegrees: 25.0,
    ),
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

  /// Eight frames of a tongue of flame side by side: a rounded root at the
  /// bottom of the cell, three fifths of the cell wide, tapering to a tip at the
  /// top that sways a little differently each frame. Yellow in its lower
  /// core, where the soot in a flame is hottest, orange to its edges and
  /// up, and translucent at the rim. The stage scales a texel's colour by
  /// its alpha too, so the colour holds the hue times the square root of
  /// the brightness, and the alpha that square root.
  static ByteData _tongueAtlas() {
    const width = _tongueCell * _tongueFrames;
    final bytes = Uint8List(width * _tongueCell * 4);
    for (var f = 0; f < _tongueFrames; f++) {
      final phase = 2 * math.pi * f / _tongueFrames;
      for (var y = 0; y < _tongueCell; y++) {
        // From the root (0) to the tip (1), the tip in the top row.
        final v = 1.0 - (y + 0.5) / _tongueCell;
        final half =
            0.3 *
            math.sqrt((v / 0.12).clamp(0.0, 1.0)) *
            math.pow(1.0 - v, 0.8) *
            (0.85 + 0.15 * math.sin(phase + 6.0 * v));
        final sway =
            math.pow(v, 1.4) *
            (0.14 * math.sin(phase + 4.0 * v) +
                0.05 * math.sin(2.0 * phase + 11.0 * v));
        for (var x = 0; x < _tongueCell; x++) {
          final u = (x + 0.5) / _tongueCell * 2.0 - 1.0;
          final off = half <= 0 ? 1.0 : (u - sway).abs() / half;
          final edge = (1.0 - off * off).clamp(0.0, 1.0);
          final i =
              (math.pow(edge, 0.7) *
                      math.pow(1.0 - v, 0.4) *
                      (v / 0.05).clamp(0.0, 1.0))
                  .toDouble();
          final core = math.pow(edge, 1.5) * math.pow(1.0 - v, 1.2);
          final glow = math.sqrt(i);
          final o = (y * width + f * _tongueCell + x) * 4;
          bytes
            ..[o] = (glow * 255).round()
            ..[o + 1] = ((0.32 + 0.45 * core) * glow * 255).round()
            ..[o + 2] = ((0.03 + 0.2 * core * core) * glow * 255).round()
            ..[o + 3] = (glow * 255).round();
        }
      }
    }
    return bytes.buffer.asByteData();
  }
}
