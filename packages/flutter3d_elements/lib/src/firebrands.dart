/// Burning brands a fire lofts into the wind: bodies of their own, as hot
/// as the flame they leave, which come down on what lies downwind and light
/// it as the core lights anything hot enough that they touch.
library;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

import 'simulation.dart' show Solid;
import 'smoke_plume.dart';

/// The brands every fire of a world lofts, by the fuel it burns, carried up
/// its plume and off on the wind.
///
/// **A law, not dice.** A fire burning ṁ kg/s — its heat over the heat of
/// combustion of what burns, Q/ΔH_c — lofts [share] of that as brands, each
/// a [brand]: a brand leaves the fire each time the fuel it has burnt since
/// the last one has made another. The same fire in the same wind lofts the
/// same brands at the same steps, on every platform and in every replay.
///
/// **Bodies with heat.** A brand is a body of [brand]'s solid, put in the
/// world at the top of the flame, as hot as that flame's gas
/// ([NativeMaterial.flameTemperature] of what burns), moving up the plume
/// at McCaffrey's centreline speed there ([SmokePlume.centerlineSpeed])
/// with the wind. From then on it is the core's: it falls through the air,
/// burns what fuel it has, and sets alight what it comes down on and is hot
/// enough to light, as any hot body does.
///
/// **The game's budget, not the fire's.** [most] brands are alight at
/// once; a fire due one more past them lofts it not, and [skipped] counts
/// them. A brand burnt out, or out and cold a second after it was lofted,
/// is taken out of the world.
///
/// Stepped by the game before its world, saved in its save beside the
/// world's snapshot ([save], [restore]).
final class Firebrands {
  /// Brands of [brand] lofted from [world]'s fires, [share] kilograms per
  /// kilogram burnt, at most [most] (eight by default) alight at once.
  ///
  /// Throws an [ArgumentError] for a negative or NaN [share], or a [brand]
  /// with no mass.
  Firebrands(
    this.world, {
    required this.brand,
    required this.share,
    this.most = 8,
  }) {
    if (!(share >= 0.0)) throw ArgumentError.value(share, 'share');
    if (!(brand.mass > 0.0)) {
      throw ArgumentError.value(brand, 'brand', 'weighs nothing');
    }
  }

  /// The world whose fires loft the brands, and which the brands are in.
  final NativeWorld world;

  /// What one brand is: its shape, what it is made of and how dense.
  final Solid brand;

  /// Kilograms of brands lofted for every kilogram a fire burns.
  final double share;

  /// The most brands alight at once.
  final int most;

  /// The brands in the world, oldest first, each with the seconds since it
  /// was lofted.
  final List<({NativeBody body, double age})> _brands =
      <({NativeBody body, double age})>[];

  /// What each fire, by its body, has burnt towards its next brand, in
  /// brands.
  final Map<NativeBody, double> _owed = <NativeBody, double>{};

  /// The brands in the world, oldest first.
  List<NativeBody> get brands => <NativeBody>[for (final b in _brands) b.body];

  /// How many brands a fire was due and did not loft, for [most].
  int get skipped => _skipped;
  int _skipped = 0;

  /// [dt] seconds of the world's fires: the spent brands taken out, and
  /// each fire's brands lofted. Called before the world is stepped.
  void step(double dt) {
    for (var i = _brands.length - 1; i >= 0; i--) {
      final b = _brands[i];
      final body = b.body;
      final spent =
          !world.contains(body) ||
          world.fuelOf(body) <= 0.0 ||
          (b.age > 1.0 && !world.isBurning(body));
      if (spent) {
        _brands.removeAt(i);
        if (world.contains(body)) world.removeBody(body);
      } else {
        _brands[i] = (body: body, age: b.age + dt);
      }
    }
    final burning = <NativeBody>{};
    final aloft = <NativeBody>{for (final b in _brands) b.body};
    for (final fire in world.fires()) {
      // A brand burning on its way down lofts none of its own.
      if (aloft.contains(fire.body) || !world.contains(fire.body)) continue;
      final made = world.materialOf(fire.body);
      final perKg = made.heatOfCombustion;
      if (!(perKg > 0.0) || !(fire.power > 0.0)) continue;
      burning.add(fire.body);
      var owed =
          (_owed[fire.body] ?? 0.0) +
          share * fire.power / perKg * dt / brand.mass;
      while (owed >= 1.0) {
        owed -= 1.0;
        if (_brands.length >= most) {
          _skipped++;
          continue;
        }
        _loft(fire, made);
      }
      _owed[fire.body] = owed;
    }
    _owed.removeWhere((body, _) => !burning.contains(body));
  }

  /// One brand out of the top of [fire]'s flame, up its plume and off on
  /// the wind, as hot as the flame of [made].
  void _loft(NativeFire fire, NativeMaterial made) {
    final tip = fire.at + fire.axis * fire.reach;
    final kw = fire.power / 1000.0;
    final rising = SmokePlume.centerlineSpeed(kw, fire.reach);
    final hot = made.flameTemperature > 0.0
        ? made.flameTemperature
        : fire.sootTemperature;
    final body = world.addBody(position: tip, mass: brand.mass);
    final parts = brand.parts;
    if (parts != null) {
      world.setCompound(body, world.createCompound(parts));
    } else {
      world.setShape(body, brand.shape);
    }
    world
      ..setMaterial(body, brand.material)
      ..setVelocity(body, fire.axis * rising + world.windAt(tip))
      ..setTemperature(body, brand.temperature ?? hot);
    if (brand.rounding > 0) world.setRounding(body, brand.rounding);
    _brands.add((body: body, age: 0.0));
  }

  /// [body] taken out, if it is a brand: one a game has seen land where it
  /// keeps no brands.
  bool remove(NativeBody body) {
    final before = _brands.length;
    _brands.removeWhere((b) => b.body == body);
    if (_brands.length == before) return false;
    if (world.contains(body)) world.removeBody(body);
    return true;
  }

  /// The brands and what each fire has burnt towards its next, as a value
  /// JSON can hold: saved beside the world's snapshot.
  Object? save() => <String, Object?>{
    'brands': <Object?>[
      for (final b in _brands) <num>[b.body.raw, b.age],
    ],
    'owed': <Object?>[
      for (final MapEntry(key: body, value: owed) in _owed.entries)
        <num>[body.raw, owed],
    ],
    'skipped': _skipped,
  };

  /// Back to what [save] gave, the world restored under it first; anything
  /// else holds no brands.
  void restore(Object? saved) {
    _brands.clear();
    _owed.clear();
    _skipped = 0;
    if (saved is! Map) return;
    if (saved['brands'] case final List<Object?> brands) {
      for (final b in brands) {
        if (b case [final int raw, final num age]) {
          _brands.add((body: NativeBody(raw), age: age.toDouble()));
        }
      }
    }
    if (saved['owed'] case final List<Object?> owed) {
      for (final o in owed) {
        if (o case [final int raw, final num left]) {
          _owed[NativeBody(raw)] = left.toDouble();
        }
      }
    }
    if (saved['skipped'] case final int skipped) _skipped = skipped;
  }
}
