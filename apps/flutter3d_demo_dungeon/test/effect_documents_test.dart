/// The crypt's effects written as `.f3dfx` documents, held to the Dart they
/// were written in particle for particle.
///
///     flutter test test/effect_documents_test.dart
///
/// **What proves the format covers them is that nothing moves.** Each
/// document's effect and the game's own `ParticleEffect` are burst — or
/// burned, for the torch — from one seed and stepped alike, and the bytes a
/// draw would read must be the same bytes. A key read with the wrong default,
/// an affector out of order or an ease misnamed changes them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_demo_dungeon/src/crypt_elements.dart';
import 'package:flutter3d_demo_dungeon/src/effects.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

EffectDocument _read(String name) =>
    EffectDocument.parse(File('effects/$name').readAsStringSync(), from: name);

/// [effect] started at a torch's height and stepped [seconds] a frame at a
/// time, in a world pulling down at [gravity]: position, colour and size of
/// every live particle.
Float32List _run(
  ParticleEffect effect, {
  required bool burning,
  double seconds = 0.6,
  double gravity = 9.81,
}) {
  final system = ParticleSystem(capacity: 2048, seed: 11)..gravity = gravity;
  final at = Vector3(1.0, 1.5, -2.0);
  final up = Vector3(0.0, 1.0, 0.0);
  if (!burning) system.burst(effect, at, direction: up);
  final key = Object();
  for (var t = 0.0; t < seconds; t += 1.0 / 60.0) {
    if (burning) system.emit(key, effect, at, perSecond: 150.0, direction: up);
    system.advance(1.0 / 60.0);
  }
  final out = Float32List(2048 * ParticleSystem.floatsPerInstance);
  final count = system.writeInstances(out);
  return Float32List.sublistView(
    out,
    0,
    count * ParticleSystem.floatsPerInstance,
  );
}

void _same(
  EffectDescription read,
  ParticleEffect dart, {
  bool burning = false,
}) {
  expect(read.effect.count, dart.count);
  final ours = _run(read.effect, burning: burning);
  expect(ours, isNotEmpty, reason: '${read.name} emitted nothing');
  expect(ours, _run(dart, burning: burning), reason: read.name);
}

void main() {
  test('the blast is the blast: core, embers and smoke', () {
    final blast = _read('blast.f3dfx');
    _same(blast['explosionCore']!, Effects.explosionCore);
    _same(blast['explosionEmbers']!, Effects.explosionEmbers);
    _same(blast['explosionSmoke']!, Effects.explosionSmoke, burning: true);
    expect(blast['explosionSmoke']!.rate, 34.0, reason: 'reactions.dart');
    expect(
      blast.effects.expand((e) => e.triggers).map((t) => t.event).toSet(),
      <String>{'elements.exploded'},
    );
  });

  test('the torch burns as it did, gradient, swirl and all', () {
    final crypt = _read('crypt.f3dfx');
    _same(crypt['flame']!, Effects.flame, burning: true);
    expect(crypt['flame']!.rate, 150.0, reason: 'frame_effects.dart');
  });

  test('a splash and the splinters fall by the world they are in', () {
    // Mutation: read `"acceleration": "world"` as a number, or as earth's.
    // On the Moon the splash falls slower in both, and alike.
    final crypt = _read('crypt.f3dfx');
    _same(crypt['splash']!, CryptElements.splash);
    _same(crypt['splinters']!, CryptElements.splinters);
    expect(
      _run(crypt['splash']!.effect, burning: false, gravity: 1.62),
      _run(CryptElements.splash, burning: false, gravity: 1.62),
    );
    expect(
      _run(crypt['splash']!.effect, burning: false, gravity: 1.62),
      isNot(_run(crypt['splash']!.effect, burning: false)),
    );
    _same(crypt['impactSparks']!, Effects.impactSparks);
  });
}
