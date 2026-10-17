/// The crypt's height fog: the document's density at the eye, a shallow
/// fog's mist on the floor.
///
///     flutter test test/crypt_fog_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_demo_dungeon/src/crypt_fog.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

Level _level(String name) => Level.fromJson(
  jsonDecode(File('assets/levels/$name.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  const eye = 1.6;

  test('as thick at the eye as the level says, on every level', () {
    for (final name in <String>['crypt', 'cistern', 'vaults', 'deep']) {
      final level = _level(name);
      final fog = cryptFog(level, eye: eye);
      final floor = level.entities
          .firstWhere((e) => e.type == 'player_spawn')
          .position
          .y;
      // Mutation: the base height at the floor rather than the eye — the
      // eye stands in air a fifth as thick as the level was tuned for.
      expect(
        fog.densityAt(floor + eye),
        closeTo(level.fogDensity, 1e-12),
        reason: name,
      );
    }
  });

  test('a level that starts the player on an upper floor is fogged from '
      'that floor', () {
    final document = _level('crypt').toJson();
    final entities = <Object?>[
      for (final e in document['entities']! as List<Object?>)
        if (e case final Map<String, Object?> spawn
            when spawn['type'] == 'player_spawn')
          <String, Object?>{
            ...spawn,
            'at': <Object?>[
              (spawn['at']! as List<Object?>)[0],
              3.0,
              (spawn['at']! as List<Object?>)[2],
            ],
          }
        else
          e,
    ];
    final raised = Level.fromJson(<String, Object?>{
      ...document,
      'entities': entities,
    });
    // Mutation: the spawn's floor left out — the upper floor's eye stands
    // three metres over the fog's base, in air e^1.5 thinner.
    expect(
      cryptFog(raised, eye: eye).densityAt(3.0 + eye),
      closeTo(raised.fogDensity, 1e-12),
    );
  });

  test('thicker on the floor and thinner at the vault, by e over two '
      'metres', () {
    final level = _level('crypt');
    final fog = cryptFog(level, eye: eye);
    // Mutation: the falloff left at the engine's default — the floor's
    // mist is a twentieth thicker than the air at the eye, not e^0.8.
    expect(
      fog.densityAt(0.0),
      closeTo(level.fogDensity * math.exp(eye / 2.0), 1e-9),
    );
    expect(fog.densityAt(eye + 2.0), closeTo(level.fogDensity / math.e, 1e-9));
  });

  test('turned off, it is no fog at all', () {
    expect(cryptFog(_level('crypt'), eye: eye, on: false).density, 0.0);
  });
}
