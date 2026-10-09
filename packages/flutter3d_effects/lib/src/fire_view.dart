/// The physics core's fires, drawn: the tongues of each flame, the smoke
/// over it, the embers it throws, the light it gives, and the bodies it
/// chars.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart'
    show FireSteps, SmokePlume;
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, Portable, Vector3Foundation;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeBody, NativeFire, NativeWorld;
import 'package:vector_math/vector_math.dart';

import 'fire_light.dart';

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

/// Gas carries what is in it: a tongue of flame and a puff of smoke are
/// the gas itself and move with it, the wind where their fire is plus the
/// rise of its hot gas where the particle now is.
final class _InTheGas extends ParticleAffector {
  _InTheGas(this.air, this.rise);

  final Vector3 Function(Particle particle) air;
  final double Function(Particle particle) rise;

  @override
  void apply(Particle particle, double dt) {
    final a = air(particle);
    particle.velocity.setValues(a.x, a.y + rise(particle), a.z);
  }
}

/// An ember lags the gas it is in by its drag: Newton's, ½ρ C_d A |Δv|Δv
/// with a sphere's C_d of 0.44, on a ball as wide as the particle, of the
/// density of char. Its speed relaxes to the gas's over
/// τ = 4 ρ_p d / (3 ρ_a C_d |Δv|), and it falls under its own weight — by
/// [gravity], its world's, which [FireView.update] reads once a frame.
final class _Dragged extends ParticleAffector {
  _Dragged(this.air, this.rise);

  final Vector3 Function(Particle particle) air;
  final double Function(Particle particle) rise;

  /// How hard the fire's world pulls an ember down, m/s²: its
  /// [NativeWorld.gravityMagnitude], down the y axis, as of the last
  /// [FireView.update]. Held here rather than asked a particle at a time,
  /// which would be a call into the core per ember per step.
  double gravity = standardGravity;

  /// The density of the air an ember is dragged through, kg/m³: its fire's
  /// world's [NativeWorld.airDensity], as of the last [FireView.update].
  ///
  /// **The world's air, not a fire's.** An ember lofted out of the plume is
  /// dragged through the air about it, and that air is its world's: a fire
  /// in a cold world drags its embers harder, one at altitude less, as that
  /// world's properties say (`WorldProperties.airDensity`, the ideal gas at
  /// its temperature and pressure unless a world says otherwise). It was a
  /// fixed 1.18 once, and then this view's own ideal gas beside the world's.
  double airDensity = standardAirDensity;

  @override
  void apply(Particle particle, double dt) {
    final a = air(particle);
    final dx = a.x - particle.velocity.x;
    final dy = a.y + rise(particle) - particle.velocity.y;
    final dz = a.z - particle.velocity.z;
    final slip = math.sqrt(dx * dx + dy * dy + dz * dz);
    final k = slip <= 0
        ? 0.0
        : 1.0 -
              math.exp(
                -dt *
                    3.0 *
                    airDensity *
                    0.44 *
                    slip /
                    (4.0 * _emberDensity * _emberDiameter(particle)),
              );
    particle.velocity
      ..x += dx * k
      ..y += dy * k - gravity * dt
      ..z += dz * k;
  }
}

/// The density of a glowing ember lofted from a wood fire, kg/m³: 127, from
/// Manzello's firebrands' masses and sizes (Yang and colleagues, Journal of
/// Fire Sciences, 2025).
const double _emberDensity = 127.0;

/// An ember's own diameter, m, by its seed: Douglas firs' firebrands are
/// sticks 3 mm thick on average (Manzello and colleagues, Int. J. Wildland
/// Fire 16, 2007). Drawn far wider than it is, as its glow blooms.
double _emberDiameter(Particle particle) => 0.002 + 0.002 * particle.seed;

/// A puff of smoke as dark as the plume it stands in: 1 − e^(−τ), τ the
/// plume's optical depth across its middle at the puff's height
/// (`flutter3d_elements/doc/smoke_plume.md`), which [depth] gives — null
/// once its fire is out, when the puff thins away over the rest of its
/// life.
final class _Thins extends ParticleAffector {
  const _Thins(this.depth);

  final double? Function(Particle particle) depth;

  @override
  void apply(Particle particle, double dt) {
    final tau = depth(particle);
    final life = particle.life;
    // Faded out over the last tenth of its life, where a plume cut short by
    // the view's budget ends, so its top is not a hard edge.
    final end = math.min(1.0, (1.0 - life) / 0.1);
    particle.color.w = tau == null
        ? particle.color.w * end
        : (1.0 - math.exp(-tau)) * end;
  }
}

/// A puff as wide as the plume where it is: Heskestad's 0.12 (z − z₀) each
/// side of the axis, z₀ the plume's virtual origin, and never narrower
/// than it left the flame.
final class _PlumeWide extends ParticleAffector {
  _PlumeWide(this.width);

  final double Function(Particle particle) width;

  @override
  void apply(Particle particle, double dt) {
    particle.size = math.max(particle.birthSize, width(particle));
  }
}

/// A tongue as bright as the soot in it: a blackbody at the soot's
/// temperature through the flame's emissivity, ε·σT⁴·η(T)/π candela a
/// square metre, η the lumens a radiated watt is worth at T — drawn
/// [_emissiveGain] times brighter, about 29, as the glow was tuned.
///
/// The soot cools as the tongue rises through the flame, by McCaffrey's
/// centreline excess (NBSIR 79-1910, 1979): the same through the continuous
/// flame, to z/Q^(2/5) = 0.08 m/kW^(2/5); falling as its inverse through the
/// intermittent flame, to 0.2; and as its −5/3 power in the plume beyond. A
/// tongue lives about as long as it takes to rise the flame's [length], so
/// its share of its life is its share of that height.
///
/// It fades in over its first eighth and out as it goes, the edge of what
/// the flame's eddies carry.
final class _Glows extends ParticleAffector {
  const _Glows({
    required this.soot,
    required this.air,
    required this.emissivity,
    required this.kw,
    required this.length,
  });

  final double soot, air, emissivity, kw, length;

  @override
  void apply(Particle particle, double dt) {
    final life = particle.life;
    final x = life * length / math.pow(math.max(kw, 1e-6), 0.4);
    final excess = x < 0.08
        ? 1.0
        : x < 0.2
        ? 0.08 / x
        : 0.4 * math.pow(0.2 / x, 5 / 3);
    final t = air + (soot - air) * excess;
    final nits =
        emissivity *
        stefanBoltzmann *
        t *
        t *
        t *
        t *
        Blackbody.efficacy(t) /
        math.pi;
    final color = Blackbody.color(t);
    final y = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z;
    final scale = y > 0
        ? nits * _emissiveGain / Photometric.legacyNits / y
        : 0.0;
    final alpha = life < 0.12 ? life / 0.12 : (1.0 - life) / 0.88;
    particle.color.setValues(
      color.x * scale,
      color.y * scale,
      color.z * scale,
      alpha,
    );
  }
}

/// How much brighter than a blackbody's luminance a flame's tongues and
/// glowing char are drawn: `legacyNits / bulbAtOneMeter`, about 29. A ratio.
///
/// The glow was tuned before 1.0 as nits over [Photometric.bulbAtOneMeter]
/// in the renderer's own unit, and an emissive colour is drawn at
/// `RenderMaterial.emissiveStrength` nits, `legacyNits` by default; so
/// a tongue's colour of `L·gain / legacyNits` is drawn at `L·gain` nits,
/// the same picture. Like the firelight's ×91 (`FireView._firelightGain`), it
/// is there
/// because the scenes fires burn in are lit and exposed for daylight: at
/// the true luminance a flame would look as dim against them as a candle
/// in the sun.
const double _emissiveGain =
    Photometric.legacyNits / Photometric.bulbAtOneMeter;

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

/// What a fire is to what it sent up: its heat, kW; its base's middle and
/// width, m; and how long its flame is, m.
typedef _Fire = ({
  double kw,
  Vector3 at,
  double base,
  double length,
  double soot,
});

/// A body whose look burns with it.
final class _Watched {
  _Watched(this.body, this.look, this.fresh, this.charred);

  final NativeBody body;
  final MeshNode look;
  final Vector4 fresh, charred;
}

/// Every fire of [world] drawn into [scene] through [renderer].
///
/// The core says where each fire is, the watts it gives off, how wide the
/// patch alight is, how far its flame reaches along which axis, and how hot
/// its flame is — the flame it heats other bodies with. The rest follows
/// from what is measured of real fires:
///
/// * **Size**: the flame stands on the patch alight, as wide as it, and is
///   as long as the core's. A flame no taller than twice its base burns as
///   flamelets half its height across, side by side over the base; a
///   slender one as one tongue as wide as its base.
/// * **Tongues** rise through the flame as fast as McCaffrey measured the
///   gas in a continuous flame rise, 6.84·√z m/s, which averages 4.56·√L
///   over a flame L long (the mean of √z over nought to L is ⅔·√L, and
///   ⅔ × 6.84 = 4.56): each lives as long as rising its flame takes. A
///   fire puffs at about 1.5/√D Hz (Pagni), D its base, so they come in
///   breaths. They are yellow at the root and the core, where the soot in
///   them is hottest, orange in the body and dull red at the tips, and as
///   many as cover the flame about twice over, so the overlap of their
///   light does not wash the flame out to white.
/// * **Smoke** leaves the flame's tip and rises with that fire's own
///   plume, McCaffrey's 1.11·Q^(1/3)·z^(−1/3) on its axis and falling off
///   as a Gaussian of the distance from it over Heskestad's 0.12 (z − z₀),
///   as wide as the plume where it is. As much is made as the soot its fuel
///   gives off — 1.5 % of what burns for a generic wood, 0.2 % for a pine
///   crib, 9 % for a tyre, the core's [NativeFire.sootYield] — and soot
///   stops light over 8.7 m² a gram; it scatters [smokeAlbedo] of what it
///   stops, and thins as it spreads. It is lit by the scene's lights, the
///   firelight among them, through a six-way sheet.
/// * **Embers** are thrown up and lag the plume by their drag.
/// * **Firelight**: the flame's radiant share of its heat, as the lumens a
///   blackbody at its soot's temperature gives for it, in the colour of
///   that blackbody — dim and red for a cool flame, bright and yellow for a
///   hot one; the camera's exposure does the rest. As [lights] says.
///
/// **Two flame lengths.** The core's flame, which heats what is near it, is
/// Heskestad's L = 0.235·Q^(2/5) − 1.02·D; the tongues here cool and rise by
/// McCaffrey's regimes, whose flame tip is the end of his intermittent zone,
/// z = 0.2·Q^(2/5). The coefficients alone differ by about a fifth (0.235
/// against 0.2), more once the base's term is taken off Heskestad's. The
/// tongues are drawn over the core's length and cooled on
/// McCaffrey's scale: the picture follows the correlation that was measured
/// for how a flame looks, and the heat the one measured for what it does.
///
/// **Brighter than the physics, on purpose.** The tongues and the char are
/// drawn about 29 times their blackbody luminance and the firelight about 91
/// times its candela, the gains the games' scenes were tuned with before
/// 1.0; see `_emissiveGain` and `_firelightGain`.
///
/// Everything that flies is carried by the wind where its fire is, and a
/// wind leans the flame as far as the core's flame leans.
final class FireView {
  FireView({
    required this._world,
    required GraphicsDevice device,
    required this._scene,
    required Renderer renderer,
    this.detail = FireDetail.full,
    this.lights = const FireLights.clusters(),
    this.smokeAlbedo = 0.66,
  }) : _flames = ParticleSystem(capacity: detail.flames, seed: 5),
       _embers = ParticleSystem(capacity: detail.embers, seed: 6),
       _smoke = ParticleSystem(capacity: detail.smoke, seed: 7) {
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
    );
    final tongues = device.createTextureFromPixels(
      width: _tongueCell * _tongueFrames,
      height: _tongueCell,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: _tongueAtlas(),
    );
    // The smoke first, over what is behind it; the flame and the embers
    // after, added on top: a flame shines through the smoke it makes.
    //
    // Both are soft against the scene over a few centimetres, no more: a
    // torch's flame stands a hand from the wall it is fixed to.
    renderer
      ..renderSteps.addContributor(
        ParticleContributor(
          _smoke,
          sixWay: SixWayMaterial(
            positive: upload(smoke.positive),
            negative: upload(smoke.negative),
          ),
          flipbook: Flipbook(columns: 4, rows: 4),
          softness: 0.3,
        ),
      )
      ..renderSteps.addContributor(
        ParticleContributor(
          _flames,
          texture: tongues,
          flipbook: Flipbook(columns: _tongueFrames, rows: 1, loops: 2),
          softness: 0.03,
        ),
      )
      ..renderSteps.addContributor(ParticleContributor(_embers));
  }

  final NativeWorld _world;
  Scene _scene;

  /// The scene the firelight hangs in; set again, it moves there.
  Scene get scene => _scene;
  set scene(Scene value) {
    if (identical(value, _scene)) return;
    for (final node in _lights) {
      node.removeFromParent();
      value.add(node);
    }
    _scene = value;
  }

  /// How much is drawn at most.
  final FireDetail detail;

  /// How the fires light the scene.
  final FireLights lights;

  /// The share of the light it stops that the smoke scatters rather than
  /// absorbs: 0.66 at first, a flaming pine fire's at 550 nm (Patterson
  /// and McMahon, Atmospheric Environment 18, 1984); a smouldering fire's
  /// is about 0.97.
  final double smokeAlbedo;

  /// The firelight, one light to a fire or a cluster of them, as the last
  /// [update] placed them.
  List<LightNode> get firelight => List<LightNode>.unmodifiable(_lights);
  final List<LightNode> _lights = <LightNode>[];

  final ParticleSystem _flames, _embers, _smoke;
  final List<_Watched> _watched = <_Watched>[];
  final Set<int> _alight = <int>{};
  double _clock = 0.0;

  /// Every fire as of the last [update], by the key its particles carry.
  final Map<Object, _Fire> _fires = <Object, _Fire>{};

  /// The wind each fire last stood in, kept after it goes out for what it
  /// sent up.
  final Map<Object, Vector3> _winds = <Object, Vector3>{};

  /// How much of each watched body is alight, by its handle.
  final Map<int, double> _share = <int, double>{};

  Vector3 _windOf(Particle particle) =>
      _winds[particle.source] ?? Vector3.zero();

  /// How fast the gas in the flame [particle] is in rises: McCaffrey's
  /// 6.84·√z m/s at z over the fire's base, faster up the flame. Nought once
  /// its fire is out.
  double _flameRise(Particle particle) {
    final fire = _fires[particle.source];
    if (fire == null) return 0.0;
    final z = (particle.position.y - fire.at.y).clamp(
      0.05 * fire.length,
      fire.length,
    );
    return 6.84 * math.sqrt(z);
  }

  /// How far [particle] is above its fire's plume's virtual origin, and
  /// from its axis, m; null once the fire is out.
  ({double above, double off})? _inPlume(Particle particle) {
    final fire = _fires[particle.source];
    if (fire == null) return null;
    final dx = particle.position.x - fire.at.x;
    final dz = particle.position.z - fire.at.z;
    return (
      above: particle.position.y - fire.at.y - _origin(fire.kw, fire.base),
      off: math.sqrt(dx * dx + dz * dz),
    );
  }

  /// How fast the plume [particle] is in rises: McCaffrey's centreline
  /// 1.11·Q^(1/3)·z^(−1/3) m/s, Q in kW, from the heat of the fire that sent
  /// it alone, falling off its axis as e^(−(r/b)²), b Heskestad's
  /// 0.12 (z − z₀). Nought once its fire is out: the smoke drifts on in the
  /// wind.
  double _plumeRise(Particle particle) {
    final fire = _fires[particle.source];
    final where = _inPlume(particle);
    if (fire == null || where == null) return 0.0;
    final b = math.max(0.12 * where.above, 0.5 * fire.base);
    final r = where.off / b;
    return _plumeAt(fire.kw, particle.position.y - fire.at.y) *
        math.exp(-r * r);
  }

  /// How wide the plume is where [particle] is: twice Heskestad's
  /// 0.12 (z − z₀).
  double _plumeWidth(Particle particle) {
    final where = _inPlume(particle);
    return where == null ? 0.0 : 0.24 * where.above;
  }

  late final _InTheGas _flameAir = _InTheGas(_windOf, _flameRise);
  late final _InTheGas _smokeAir = _InTheGas(_windOf, _plumeRise);
  late final _Dragged _emberAir = _Dragged(_windOf, _plumeRise);
  late final _PlumeWide _plumeWide = _PlumeWide(_plumeWidth);

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
  /// by the share of its surface the core says char covers, and glowing as
  /// a blackbody at the char's temperature over as much of it as is alight
  /// — over all its char once the fire is out, as that char cools.
  void watch(
    NativeBody body,
    MeshNode look, {
    Vector4? fresh,
    Vector4? charred,
  }) => _watched.add(
    _Watched(
      body,
      look,
      fresh ?? _srgbVector(look.material.baseColor),
      charred ?? Vector4(0.06, 0.05, 0.045, 1.0),
    ),
  );

  /// Stops charring [body]'s look.
  void forget(NativeBody body) => _watched.removeWhere((w) => w.body == body);

  /// The fires drawn as the world has them, [dt] seconds on.
  void update(double dt) {
    _clock += dt;
    _emberAir
      ..gravity = _world.gravityMagnitude
      ..airDensity = _world.airDensity;
    final fires = _world.fires();
    burning = fires.length;
    watts = fires.fold(0.0, (sum, f) => sum + f.power);
    // A compound's parts each burn: one key a part, numbered within its
    // body, so a fire keeps its key when another one goes out.
    final parts = <int, int>{};
    final keys = <int>[
      for (final f in fires)
        f.body.raw * 64 + (parts[f.body.raw] = (parts[f.body.raw] ?? -1) + 1),
    ];
    _fires.clear();
    _share.clear();
    for (var k = 0; k < burning; k++) {
      final f = fires[k];
      final wind = _world.windAt(f.at);
      _winds[keys[k]] = wind;
      _fires[keys[k]] = (
        kw: f.power / 1000.0,
        at: f.at,
        base: f.base,
        length: f.reach,
        soot: f.sootYield,
      );
      _share[f.body.raw] = math.max(_share[f.body.raw] ?? 0.0, f.alight);
    }
    // As many puffs as tile each plume; where that is more than the view
    // can hold, each plume is drawn as far up as the puffs it can hold
    // reach, its puffs living that share of their lives.
    final wanted = fires.fold(0.0, (sum, f) {
      final kw = f.power / 1000.0;
      // A fire giving off no heat yet has no plume to carry smoke.
      if (!(kw > 0.0)) return sum;
      final base = math.max(f.base, 0.01);
      final tip = math.max(f.reach, base);
      return sum +
          _puffsPerSecond(kw, base, tip) *
              _puffLife(kw, base, tip, f.sootYield);
    });
    final shorter = wanted > 0.7 * detail.smoke
        ? 0.7 * detail.smoke / wanted
        : 1.0;
    _wanted = <(String, int, int)>[
      ('smoke', wanted.round(), (0.7 * detail.smoke).round()),
    ];
    final now = keys.toSet();
    for (var k = 0; k < burning; k++) {
      _burn(keys[k], fires[k], shorter);
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
    if (steps.charring) _char();
    if (steps.firelight) {
      _light(fires);
    } else {
      for (final node in _lights) {
        node.intensity = 0.0;
      }
    }
    // A step switched off sends nothing and keeps nothing it sent.
    for (final (on, system) in <(bool, ParticleSystem)>[
      (steps.flames, _flames),
      (steps.embers, _embers),
      (steps.smoke, _smoke),
    ]) {
      if (on) continue;
      for (final key in now) {
        system.stopEmitting(key);
      }
      system.clear();
    }
    _flames.advance(dt);
    _embers.advance(dt);
    _smoke.advance(dt);
  }

  /// Which of its steps the view takes ([FireSteps]).
  FireSteps steps = FireSteps.all;

  /// What each step wanted to draw this frame and how much it holds:
  /// where it wanted more, it drew fewer, larger or farther apart.
  List<(String, int, int)> get wanted => _wanted;
  List<(String, int, int)> _wanted = const <(String, int, int)>[];

  void _char() {
    for (final w in _watched) {
      final char = _world.charOf(w.body);
      final material = w.look.material;
      material.baseColor = _fromSrgb(
        w.fresh + (w.charred - w.fresh) * char.share,
      );
      // Char is near enough a blackbody (ε = 1): its luminance is
      // σT⁴·η(T)/π, η the lumens a radiated watt is worth at T, as a
      // Lambertian surface sends it. Over the fire's patch while it burns,
      // over all the char once it is out.
      final alight = _share[w.body.raw] ?? 0.0;
      final glowing = alight > 0.0 ? math.min(alight, char.share) : char.share;
      final t = char.temperature;
      final nits =
          stefanBoltzmann * t * t * t * t * Blackbody.efficacy(t) / math.pi;
      final color = Blackbody.color(t);
      final y = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z;
      material.emissive = y > 0.0 && glowing > 0.0
          ? (color *
                    (glowing *
                        nits *
                        _emissiveGain /
                        Photometric.legacyNits /
                        y))
                .toLinearColor()
          : LinearColor.black;
    }
  }

  /// What the pre-1.0 `fromCandela` multiplied physical candela by, relative
  /// to what the renderer divides by now: `legacyUnit / bulbAtOneMeter`,
  /// about 91. Its counterpart for the flame's own glow is [_emissiveGain].
  static const double _firelightGain =
      Photometric.legacyUnit / Photometric.bulbAtOneMeter;

  /// The firelight: each fire's radiant power as lumens, gathered as
  /// [lights] says, from the middle of their light, in the colour of the
  /// light they give together.
  void _light(List<NativeFire> fires) {
    // `base` is summed weighted by light, as `at` is, and divided below.
    final groups =
        <({Vector3 at, double lumens, Vector3 color, double base})>[];
    if (lights.cluster >= 0) {
      for (final f in fires) {
        final t = f.sootTemperature;
        final lm = f.radiantShare * f.power * Blackbody.efficacy(t);
        if (lm <= 0) continue;
        final at = f.at + f.axis * (0.5 * f.reach);
        final color = Blackbody.color(t)..scale(lm);
        final base = math.max(f.base, 0.01) * lm;
        final near = lights.cluster <= 0
            ? -1
            : groups.indexWhere((g) => g.at.distanceTo(at) <= lights.cluster);
        if (near < 0) {
          groups.add((at: at * lm, lumens: lm, color: color, base: base));
        } else {
          final g = groups[near];
          groups[near] = (
            at: g.at + at * lm,
            lumens: g.lumens + lm,
            color: g.color + color,
            base: g.base + base,
          );
        }
      }
    }
    // The middles, weighted by light; past the most, the two nearest join.
    var placed = <({Vector3 at, double lumens, Vector3 color, double base})>[
      for (final g in groups)
        (
          at: g.at / g.lumens,
          lumens: g.lumens,
          color: g.color,
          base: g.base / g.lumens,
        ),
    ];
    while (placed.length > math.max(lights.most, 1)) {
      var best = (0, 1, double.infinity);
      for (var i = 0; i < placed.length; i++) {
        for (var j = i + 1; j < placed.length; j++) {
          final d = placed[i].at.distanceTo(placed[j].at);
          if (d < best.$3) best = (i, j, d);
        }
      }
      final a = placed[best.$1], b = placed[best.$2];
      final lm = a.lumens + b.lumens;
      placed = <({Vector3 at, double lumens, Vector3 color, double base})>[
        for (var i = 0; i < placed.length; i++)
          if (i != best.$1 && i != best.$2) placed[i],
        (
          at: (a.at * a.lumens + b.at * b.lumens) / lm,
          lumens: lm,
          color: a.color + b.color,
          base: (a.base * a.lumens + b.base * b.lumens) / lm,
        ),
      ];
    }
    while (_lights.length < placed.length) {
      final node = LightNode(
        type: LightType.point,
        intensity: 0.0 * Photometric.legacyUnit,
        castsShadow: false,
        name: 'firelight',
      );
      _scene.add(node);
      _lights.add(node);
    }
    for (var i = 0; i < _lights.length; i++) {
      final node = _lights[i];
      if (i >= placed.length) {
        node.intensity = 0.0;
        continue;
      }
      final g = placed[i];
      // The flame breathes as it puffs, at Pagni's 1.5/√D Hz as its tongues
      // do (D its base, light-weighted over a cluster), and its light with
      // it.
      final breath =
          1.0 + 0.2 * math.sin(2 * math.pi * 1.5 / math.sqrt(g.base) * _clock);
      final most = math.max(g.color.x, math.max(g.color.y, g.color.z));
      node
        ..color = (most > 0 ? g.color / most : Vector3.zero()).toLinearColor()
        // The scenes fires burn in are still lit and exposed in the engine's
        // pre-1.0 unit, so the firelight keeps the gain that unit gave it
        // over physical candela: without it a torch lights its wall about
        // 91 times more dimly than the ambient it was tuned against.
        ..intensity = Photometric.fromLumens(g.lumens) * _firelightGain * breath
        // Out to where it lights a surface facing it with a tenth of a lux,
        // about what a full moon gives (starlight alone is a thousandth).
        ..range = math.sqrt(g.lumens / (4 * math.pi) / 0.1);
      node.setPosition(g.at.x, g.at.y, g.at.z);
    }
  }

  /// [SmokePlume.virtualOrigin].
  static double _origin(double kw, double base) =>
      SmokePlume.virtualOrigin(kw, base);

  /// [SmokePlume.centerlineSpeed].
  static double _plumeAt(double kw, double z) =>
      SmokePlume.centerlineSpeed(kw, z);

  /// kg of soot per joule a wood fire makes, [SmokePlume.woodSoot]: what
  /// [plumeDepth] takes when it is not told.
  static const double woodSoot = SmokePlume.woodSoot;

  /// [SmokePlume.halfWidth].
  static double _halfWidth(double kw, double base, double z) =>
      SmokePlume.halfWidth(kw, base, z);

  /// The plume's optical depth across its middle [z] m over a fire of [kw]
  /// on a base [base] across, making [sootYield] kg of soot a joule
  /// ([NativeFire.sootYield]): what each puff of its smoke is drawn as dark
  /// as, and what a game asks to know how much a column of smoke hides.
  /// [SmokePlume.depth], which the simulation's watcher reads too
  /// (`ElementsSimulation.seenThroughSmoke`).
  static double plumeDepth(
    double kw,
    double base,
    double z, {
    double sootYield = woodSoot,
  }) => _plumeDepth(kw, base, z, sootYield);

  static double _plumeDepth(double kw, double base, double z, double soot) =>
      SmokePlume.depth(kw, base, z, sootYield: soot);

  /// Puffs a second off a flame [tip] m tall, each standing for as long a
  /// stretch of the plume as it is wide: u / 2b there.
  static double _puffsPerSecond(double kw, double base, double tip) =>
      _plumeAt(kw, tip) / (2.0 * _halfWidth(kw, base, tip));

  /// How long a puff off a flame [tip] m tall lives, s: until the plume it
  /// rises in lets through all but a hundredth of the light, τ ∝ z^(−2/3)
  /// falling to 0.01, at McCaffrey's speed on the way
  /// (`flutter3d_elements/doc/smoke_plume.md`).
  static double _puffLife(double kw, double base, double tip, double soot) {
    final k = _plumeDepth(kw, base, tip, soot) * Portable.pow(tip, 2 / 3);
    final end = math.max(Portable.pow(k / 0.01, 1.5), tip);
    return 3.0 /
        (4.0 * 1.11 * Portable.pow(math.max(kw, 1e-6), 1 / 3)) *
        (Portable.pow(end, 4 / 3) - Portable.pow(tip, 4 / 3));
  }

  /// The plume's optical depth where [particle], a puff, now is; null once
  /// its fire is out.
  double? _smokeDepth(Particle particle) {
    final fire = _fires[particle.source];
    if (fire == null) return null;
    final z = math.max(particle.position.y - fire.at.y, 1e-3);
    return _plumeDepth(fire.kw, math.max(fire.base, 0.01), z, fire.soot);
  }

  void _burn(int key, NativeFire f, double shorter) {
    final kw = f.power / 1000.0;
    final base = math.max(f.base, 0.01);
    final length = math.max(f.reach, base);
    // A slender flame is one tongue as wide as its base; a squat one,
    // flamelets half its height across.
    final width = math.min(base, 0.5 * length);
    final rise = 4.56 * math.sqrt(length);
    final life = length / rise;
    // A tongue's sprite as wide as two of the tongue, and no taller than
    // the flame; a big fire's eddies are as big as it is, so its tongues
    // are at least two fifths of its flame. As many tongues as cover the
    // flame about twice over.
    final side = math.min(math.max(2.2 * width, 0.4 * length), length);
    final alive = (2.2 * 0.6 * (base + width) * length / (0.2 * side * side))
        .clamp(4.0, 60.0);
    final puff =
        1.0 + 0.6 * math.sin(2 * math.pi * 1.5 / math.sqrt(base) * _clock);
    // The flame's emissivity from its own light: χr·Q leaves it as
    // radiation from a side of πD·L at the soot's σT⁴, so ε = χr·Q /
    // (σT⁴·πDL), never past one.
    final soot = f.sootTemperature;
    final emissivity = math.min(
      1.0,
      f.radiantShare *
          f.power /
          (stefanBoltzmann * math.pow(soot, 4) * math.pi * base * length),
    );
    if (steps.flames) {
      _flames.emit(
        key,
        _flameEffect(
          life,
          side,
          0.5 * (base - width) + 0.15 * width,
          rise,
          _Glows(
            soot: soot,
            air: _world.airTemperature,
            emissivity: emissivity,
            kw: kw,
            length: length,
          ),
        ),
        f.at,
        perSecond: alive / life * puff,
        direction: f.axis,
      );
    }
    final tip = f.at + f.axis * length;
    final high = math.max(tip.y - f.at.y, base);
    // A fire that makes no soot — glowing charcoal's — sends up no smoke.
    if (steps.smoke && kw > 0.0 && f.sootYield > 0.0) {
      _smoke.emit(
        key,
        _smokeEffect(
          2.0 * _halfWidth(kw, base, high),
          _plumeAt(kw, high),
          shorter * _puffLife(kw, base, high, f.sootYield),
        ),
        tip,
        perSecond: _puffsPerSecond(kw, base, high),
        direction: Vector3(0.0, 1.0, 0.0),
      );
    }
    if (steps.embers) {
      _embers.emit(
        key,
        _emberEffect(rise),
        f.at,
        perSecond: kw / 25.0,
        direction: Vector3(0.0, 1.0, 0.0),
      );
    }
  }

  /// Tongues [side] across, living [life] s, standing on a disc [radius]
  /// across and leaving it at [rise] m/s, glowing as [glow] says.
  ParticleEffect _flameEffect(
    double life,
    double side,
    double radius,
    double rise,
    _Glows glow,
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
      glow,
      const ParticleSizeOverLife(from: 1.0, to: 0.5),
    ],
  );

  /// Puffs [width] across as they leave the flame, rising at [rise] m/s,
  /// living [life] s.
  ParticleEffect _smokeEffect(double width, double rise, double life) =>
      ParticleEffect(
        count: 1,
        emitter: ConeEmitter(
          speed: Range(0.6 * rise, rise),
          halfAngle: 10.0 * math.pi / 180.0,
        ),
        lifetime: Range(life, life),
        size: Range(width, width),
        color: Vector4(smokeAlbedo, smokeAlbedo, smokeAlbedo, 0.0),
        affectors: <ParticleAffector>[
          _smokeAir,
          const ParticleTurbulence(strength: 0.4, scale: 1.5),
          _plumeWide,
          _Thins(_smokeDepth),
        ],
      );

  /// Embers thrown up at about the speed the flame's gas rises, [rise].
  ParticleEffect _emberEffect(double rise) => ParticleEffect(
    count: 1,
    emitter: ConeEmitter(
      speed: Range(0.6 * rise, 1.2 * rise),
      halfAngle: 25.0 * math.pi / 180.0,
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
  /// top that sways a little differently each frame, translucent at the
  /// rim. Grey: its colour and brightness are the soot's, which [_Glows]
  /// gives each tongue. The stage scales a texel's colour by its alpha too,
  /// so the colour holds the square root of the shape, and the alpha that
  /// square root.
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
          final glow = (math.sqrt(i) * 255).round();
          final o = (y * width + f * _tongueCell + x) * 4;
          bytes
            ..[o] = glow
            ..[o + 1] = glow
            ..[o + 2] = glow
            ..[o + 3] = glow;
        }
      }
    }
    return bytes.buffer.asByteData();
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);

/// [color] sRGB-encoded, as the `Vector4` this file paints with.
Vector4 _srgbVector(LinearColor color) {
  final srgb = color.toSrgb();
  return Vector4(srgb.r, srgb.g, srgb.b, srgb.a);
}
