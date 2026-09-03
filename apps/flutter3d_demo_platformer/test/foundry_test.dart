/// Foundry, proved finishable.
///
///     flutter test test/foundry_test.dart
///
/// The fourth level, and the one whose subject is the floor giving way: planks
/// that fall under weight, pads that throw you, lifts that only move when
/// somebody is standing on their plate.
///
/// **What the route walks and what it does not is the whole shape of this
/// file.** A platform that gives way under you is a thing a player *times*, and
/// a bot that crosses one is a bot that got lucky — so both crossings in this
/// level have a way over that holds still, and that is the way the autopilot
/// goes: the catwalk beside the gangway, and the anvils under the gantry. What
/// the planks and the lift get instead are measurements, which is the half a
/// playthrough cannot check and the half that quietly stops being true when
/// somebody moves a brush.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'climbing.dart';

const String _foundry = 'assets/levels/foundry.json';

/// What the runner measurably does, from `playthrough_test.dart`.
const double _jump = 1.8;
const double _gap = 7.5;

void main() {
  test('the level has no errors in it, and nothing overlaps', () {
    final issues = issuesIn(shippedLevel(_foundry));

    expect(
      issues
          .where((LevelIssue i) => i.isError)
          .map((LevelIssue i) => i.message),
      isEmpty,
    );
    expect(
      issues
          .map((LevelIssue i) => i.message)
          .where((String m) => m.contains('overlaps')),
      isEmpty,
    );
    expect(
      issues
          .map((LevelIssue i) => i.message)
          .where((String m) => m.contains('inside solid geometry')),
      isEmpty,
    );
  });

  test('the gangway has somewhere to stand still on', () {
    // **The claim that makes the crumbling planks crossable rather than timed.**
    // A plank holds for as long as somebody is standing on it and then goes;
    // a run of nothing but planks is a run you must not stop on, which is a
    // different and much crueller room than the one this level wanted. So one
    // plate in the middle of the gangway is solid, and the planks either side of
    // it are each within a jump of it.
    //
    // Mutation: make the middle plate crumble too. There is then no rest in
    // sixteen metres of pool and this says so.
    final level = shippedLevel(_foundry);
    final planks = <EntityDef>[
      for (final entity in level.ofType(PlatformerEntities.crumbling)) entity,
    ]..sort((EntityDef a, EntityDef b) => a.position.z.compareTo(b.position.z));

    expect(planks.length, greaterThanOrEqualTo(3));
    for (final plank in planks) {
      // It has to hold for longer than a walk across it: four metres at six
      // metres a second is two thirds of a second.
      expect(
        plank.number('delay') ?? 0.5,
        greaterThan(0.7),
        reason: '${plank.name} gives way before a runner is over it',
      );
      // And come back, or the second attempt is at a pool with no bridge.
      expect(
        plank.number('gone') ?? 2.5,
        greaterThan(0.0),
        reason: '${plank.name} never returns',
      );
    }

    // The rest: a brush on the gangway's own line, between the first plank and
    // the last, at the height they stand at.
    final rests = <Brush>[
      for (final brush in level.brushes)
        if (brush.centre.x.abs() < 1.0 &&
            brush.centre.z > planks.first.position.z &&
            brush.centre.z < planks.last.position.z &&
            brush.centre.y > -1.0 &&
            brush.centre.y < 1.0)
          brush,
    ];
    expect(
      rests,
      isNotEmpty,
      reason: 'there is nowhere on the gangway that holds still',
    );

    // And no plank is more than five metres from something that does not move:
    // the rest in the middle, or one of the two banks. Five rather than the
    // 7.5 m a double jump clears, because a jump you have to make exactly, off
    // a floor that is already going, is not a margin at all — and because at
    // 7.5 the two banks alone satisfy this and deleting the rest would change
    // nothing, which is a check that cannot fail.
    final pour = level
        .ofType(PlatformerEntities.hazard)
        .firstWhere((EntityDef e) => e.name == 'the shallow pour');
    final still = <double>[
      pour.position.z - pour.vector('size')!.z / 2.0,
      pour.position.z + pour.vector('size')!.z / 2.0,
      for (final brush in rests) brush.centre.z,
    ];
    for (final plank in planks) {
      final away = still
          .map((double z) => (plank.position.z - z).abs())
          .reduce(math.min);
      expect(
        away,
        lessThan(5.0),
        reason:
            '${plank.name} is ${away.toStringAsFixed(1)} m from anything '
            'that holds still',
      );
    }
  });

  test('the catwalk crosses the pour without a gap in it', () {
    // The way over that holds still, and the way the route goes. A catwalk with
    // a hole in the middle is a catwalk nobody notices until they are in the
    // metal, because a brush that stops short looks exactly like one that does
    // not from anywhere but underneath.
    //
    // Mutation: shorten it by a metre at either end. The pool it is over is
    // sixteen metres and this measures the shortfall.
    final level = shippedLevel(_foundry);
    final pour = level
        .ofType(PlatformerEntities.hazard)
        .firstWhere((EntityDef e) => e.name == 'the shallow pour');
    final over = pour.vector('size')!.z;
    final along = pour.position.z;

    final plates = <Brush>[
      for (final brush in level.brushes)
        if ((brush.centre.x + 14.0).abs() < 1.0 &&
            brush.centre.y > -1.0 &&
            brush.centre.y < 1.0)
          brush,
    ];
    expect(plates, hasLength(1), reason: 'the catwalk is not one plate');
    expect(
      plates.first.size.z,
      greaterThanOrEqualTo(over),
      reason: 'the catwalk is ${plates.first.size.z} m over $over m of metal',
    );
    expect(plates.first.centre.z, closeTo(along, 0.5));
  });

  test('the anvils cross the tap hole in hops a runner can make', () {
    // The second crossing, and the one over the pit that kills. Measured the
    // way Cisterns measures its weir: both banks count, because a crossing that
    // starts three metres out from the shore is a crossing nobody gets onto.
    //
    // Mutation: take an anvil out. The gap doubles and this names it.
    final level = shippedLevel(_foundry);
    final pit = level
        .ofType(PlatformerEntities.hazard)
        .firstWhere((EntityDef e) => e.name == 'the tap hole');
    final near = pit.position.z - pit.vector('size')!.z / 2.0;
    final far = pit.position.z + pit.vector('size')!.z / 2.0;

    final anvils = <Brush>[
      for (final brush in level.brushes)
        if (brush.centre.x.abs() < 1.0 &&
            brush.centre.z > near &&
            brush.centre.z < far &&
            brush.centre.y + brush.size.y / 2.0 > 0.0)
          brush,
    ]..sort((Brush a, Brush b) => a.centre.z.compareTo(b.centre.z));

    expect(anvils.length, greaterThanOrEqualTo(3));

    var edge = near;
    for (final anvil in anvils) {
      expect(
        anvil.centre.z - anvil.size.z / 2.0 - edge,
        lessThan(_gap),
        reason: 'the hop onto the anvil at ${anvil.centre.z} is too far',
      );
      edge = anvil.centre.z + anvil.size.z / 2.0;
    }
    expect(far - edge, lessThan(_gap), reason: 'the far bank is out of reach');
  });

  test('the mould stair climbs to the key in single jumps', () {
    // The key is on the fourth terrace of a stair, and every step of it is
    // under a single jump on purpose: this level's difficulty is the floor
    // going away, and a climb that also asks for a double jump is a second
    // difficulty nobody put there.
    //
    // Mutation: double a terrace's height. The step goes past a jump and this
    // says which one.
    final level = shippedLevel(_foundry);
    final key = level
        .ofType(EntityTypes.key)
        .firstWhere((EntityDef e) => e.name == 'the amber key');

    final steps = <double>[
      0.0,
      for (final brush in level.brushes)
        if ((brush.centre.x - key.position.x).abs() < brush.size.x / 2.0 &&
            brush.centre.z > 60.0 &&
            brush.centre.z < 90.0 &&
            brush.centre.y > 0.0)
          brush.centre.y + brush.size.y / 2.0,
    ]..sort();

    expect(steps.length, greaterThan(3), reason: 'the stair is not there');
    for (var i = 1; i < steps.length; i++) {
      expect(
        steps[i] - steps[i - 1],
        lessThan(_jump),
        reason:
            'the step from ${steps[i - 1]} to ${steps[i]} is more than a '
            'single jump',
      );
    }
    // And the key stands on the top of it rather than in the air above.
    expect(key.position.y - steps.last, lessThan(_jump));
  });

  test('the lift is worked by standing on something', () {
    // **A gate with no plate in front of it is a gate that never opens**, and a
    // lift with no plate is a lift that never moves: nothing in this genre
    // presses a use key. The lift also has to actually reach the walkway it is
    // there for, which is two numbers agreeing and therefore two numbers that
    // can quietly stop agreeing.
    //
    // Mutation: shorten the lift's travel by two metres. It stops under the
    // gantry and the coins on it become scenery.
    final level = shippedLevel(_foundry);
    final lift = level.entities.firstWhere(
      (EntityDef e) => e.name == 'the charging lift',
    );
    final plates = <EntityDef>[
      for (final entity in level.entities)
        if (entity.string('target') == 'the charging lift') entity,
    ];
    expect(plates, isNotEmpty, reason: 'nothing works the lift');

    final travel = lift.vector('travel')!;
    final deck = lift.position.y + lift.vector('size')!.y / 2.0 + travel.y;
    final gantry = <double>[
      for (final brush in level.brushes)
        if (brush.material == 'wood' && brush.centre.y > 5.0)
          brush.centre.y + brush.size.y / 2.0,
    ];
    expect(gantry, isNotEmpty, reason: 'the gantry is gone');
    expect(
      (gantry.first - deck).abs(),
      lessThan(_jump),
      reason:
          'the lift stops at $deck and the gantry is at ${gantry.first}, '
          'which is not a step',
    );
  });

  test('every part of it is behind the one before it', () {
    final climb = Climb(_foundry);
    final posts = climb.posts;

    expect(posts, hasLength(6));
    for (var i = 1; i < posts.length; i++) {
      expect(
        posts[i].at.z,
        greaterThan(posts[i - 1].at.z),
        reason: '${posts[i].name} is behind ${posts[i - 1].name}',
      );
    }
  });

  test('the key can be fetched and the shipping door reached', () {
    final climb = Climb(_foundry);

    climb.walkThrough(
      <(String, Vector3)>[
        ('the cold floor', Vector3(0.0, 1.0, -4.0)),
        ('the scrap', Vector3(0.0, 1.0, 20.0)),
        // Round the ramp rather than over it: the ledge on top of the ramp is a
        // three-metre face from the south, and walking into one is not a route.
        ('the pour side', Vector3(-9.0, 1.0, 36.0)),
        ('the catwalk', Vector3(-14.0, 1.0, 48.0)),
        ('the mould floor', Vector3(-9.0, 1.0, 60.0)),
        ('the amber key', climb.named('the amber key')),
        ('the tap', Vector3(0.0, 1.0, 100.0)),
        ('the anvils', Vector3(0.0, 1.0, 114.0)),
        ('the gatehouse', Vector3(0.0, 1.0, 128.0)),
        ("the amber gate's plate", climb.named("the amber gate's plate")),
        ('the cooling yard', Vector3(0.0, 1.0, 146.0)),
        ('the shipping door', climb.named('the shipping door')),
      ],
      finishAt: 'the shipping door',
      fetching: 'the amber key',
    );

    expect(
      climb.runner.keys,
      contains('amber'),
      reason: 'walked the whole level and never picked the key up',
    );
    expect(climb.sim.state, RunState.finished);
    expect(climb.sim.nextLevel, 'assets/levels/spire.json');
  });

  test('there is enough in it to be worth playing', () {
    final level = shippedLevel(_foundry);
    expect(
      level.ofType(PlatformerEntities.collectible).length,
      greaterThanOrEqualTo(40),
    );
    expect(
      level.ofType(PlatformerEntities.crate).length,
      greaterThanOrEqualTo(4),
    );
  });
}
