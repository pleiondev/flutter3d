/// The five documents this game ships, and the chain through them.
///
///     flutter test test/levels_test.dart
///
/// **There used to be one level and `next` was empty.** The machinery to move on
/// was written, tested and pointed at nothing. What this file checks is the
/// half a generator cannot: that the chain arrives somewhere, that every
/// document on it loads, and that each one can be stood up in.
///
/// Walked from the level list rather than from a list written here, so a sixth
/// document added to the chain is checked the day it is added.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String _first = 'assets/levels/crypt.json';

Level _read(String path) => Level.fromJson(
  jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
);

/// The chain, from [_first] until something says nothing comes next.
List<({String path, Level level})> _chain() {
  final out = <({String path, Level level})>[];
  final seen = <String>{};
  String? path = _first;
  while (path != null) {
    if (!seen.add(path)) {
      fail('the chain loops: $path is reached twice');
    }
    expect(
      File(path).existsSync(),
      isTrue,
      reason: 'the chain names $path, which is not there',
    );
    final level = _read(path);
    out.add((path: path, level: level));
    path = level.next;
  }
  return out;
}

void main() {
  test('the chain is five levels and ends', () {
    // Ending matters as much as arriving: a last level with a `next` is a game
    // that shows an error screen instead of credits.
    final chain = _chain();

    expect(chain.map((r) => r.path).toList(), <String>[
      'assets/levels/crypt.json',
      'assets/levels/vaults.json',
      'assets/levels/deep.json',
      'assets/levels/cistern.json',
      'assets/levels/sanctum.json',
    ]);
    expect(chain.last.level.next, isNull, reason: 'the last level leads on');
  });

  test('and every document on it is valid against the shipped registry', () {
    // The validator runs against the same registry the game spawns from, so
    // the two cannot disagree about what a document may contain.
    for (final step in _chain()) {
      final issues = LevelValidator(
        registry: sampleRegistry(),
        rules: sampleRules(),
      ).validate(step.level);

      expect(
        issues.where((LevelIssue i) => i.isError),
        isEmpty,
        reason: '${step.path}:\n${issues.join('\n')}',
      );
    }
  });

  // `visibility_test.dart` holds the committed visibility tables fresh; the
  // lightmaps beside the same documents had no such check, and a stale one is
  // dropped at load — a level that quietly loses its bounce light rather than
  // one that fails. Both halves matter: the hash says the bake read these
  // brushes, these lights and these materials, and the size says this build's
  // planner packs them into the atlas the bake wrote. Mutation: flipping any
  // byte of the hash in one `.lightmap.bin` — offsets 20 to 23 — makes the
  // first expectation report false; changing what `LightmapLayout.plan`
  // packs into (the `area * 1.2` the atlas width comes from) makes the
  // second report false without touching the first.
  test('and the lightmap committed beside each was baked from it', () {
    for (final step in _chain()) {
      final side =
          '${step.path.substring(0, step.path.length - 5)}.lightmap.bin';
      final map = Lightmap.fromBytes(File(side).readAsBytesSync());

      expect(
        map.isStaleFor(step.level),
        isFalse,
        reason: '$side: run dart run flutter3d_sim:bake_lightmap',
      );
      final layout = LightmapLayout.plan(
        step.level,
        texelsPerMetre: map.texelsPerMetre,
      );
      expect(
        (layout.width, layout.height),
        (map.width, map.height),
        reason: '$side: the planner and the committed atlas disagree',
      );
    }
  });

  test('and every one can be stood up in, with a way out of it', () {
    // Spawned, not merely parsed. A level whose entities refuse to spawn parses
    // perfectly and is unplayable, which is the failure the registry seam
    // exists to make loud — and it is only loud if somebody spawns.
    for (final step in _chain()) {
      final world = CollisionWorld();
      step.level.addTo(world);
      final staged = stage(
        step.level,
        world,
        input: InputState(),
        registry: sampleRegistry(),
        inventory: startingInventory(),
      );
      world.update();

      expect(
        staged.player.isAlive,
        isTrue,
        reason: '${step.path}: dead on arrival',
      );
      expect(
        staged.mechanisms.all.whereType<Exit>(),
        isNotEmpty,
        reason: '${step.path} has no way out of it',
      );
      expect(
        staged.navIssues.where((LevelIssue i) => i.isError),
        isEmpty,
        reason: '${step.path}: ${staged.navIssues.join('\n')}',
      );
    }
  });

  test('and the way out of each is walkable from where the player lands', () {
    // **The half the previous test cannot ask.** A key on the same level is
    // not a key a player can get to: put the brass key behind the brass door
    // and every check in this file still passes, and the level is unfinishable
    // from the first step.
    //
    // So the locks are honoured. Every door whose key is not held yet is put
    // into the level as a brush and the grid is baked with it standing there;
    // whatever keys are walkable from the spawn are then taken, the doors they
    // open come out, and the grid is baked again. When that stops adding keys,
    // the way out has to be reachable — and if it is not, no order of play
    // reaches it either, because this took every key it could get at each turn.
    for (final (:path, :level) in _chain()) {
      final document =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      final spawn = level.playerStart!.position;
      final exit = level.entities
          .firstWhere((EntityDef e) => e.type == 'exit')
          .position;
      final keys = <(String, Vector3)>[
        for (final key in level.entities.where(
          (EntityDef e) => e.type == EntityTypes.key,
        ))
          if (key.properties['color'] case final String colour)
            (colour, key.position),
      ];

      var held = <String>{};
      var reached = false;
      // One turn per key at most: a turn that opens nothing ends it.
      for (var turn = 0; turn <= keys.length; turn++) {
        final nav = Navigation.bake(_shut(document, held), cellSize: 0.25);
        if (_walkable(nav, spawn, exit)) {
          reached = true;
          break;
        }
        final within = <String>{
          for (final (colour, at) in keys)
            if (_walkable(nav, spawn, at)) colour,
        };
        if (within.length == held.length) break;
        held = within;
      }

      expect(
        reached,
        isTrue,
        reason:
            '$path: nothing walks from the spawn at $spawn to the way out '
            'at $exit, with the keys it can reach ($held) in hand',
      );
    }
  });

  test('and every room reflects itself: a probe per room, standing in air', () {
    // The generator puts a `reflection_probe` at the middle of every room it
    // builds and none in a corridor. What a document can be held to is the
    // half that would go wrong quietly: a probe inside a brush captures the
    // inside of a wall, and something a player reaches for with no probe in
    // reach reflects a sky a crypt does not have. Twelve metres is the far
    // corner of the widest room from its middle, with a little to spare.
    for (final step in _chain()) {
      final probes = step.level.ofType(EntityTypes.reflectionProbe).toList();
      expect(probes, isNotEmpty, reason: '${step.path} reflects nothing');
      for (final probe in probes) {
        expect(
          _solidAt(step.level, probe.position),
          isFalse,
          reason: '${step.path}: a probe at ${probe.position} is inside a wall',
        );
      }
      for (final wanted in step.level.entities.where(
        (EntityDef e) => e.type == EntityTypes.key || e.type == 'pickup',
      )) {
        final nearest = probes
            .map((EntityDef p) => p.position.distanceTo(wanted.position))
            .reduce(math.min);
        expect(
          nearest,
          lessThan(12.0),
          reason:
              '${step.path}: the ${wanted.type} at ${wanted.position} has no '
              'room\'s probe within reach, and reflects nothing',
        );
      }
    }
  });

  test('and every locked door has its key somewhere on the same level', () {
    // **The failure a chain makes possible.** Keys do not carry between levels
    // — deliberately, because a player arriving at the second level holding the
    // third level's key is a designer's promise broken by the plumbing. Which
    // means a door whose key is in the level before it is a level that cannot
    // be finished, and nothing else in this repository would notice.
    for (final step in _chain()) {
      final keys = step.level.entities
          .where((EntityDef e) => e.type == EntityTypes.key)
          .map((EntityDef e) => e.properties['color'])
          .whereType<String>()
          .toSet();
      final locks = step.level.entities
          .where((EntityDef e) => e.type == EntityTypes.door)
          .map((EntityDef e) => e.properties['key'])
          .whereType<String>()
          .toSet();

      expect(
        locks.difference(keys),
        isEmpty,
        reason: '${step.path} locks a door with a key that is not in it',
      );
    }
  });

  test('and the fight gets harder rather than merely longer', () {
    // Not a rule the engine could enforce, and worth writing down anyway: five
    // levels that are the same fight five times is a game with one level in
    // it. Counted by kind, because that is what changes — the crypt has no
    // tanks and the deep is mostly tanks.
    int tanksIn(Level level) => level.entities
        .where(
          (EntityDef e) =>
              e.type == ShooterEntities.monster &&
              e.properties['kind'] == 'tank',
        )
        .length;

    final chain = _chain();
    expect(
      tanksIn(chain.first.level),
      0,
      reason: 'the first level opens with the slowest, hardest thing',
    );
    expect(tanksIn(chain.last.level), greaterThan(1));
  });

  test('nothing a player reads hangs in mid-air', () {
    // **A note is read, not drawn**, so nothing in this game ever put a page
    // where one of these is — and the crypt's sat in the middle of a doorway,
    // two metres from anything, for as long as the level has existed. The
    // editor draws models for the marks now, which is what made it visible.
    //
    // Against a wall means within a hand's width of some solid brush: this is
    // asking "is it on something", not "is it exactly flush".
    //
    // Every document, not only the first: each level opens with a page on the
    // wall by the door, and each one is placed by hand at the wall's own face.
    for (final (:path, :level) in _chain()) {
      for (final note in level.entities.where(
        (EntityDef e) => e.type == 'note',
      )) {
        final at = note.position;
        var nearest = double.infinity;
        for (final brush in level.brushes) {
          if (!brush.solid) continue;
          final dx = math.max(
            (at.x - brush.centre.x).abs() - brush.size.x / 2,
            0.0,
          );
          final dy = math.max(
            (at.y - brush.centre.y).abs() - brush.size.y / 2,
            0.0,
          );
          final dz = math.max(
            (at.z - brush.centre.z).abs() - brush.size.z / 2,
            0.0,
          );
          nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy + dz * dz));
        }
        expect(
          nearest,
          lessThan(0.2),
          reason:
              '$path: the note at $at is ${nearest.toStringAsFixed(2)} m from '
              'the nearest wall, which is a page floating in the air',
        );
      }
    }
  });

  test('and neither does the way out of any of them', () {
    // **The same mistake as the note, in every document at once.** A way
    // out is drawn as an arch two metres and six tall, centred on its own
    // middle; the position was authored as 2.4, 2.4 and 5.0 by eye, so every
    // arch in the game hung one and a tenth metres off the ground. The game
    // never drew one, which is why it survived three levels.
    //
    // Measured against whatever is under it — the crypt's floor, the vault's
    // lift at the top of its travel — rather than against y = 0, because one
    // of the three is a way out you ride up to.
    for (final (:path, :level) in _chain()) {
      for (final exit in level.entities.where((e) => e.type == 'exit')) {
        final at = exit.position;
        final base = at.y - _archHeight / 2.0;

        var floor = double.negativeInfinity;
        for (final brush in level.brushes) {
          if (!brush.solid) continue;
          if ((at.x - brush.centre.x).abs() > brush.size.x / 2) continue;
          if ((at.z - brush.centre.z).abs() > brush.size.z / 2) continue;
          final top = brush.centre.y + brush.size.y / 2;
          if (top > base + 0.05) continue; // a ceiling is not a floor
          floor = math.max(floor, top);
        }
        for (final mover in level.entities.where(
          (e) => e.vector('size') != null && e.vector('travel') != null,
        )) {
          final size = mover.vector('size')!;
          final travel = mover.vector('travel')!;
          if ((at.x - mover.position.x).abs() > size.x / 2) continue;
          if ((at.z - mover.position.z).abs() > size.z / 2) continue;
          final top = mover.position.y + size.y / 2 + math.max(travel.y, 0.0);
          if (top > base + 0.05) continue;
          floor = math.max(floor, top);
        }

        expect(
          base - floor,
          closeTo(0.0, 0.05),
          reason:
              '$path: the way out at $at stands '
              '${(base - floor).toStringAsFixed(2)} m off the floor',
        );
      }
    }
  });
  test('and every door fills the doorway it is set into', () {
    // **A door six metres wide in a hole four metres wide.** The crypt's
    // author widened the locked door deliberately — the comment in
    // `make_crypt.py` explains that a player arriving diagonally gets wedged
    // in a four-metre one — and the widening did nothing for as long as the
    // level existed, because the corridor on the other side cuts the same wall
    // plane at four. Two openings on one plane intersect, so the gap stayed
    // four and a metre of wall stood in front of the door on either side.
    //
    // Neither number is checked here. What is checked is the hole: nothing
    // solid inside the door's own face, and wall immediately beyond its edges.
    // A door that fits is a door whose two numbers agree with the geometry,
    // however either of them was arrived at.
    for (final (:path, :level) in _chain()) {
      for (final door in level.entities.where((e) => e.type == 'door')) {
        final at = door.position;
        final size = door.vector('size')!;
        // The wall's normal is the door's thinnest axis, and the door slides
        // along the other one. Read rather than assumed, so a door set into an
        // east wall is measured the same way as one in a north wall.
        final along = size.x < size.z ? 2 : 0;
        final width = along == 0 ? size.x : size.z;

        var walled = 0;
        for (var i = 1; i < 20; i++) {
          for (var j = 1; j < 20; j++) {
            final point = Vector3.copy(at);
            point.y = at.y - size.y / 2 + size.y * j / 20;
            final u = (along == 0 ? at.x : at.z) - width / 2 + width * i / 20;
            if (along == 0) {
              point.x = u;
            } else {
              point.z = u;
            }
            if (_solidAt(level, point)) walled++;
          }
        }
        expect(
          walled,
          0,
          reason:
              '$path: ${door.name} is a door with wall standing in '
              '$walled of the 361 places its own face covers',
        );

        // And the other way round: a doorway wider than its door is a gap
        // beside it, which is a level a player walks through a locked door in.
        for (final beyond in <Vector3>[
          Vector3.copy(at)
            ..[along] = (along == 0 ? at.x : at.z) - width / 2 - 0.3,
          Vector3.copy(at)
            ..[along] = (along == 0 ? at.x : at.z) + width / 2 + 0.3,
          Vector3.copy(at)..y = at.y + size.y / 2 + 0.3,
        ]) {
          expect(
            _solidAt(level, beyond),
            isTrue,
            reason: '$path: ${door.name} has a gap beside it at $beyond',
          );
        }
      }
    }
  });
}

/// [document] with every door whose key is not in [held] built as a wall.
///
/// A door is an entity and the navigation grid is baked from brushes, so a
/// grid asked about the level as written is a grid with every door wide open.
/// Standing them up as brushes is what makes the routing question the one a
/// player faces.
Level _shut(Map<String, Object?> document, Set<String> held) {
  final doors = (document['entities']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .where((Map<String, Object?> e) => e['type'] == 'door');
  return Level.fromJson(<String, Object?>{
    ...document,
    'brushes': <Object?>[
      ...document['brushes']! as List<Object?>,
      for (final door in doors)
        if (door['key'] case final String key)
          if (!held.contains(key))
            <String, Object?>{
              'at': door['at'],
              'size': door['size'],
              'material': door['material'] ?? 'iron',
            },
    ],
  });
}

/// Whether a body the player's height walks from [from] to [to].
///
/// The field is swept from the destination and read at the start, which is
/// the direction the grid's own height rule is asked in: a ledge that can be
/// dropped off cannot be climbed back up, and a route that only works one way
/// is not one.
///
/// **The player's height, and not the player's width.** `playthrough_test`
/// writes down why it needs two fields to walk the crypt: a grid cell touching
/// a wall has a clearance of one whatever the wall's real distance, so a field
/// asked for the player's 0.35 abandons every corner and, in the deep, the
/// three-metre room with a pillar in it. The narrow field covers those, and
/// the character controller slides along the walls the routes then hug. Asking
/// the wide one here would fail on a level the game ships and a player
/// finishes.
bool _walkable(Navigation nav, Vector3 from, Vector3 to) =>
    (nav.fieldFor(
      radius: 0.0,
      height: 1.8,
    )..rebuild(to)).walkingDistanceTo(from) !=
    null;

/// Whether any solid brush of [level] covers [point].
bool _solidAt(Level level, Vector3 point) {
  for (final brush in level.brushes) {
    if (!brush.solid) continue;
    if ((point.x - brush.centre.x).abs() > brush.size.x / 2) continue;
    if ((point.y - brush.centre.y).abs() > brush.size.y / 2) continue;
    if ((point.z - brush.centre.z).abs() > brush.size.z / 2) continue;
    return true;
  }
  return false;
}

/// How tall the arch a way out is drawn as stands. `tool/cryptkit.py` says the
/// same number, and `tool/make_models.py` builds it.
const double _archHeight = 2.6;
