/// What the validator says about a badly authored entity.
///
///     flutter test test/entity_kinds_test.dart
///
/// **Thirteen branches that nothing looked at.** Every `EntityKind` in this
/// package checks its own entity, and until this file none of those checks had
/// a test: they fired only when a level happened to be wrong, and the levels in
/// the repository are right. So the branches were reached by nobody, and a
/// message that says `$speed` where it means `$damage` would have shipped.
///
/// Two claims per branch, and the second is the one that catches a check
/// written backwards: **it fires when the entity is wrong, and it is silent
/// when the entity is right.** A validator that complains about a correct
/// level is worse than one that says nothing — it teaches the author to ignore
/// it, and then the real error scrolls past with the noise.
///
/// Everything goes through a real document and the real `LevelValidator`,
/// because that is the only path an authored level takes. A test that called
/// `validate` directly would pass with the kind unregistered.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

/// One entity, in the smallest level that can hold it.
///
/// A floor, a light, a spawn and an exit as well. None of those are under test
/// here — they are there because the level *rules* ask for them, and a fixture
/// that leaves them out gets "no exit" and "the level will be black" back on
/// every single claim below. Building this through the real validator means
/// living with the real rules, which is the point: the alternative is calling
/// `validate` on a kind directly and passing with the kind unregistered.
List<LevelIssue> _issuesFor(Map<String, Object?> entity) {
  final level = Level.fromJson(<String, Object?>{
    'version': 1,
    'name': 'one entity',
    'materials': <String, Object?>{
      'stone': <String, Object?>{'baseColor': <double>[0.5, 0.5, 0.5, 1.0]},
    },
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, -0.5, 0.0],
        'size': <double>[20.0, 1.0, 20.0],
        'material': 'stone',
      },
    ],
    'lights': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, 6.0, 0.0],
        'intensity': 20.0,
        'range': 20.0,
      },
    ],
    'entities': <Object?>[
      <String, Object?>{
        'type': EntityTypes.playerSpawn,
        'at': <double>[0.0, 0.0, -4.0],
      },
      <String, Object?>{
        'type': EntityTypes.exit,
        'name': 'the way out',
        'at': <double>[0.0, 1.0, 6.0],
        'text': 'done',
      },
      entity,
    ],
  });

  return LevelValidator(
    registry: platformerRegistry(),
    rules: platformerRules(),
  ).validate(level);
}

/// The messages of a given severity, so a claim can name the words it expects.
List<String> _of(List<LevelIssue> issues, LevelIssueSeverity severity) =>
    <String>[
      for (final issue in issues)
        if (issue.severity == severity) issue.message,
    ];

List<String> _errors(Map<String, Object?> entity) =>
    _of(_issuesFor(entity), LevelIssueSeverity.error);

List<String> _warnings(Map<String, Object?> entity) =>
    _of(_issuesFor(entity), LevelIssueSeverity.warning);

/// An entity of [type], at the origin, with whatever else is given.
Map<String, Object?> _entity(String type, [Map<String, Object?>? properties]) =>
    <String, Object?>{
      'type': type,
      'name': 'the thing',
      'at': <double>[0.0, 1.0, 0.0],
      ...?properties,
    };

/// The engine's own kinds, which `platformerRegistry` composes in.
///
/// Listed rather than derived, because there is nothing to derive it from: a
/// registry is a flat map and an `EntityKind` does not say which package it
/// came from. A name added here by mistake silences a real gap, so the guard
/// below checks the list from both ends.
const Set<String> _engineTypes = <String>{
  EntityTypes.playerSpawn,
  EntityTypes.door,
  EntityTypes.lift,
  EntityTypes.platform,
  EntityTypes.button,
  EntityTypes.trigger,
  EntityTypes.exit,
  // The engine names seven; the eighth is a lamp, whose type string the game
  // package spells out rather than declaring, so it is spelt out here too.
  'lamp',
};

void main() {
  group('a collectible', () {
    test('must say what it gives', () {
      // Mutation: drop the `requireText`. The level loads, the entity spawns,
      // and walking over it credits a purse under the key `null`.
      expect(_errors(_entity(PlatformerEntities.collectible)),
          contains(contains('"what"')));
    });

    test('and giving none of it is worth saying out loud', () {
      expect(
        _warnings(_entity(PlatformerEntities.collectible,
            <String, Object?>{'what': 'coin', 'count': 0})),
        contains(contains('does nothing')),
      );
    });

    test('and a proper one is silent', () {
      final entity = _entity(PlatformerEntities.collectible,
          <String, Object?>{'what': 'coin', 'count': 1});
      expect(_errors(entity), isEmpty);
      expect(_warnings(entity), isEmpty);
    });
  });

  group('a hazard', () {
    test('cannot ride something that is not there', () {
      // The saw is a hazard riding a mover, named by a string. A typo in that
      // string is a saw that stands still in the air for ever, and there is no
      // other way to notice.
      expect(
        _errors(_entity(PlatformerEntities.hazard,
            <String, Object?>{'follows': 'the arm that is not'})),
        contains(contains('no entity in this level is named')),
      );
    });

    test('that does no damage is a warning, not an error', () {
      // Mutation: make it an error. Authoring a hazard at zero damage while
      // laying a level out is normal, and a validator that refuses the document
      // stops the work.
      expect(
        _errors(_entity(
            PlatformerEntities.hazard, <String, Object?>{'damage': 0.0})),
        isEmpty,
      );
      expect(
        _warnings(_entity(
            PlatformerEntities.hazard, <String, Object?>{'damage': 0.0})),
        contains(contains('no damage')),
      );
    });

    test('unless it kills outright, which is what "instant" means', () {
      // Mutation: drop the `instant` check. Every pit in the game — all of
      // which kill instantly and carry no damage number — warns.
      expect(
        _warnings(_entity(PlatformerEntities.hazard,
            <String, Object?>{'damage': 0.0, 'instant': true})),
        isEmpty,
      );
    });
  });

  group('a checkpoint', () {
    test('must be numbered', () {
      // Mutation: default the order to zero. Every post in the level is post
      // zero, they sort arbitrarily, and dying sends the player backwards.
      expect(_errors(_entity(PlatformerEntities.checkpoint)),
          contains(contains('"order"')));
    });

    test('and a numbered one is silent', () {
      expect(
        _errors(_entity(
            PlatformerEntities.checkpoint, <String, Object?>{'order': 1})),
        isEmpty,
      );
    });
  });

  group('a spring', () {
    test('that throws nowhere is refused', () {
      expect(
        _errors(
            _entity(PlatformerEntities.spring, <String, Object?>{'speed': 0.0})),
        contains(contains('does nothing')),
      );
    });

    test('and one with no speed at all takes the default', () {
      // Mutation: treat a missing `speed` as zero. Every spring authored the
      // short way — which is all of them — is refused.
      expect(_errors(_entity(PlatformerEntities.spring)), isEmpty);
    });
  });

  group('a key', () {
    test('must have a colour, because that is what a gate matches on', () {
      expect(_errors(_entity(EntityTypes.key)), contains(contains('"color"')));
      expect(
        _errors(_entity(EntityTypes.key, <String, Object?>{'color': 'blue'})),
        isEmpty,
      );
    });
  });

  group('a one-way platform', () {
    test('thick enough to land inside of is a warning', () {
      // The defect this catches is invisible in the document and obvious in
      // play: a player jumping up through a thick slab is inside it for long
      // enough to be pushed back out sideways.
      expect(
        _warnings(_entity(PlatformerEntities.oneWay, <String, Object?>{
          'size': <double>[4.0, 1.2, 4.0],
        })),
        contains(contains('thick')),
      );
    });

    test('and a thin one is silent', () {
      expect(
        _warnings(_entity(PlatformerEntities.oneWay, <String, Object?>{
          'size': <double>[4.0, 0.3, 4.0],
        })),
        isEmpty,
      );
    });
  });

  group('a conveyor', () {
    test('with no flow is a floor, and is refused as one', () {
      expect(_errors(_entity(PlatformerEntities.conveyor)),
          contains(contains('"flow"')));
    });

    test('with a flow of zero is a warning rather than an error', () {
      // Mutation: return after the first branch without checking the length.
      // A conveyor authored `[0, 0, 0]` — which is what a half-finished one
      // looks like — passes silently.
      expect(
        _warnings(_entity(PlatformerEntities.conveyor, <String, Object?>{
          'flow': <double>[0.0, 0.0, 0.0],
        })),
        contains(contains('flows nowhere')),
      );
    });

    test('and one that flows is silent', () {
      final entity = _entity(PlatformerEntities.conveyor, <String, Object?>{
        'flow': <double>[0.0, 0.0, 3.0],
      });
      expect(_errors(entity), isEmpty);
      expect(_warnings(entity), isEmpty);
    });
  });

  group('a crumbling platform', () {
    test('that gives way instantly is refused', () {
      expect(
        _errors(_entity(
            PlatformerEntities.crumbling, <String, Object?>{'delay': 0.0})),
        contains(contains('gives way')),
      );
    });

    test('and one with a delay is fine', () {
      expect(
        _errors(_entity(
            PlatformerEntities.crumbling, <String, Object?>{'delay': 0.4})),
        isEmpty,
      );
    });
  });

  group('a climbable', () {
    test('shorter than the runner is a warning', () {
      expect(
        _warnings(_entity(PlatformerEntities.climbable, <String, Object?>{
          'size': <double>[1.0, 1.0, 1.0],
        })),
        contains(contains('shorter than the runner')),
      );
    });

    test('and the default is tall enough', () {
      // Mutation: read the size without the default. A ladder authored the
      // short way has no `size`, and `null.y` is either a crash or — with a
      // zero default — a warning on every correct ladder in the game.
      expect(_warnings(_entity(PlatformerEntities.climbable)), isEmpty);
    });
  });

  group('an enemy', () {
    test('must have a route, because standing still is a hazard', () {
      expect(_errors(_entity(PlatformerEntities.enemy)),
          contains(contains('"route"')));
      expect(
        _errors(_entity(PlatformerEntities.enemy,
            <String, Object?>{'route': <Object?>[]})),
        contains(contains('"route"')),
        reason: 'an empty route is no route',
      );
    });

    test('of a kind this game does not have is refused, and named', () {
      // Mutation: accept any string. The level loads, the entity spawns as a
      // patrol, and the author never learns that "flyer" did nothing.
      final errors = _errors(_entity(PlatformerEntities.enemy, <String, Object?>{
        'route': <Object?>[
          <double>[1.0, 0.0, 0.0],
        ],
        'kind': 'flyer',
      }));
      expect(errors, contains(contains('flyer')));
      expect(errors.first, contains('patrol'),
          reason: 'a refusal that does not say what is allowed is a dead end');
    });

    test('and both kinds it does have are silent', () {
      for (final kind in <String>['patrol', 'leaper']) {
        expect(
          _errors(_entity(PlatformerEntities.enemy, <String, Object?>{
            'route': <Object?>[
              <double>[1.0, 0.0, 0.0],
            ],
            'kind': kind,
          })),
          isEmpty,
          reason: kind,
        );
      }
    });
  });

  group('a crate', () {
    test('with no mass is a wall, and is refused as one', () {
      expect(
        _errors(_entity(
            PlatformerEntities.crate, <String, Object?>{'mass': 0.0})),
        contains(contains('a wall')),
      );
    });

    test('and one with mass, or none given, is silent', () {
      expect(_errors(_entity(PlatformerEntities.crate)), isEmpty);
      expect(
        _errors(_entity(
            PlatformerEntities.crate, <String, Object?>{'mass': 40.0})),
        isEmpty,
      );
    });
  });

  test('a breakable block has nothing to check, and says so here', () {
    // `BreakableKind` overrides no `validate`, which is a decision rather than
    // an omission: it has no property that can be wrong. Written down because
    // the guard below would otherwise be satisfied by a kind nobody looked at.
    expect(_errors(_entity(PlatformerEntities.breakable)), isEmpty);
    expect(_warnings(_entity(PlatformerEntities.breakable)), isEmpty);
  });

  test('every kind this package defines is checked above', () {
    // The guard that keeps this file honest as the package grows. A new
    // `EntityKind` with a `validate` nobody tested is exactly the state this
    // file was written to end, and without this it would quietly return.
    //
    // **This package's own kinds, not everything in the registry.** The
    // registry also holds the engine's — a spawn, a door, a lift, an exit —
    // and those are `flutter3d_game`'s to test. A platformer that tested them
    // here would be a platformer asserting things about a shooter.
    //
    // Mutation: add a kind to `platformerRegistry` and not to this list.
    const covered = <String>{
      PlatformerEntities.collectible,
      PlatformerEntities.hazard,
      PlatformerEntities.checkpoint,
      PlatformerEntities.crate,
      PlatformerEntities.spring,
      PlatformerEntities.oneWay,
      PlatformerEntities.conveyor,
      PlatformerEntities.crumbling,
      PlatformerEntities.breakable,
      PlatformerEntities.climbable,
      PlatformerEntities.enemy,
      // Registered by this package with its own kind, though the engine names
      // the type: a key is a key in any game that has doors.
      EntityTypes.key,
    };

    final registered = platformerRegistry().types.toSet();
    final ours = registered.difference(_engineTypes);

    expect(
      ours.difference(covered),
      isEmpty,
      reason: 'these kinds are this package\'s and have no validation test',
    );
    expect(
      covered.difference(registered),
      isEmpty,
      reason: 'these are listed as covered and are not registered at all',
    );
  });
}
