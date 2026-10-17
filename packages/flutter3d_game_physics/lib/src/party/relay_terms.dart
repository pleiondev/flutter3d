import 'dart:math' as math;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The letters a party or room code is made of: no `0`/`O` and no `1`/`I`,
/// which read alike aloud and on a phone keyboard, the two ways a code
/// travels between two people in one room.
const String partyCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// A five-letter code from [partyCodeAlphabet], thrown with [dice].
///
/// **The dice are handed in.** A code is not part of a step, but this
/// package is held to the rule that a step reaches for no loose generator,
/// and a test wants the same code twice; an application passes
/// `math.Random()`.
String partyCode(math.Random dice) => List<String>.generate(
  5,
  (_) => partyCodeAlphabet[dice.nextInt(partyCodeAlphabet.length)],
).join();

/// What every machine of one party has to share beyond the simulation's
/// version: the physics backend, since the native core and the Dart
/// reference are not promised to agree, and a session across the two
/// parts at the first contact. The relay holds a room and a party to the
/// first machine's terms.
///
/// **The run's choice, made here if nothing has asked yet.** Read before it
/// was made, the first machine of a party said `dart` and the ones after
/// staging said `native`.
String get physicsTerms => 'physics=${usePhysics().name}';

/// [simulation] as the one number a relay compares: the engine's version
/// and the game's, `engine × 1000 + genre`. Two builds agree on it exactly
/// when a session between them steps the same; a game with no genre of its
/// own passes [SimulationVersion.engineOnly].
int relayVersionOf(SimulationVersion simulation) =>
    simulation.engine * 1000 + simulation.genreVersion;
