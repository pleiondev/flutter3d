/// Cisterns, proved finishable.
///
///     flutter test test/cisterns_test.dart
///
/// The third level, and the first one whose hazard is a *place* rather than a
/// thing: water, shallow where the lesson is cheap and four metres deep where
/// it is not. What that makes checkable divides in two, the way Ascent's own
/// test divides it.
///
/// **The route** walks the level from the quay to the outflow, fetching the key
/// on the way, and it is a list of places rather than a script — see
/// `climbing.dart`. It goes over the weir and never onto a barge, deliberately:
/// a platform you wait for is something a player times and an autopilot gets
/// lucky on, so the crossing the test proves is the one that holds still.
///
/// **The measurements** are the claims the route cannot make. A bot that walks
/// the weir says nothing about how far apart the stones are — it would walk one
/// with a five-metre gap in it just as happily as this one, right up until the
/// day somebody moved a stone. So the hops are measured against the runner's
/// own numbers, and the deep is asked whether it is still fatal.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'climbing.dart';

const String _cisterns = 'assets/levels/cisterns.json';

/// What the runner measurably does, from `playthrough_test.dart`.
const double _jump = 1.8;
const double _gap = 7.5;

void main() {
  test('the level has no errors in it, and nothing overlaps', () {
    final issues = issuesIn(shippedLevel(_cisterns));

    expect(
      issues
          .where((LevelIssue i) => i.isError)
          .map((LevelIssue i) => i.message),
      isEmpty,
    );
    // Two brushes in one volume z-fight, which is the level flickering. The
    // three levels after Ascent are built to butt rather than overlap, and this
    // is what keeps them that way.
    expect(
      issues
          .map((LevelIssue i) => i.message)
          .where((String m) => m.contains('overlaps')),
      isEmpty,
    );
    // The founding bug of this project: a coin inside a wall looks exactly like
    // a coin nobody has taken yet.
    expect(
      issues
          .map((LevelIssue i) => i.message)
          .where((String m) => m.contains('inside solid geometry')),
      isEmpty,
    );
  });

  test('the weir crosses the deep in hops a runner can make', () {
    // **The claim the route cannot make.** A bot that walks the weir walks
    // whatever is there; what makes the weir a crossing rather than a decoration
    // is that every gap in it is inside a jump, and only arithmetic says so.
    //
    // Mutation: move any stone two metres along z. The gap goes past what the
    // runner clears and this names the pair.
    final level = shippedLevel(_cisterns);
    final stones = <Brush>[
      for (final brush in level.brushes)
        if ((brush.centre.x - 15.0).abs() < 1.0 &&
            brush.centre.z > 80.0 &&
            brush.centre.z < 112.0)
          brush,
    ]..sort((Brush a, Brush b) => a.centre.z.compareTo(b.centre.z));

    expect(
      stones.length,
      greaterThanOrEqualTo(6),
      reason: 'the weir is ${stones.length} stones, which is not a crossing',
    );

    // Both shores count: a weir that starts three metres out from the quay is a
    // weir nobody gets onto.
    var near = 80.0;
    for (final stone in stones) {
      final edge = stone.centre.z - stone.size.z / 2.0;
      expect(
        edge - near,
        lessThan(_gap),
        reason:
            'the hop onto the stone at ${stone.centre.z} is '
            '${(edge - near).toStringAsFixed(2)} m, against $_gap',
      );
      near = stone.centre.z + stone.size.z / 2.0;
    }
    expect(
      112.0 - near,
      lessThan(_gap),
      reason: 'the last stone is ${112.0 - near} m short of the far shore',
    );
  });

  test('the deep is a life and the shallows are not', () {
    // The level's whole difficulty curve in two entities: a player learns the
    // rule where it costs health and meets it where it costs the run.
    //
    // Mutation: give the deep a damage number instead. It stops being a
    // crossing and becomes a swim.
    final level = shippedLevel(_cisterns);
    final water = <String, EntityDef>{
      for (final entity in level.ofType(PlatformerEntities.hazard))
        entity.name ?? '?': entity,
    };

    expect(water['the deep']?.properties['instant'], isTrue);
    expect(water['the spill']?.properties['instant'], isTrue);
    for (final name in <String>['the shallows', 'the race']) {
      final wading = water[name];
      expect(wading, isNotNull, reason: '$name is gone');
      expect(
        wading!.properties['instant'],
        isNot(true),
        reason: '$name kills, and it is the room that teaches the rule',
      );
      // Twenty-two metres of pool at a walk of six is nearly four seconds in
      // it, and health comes back on dying and nowhere else.
      expect(
        wading.number('damage'),
        lessThanOrEqualTo(30.0),
        reason: 'wading $name costs more than a player can afford to learn',
      );
    }
  });

  test('the spillway climbs out one jump at a time', () {
    // Three one-way shelves between the last quay and the gallery, each a metre
    // and a bit over the last. **A one-way platform is the point of the room**:
    // walking straight off the shore goes under the first shelf and into water
    // that kills, and the way up is through them from below.
    //
    // Mutation: raise a shelf by a metre. The climb needs a double jump it was
    // never meant to need, and this says which step.
    final level = shippedLevel(_cisterns);
    final shelves = <EntityDef>[
      for (final entity in level.ofType(PlatformerEntities.oneWay))
        if (entity.position.x.abs() < 1.0) entity,
    ]..sort((EntityDef a, EntityDef b) => a.position.z.compareTo(b.position.z));

    expect(shelves, hasLength(3), reason: 'the shelves are not three');

    var standing = 0.0;
    for (final shelf in shelves) {
      final top = shelf.position.y + (shelf.vector('size')?.y ?? 0.3) / 2.0;
      expect(
        top - standing,
        lessThan(_jump),
        reason:
            'the step onto ${shelf.name} is '
            '${(top - standing).toStringAsFixed(2)} m, and a jump is $_jump',
      );
      standing = top;
    }

    // And the gallery is the last step off them, not a wall above them.
    final gallery = <double>[
      for (final brush in level.brushes)
        if (brush.centre.x.abs() < 1.0 &&
            brush.centre.z > 142.0 &&
            brush.centre.z < 170.0)
          brush.centre.y + brush.size.y / 2.0,
    ].reduce(math.max);
    expect(gallery - standing, lessThan(_jump));
  });

  test('every part of it is behind the one before it', () {
    // The checkpoints are the level's own account of its order, and a post
    // numbered out of step sends a player backwards when they die at it.
    final climb = Climb(_cisterns);
    final posts = climb.posts;

    expect(posts, hasLength(7));
    for (var i = 1; i < posts.length; i++) {
      expect(
        posts[i].at.z,
        greaterThan(posts[i - 1].at.z),
        reason: '${posts[i].name} is behind ${posts[i - 1].name}',
      );
    }
  });

  test('the key can be fetched and the outflow reached', () {
    // **The acceptance for the level.** Places worth being, in order, and the
    // autopilot works out how to get between them. Two of them are not on the
    // walked line: the weir runs up the eastern side and the key sits on an
    // island half way along it.
    final climb = Climb(_cisterns);

    climb.walkThrough(
      <(String, Vector3)>[
        ('the quay', Vector3(0.0, 1.0, -2.0)),
        ('the landing', Vector3(0.0, 1.0, 27.0)),
        ('the sluice', Vector3(0.0, 1.0, 68.0)),
        // In front of the weir rather than at it: a line drawn from the middle of
        // the sluice to the first stone crosses four metres of deep water, and
        // walking a diagonal into a cistern is a death the level did not intend.
        ('the head of the weir', Vector3(15.0, 1.0, 78.0)),
        ('the rust key', climb.named('the rust key')),
        ('the far end of the weir', Vector3(15.0, 1.0, 110.0)),
        // Off the weir along its own line and not on a diagonal. Every waypoint
        // in a cistern is a straight line drawn over water, and the two that were
        // drawn across a corner of the deep both ended the same way: the runner
        // walked off the stones, drowned, came back to the last post and set off
        // along the same diagonal again.
        ('the far shore', Vector3(15.0, 1.0, 116.0)),
        ("the rust gate's plate", climb.named("the rust gate's plate")),
        ('past the gate', Vector3(0.0, 1.0, 128.0)),
        ('the gallery', Vector3(0.0, 5.0, 148.0)),
        ('the outflow', climb.named('the outflow')),
      ],
      finishAt: 'the outflow',
      fetching: 'the rust key',
    );

    expect(
      climb.runner.keys,
      contains('red'),
      reason: 'walked the whole level and never picked the key up',
    );
    expect(climb.sim.state, RunState.finished);
    expect(climb.sim.nextLevel, 'assets/levels/foundry.json');
  });

  test('there is enough in it to be worth playing', () {
    // Not a mechanism, a quantity. A level a hundred and eighty metres long
    // with nine coins in it is an empty field, which is what the first drafts
    // of Ascent were and what playing them looked like.
    final level = shippedLevel(_cisterns);
    expect(
      level.ofType(PlatformerEntities.collectible).length,
      greaterThanOrEqualTo(30),
    );
    expect(
      level.ofType(PlatformerEntities.crate).length,
      greaterThanOrEqualTo(4),
    );
  });
}
