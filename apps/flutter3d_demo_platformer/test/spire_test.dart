/// Spire, proved finishable — and proved to be the end of the game.
///
///     flutter test test/spire_test.dart
///
/// The fifth level and the last one: ten flights over a shaft that kills, with
/// hunters on them. Two things are worth checking here that no earlier level
/// could ask for.
///
/// **The staircase is the level.** Every rise and every gap in it is a number
/// the runner either clears or does not, and there is no ground under any of
/// them to catch a miss — so the whole climb is walked from the document and
/// measured against what the runner measurably does, rather than trusted
/// because a bot got up it once.
///
/// **And it says nothing comes next.** `finale` in the HUD is `nextLevel ==
/// null`, so the credits belong to whichever document has no `next` — which
/// makes "this is the last level" a fact about content that a content change
/// can silently move. `ending_test.dart` walks the chain from the first level;
/// this asks the last one directly.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'climbing.dart';

const String _spire = 'assets/levels/spire.json';

/// What the runner measurably does, from `playthrough_test.dart`.
const double _doubleJump = 3.13;
const double _gap = 7.5;

/// The floors of the climb, lowest first: every brush with a top above the
/// base, on the walked line, read out of the document rather than written down
/// here a second time.
///
/// **`size.z` is in the filter because the far wall is not a flight.** The
/// level's end cap is on the centre line, is wider than any floor and stands
/// forty-two metres tall, so the first version of this picked it up and
/// reported a fourteen-metre step to it. A floor somebody stands on is at
/// least four metres deep; a wall is one.
List<Brush> _flights(Level level) => <Brush>[
  for (final brush in level.brushes)
    if (brush.centre.x.abs() < 4.0 &&
        brush.size.x > 12.0 &&
        brush.size.z >= 4.0 &&
        brush.centre.z > 16.0 &&
        brush.centre.y + brush.size.y / 2.0 > 1.0)
      brush,
]..sort((Brush a, Brush b) => a.centre.z.compareTo(b.centre.z));

/// Where the shaft stops, which is where the climb stops and the summit begins.
double _shaftEnds(Level level) {
  final shaft = level
      .ofType(PlatformerEntities.hazard)
      .firstWhere((EntityDef e) => e.name == 'the shaft');
  return shaft.position.z + shaft.vector('size')!.z / 2.0;
}

void main() {
  test('the level has no errors in it, and nothing overlaps', () {
    final issues = issuesIn(shippedLevel(_spire));

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

  test('every flight is a jump from the one below it', () {
    // **The claim the whole level rests on, and the one a playthrough cannot
    // make.** A bot that gets up this staircase says the staircase can be got
    // up; it says nothing about whether the eighth step is 3.1 m or 3.4, and
    // 3.4 is a level that stops there for ever. There is no ground under any of
    // these to catch a miss, so a step that is a little too big is not a
    // setback, it is a wall.
    //
    // Mutation: raise any flight by a metre, or push one two metres further
    // along. This names the pair and the number.
    final flights = _flights(shippedLevel(_spire));
    expect(
      flights.length,
      greaterThanOrEqualTo(10),
      reason: 'the staircase is ${flights.length} flights',
    );

    var standing = 0.0;
    var edge = 18.0;
    for (final flight in flights) {
      final top = flight.centre.y + flight.size.y / 2.0;
      expect(
        top - standing,
        lessThan(_doubleJump),
        reason:
            'the flight at ${flight.centre.z} is '
            '${(top - standing).toStringAsFixed(2)} m up, against a double '
            'jump of $_doubleJump',
      );
      expect(
        flight.centre.z - flight.size.z / 2.0 - edge,
        lessThan(_gap),
        reason:
            'the flight at ${flight.centre.z} is '
            '${(flight.centre.z - flight.size.z / 2.0 - edge).toStringAsFixed(2)}'
            ' m across, against $_gap',
      );
      standing = top;
      edge = flight.centre.z + flight.size.z / 2.0;
    }
  });

  test('and there is nothing under them but the shaft', () {
    // What makes a miss cost something. **Deliberately `instant` rather than a
    // large damage number**: see `Hazard.instant` on why a drop is not a figure
    // you pick large enough to kill a full-health player.
    //
    // Mutation: put a floor in at y = 0 across the climb. A missed jump becomes
    // a walk back to the bottom, the checkpoints stop meaning anything, and
    // this fails on the first flight it finds ground under.
    final level = shippedLevel(_spire);
    final shaft = level
        .ofType(PlatformerEntities.hazard)
        .firstWhere((EntityDef e) => e.name == 'the shaft');
    expect(shaft.properties['instant'], isTrue);

    // The summit is the one floor of this level that stands on ground rather
    // than over the shaft — it is where the level stops being a climb — so what
    // the shaft has to cover is everything up to and including the crown.
    final size = shaft.vector('size')!;
    final over = _shaftEnds(level);
    final flights = <Brush>[
      for (final flight in _flights(level))
        if (flight.centre.z < over) flight,
    ];
    expect(flights.length, greaterThanOrEqualTo(10));
    expect(
      shaft.position.z - size.z / 2.0,
      lessThanOrEqualTo(flights.first.centre.z - flights.first.size.z / 2.0),
    );
    expect(
      over,
      greaterThanOrEqualTo(flights.last.centre.z + flights.last.size.z / 2.0),
    );

    // Nothing standable between the flights: every brush over the shaft either
    // reaches a flight's own height or is one of the ledges hung off their
    // sides, and none of them sits in a gap on the walked line.
    for (var i = 1; i < flights.length; i++) {
      final from = flights[i - 1].centre.z + flights[i - 1].size.z / 2.0;
      final to = flights[i].centre.z - flights[i].size.z / 2.0;
      final between = <Brush>[
        for (final brush in level.brushes)
          if (brush.centre.x.abs() < 4.0 &&
              brush.centre.z > from &&
              brush.centre.z < to &&
              brush.centre.y + brush.size.y / 2.0 > 0.0)
            brush,
      ];
      expect(
        between,
        isEmpty,
        reason: 'there is a floor in the gap at $from–$to',
      );
    }
  });

  test('the hunters are hunters, and they let go of you', () {
    // **The archetype the navigation grid's jump links were built for**, used
    // where it is the point rather than a nuisance: a patrol holds its own
    // posts and a leaper jumps the gaps in them, and neither can leave the
    // platform it was put on. This one crosses the level to where the player
    // is.
    //
    // What is pinned is that they see less far and forget faster than the
    // defaults. Fourteen metres and three seconds — `EnemyKind`'s figures — on
    // a staircase this narrow is a chase that never ends, and a chase that
    // never ends on a level where standing still is fatal is not difficulty.
    //
    // Mutation: drop `sight` and `patience` from the generator. The defaults
    // come back and this says so.
    final level = shippedLevel(_spire);
    final hunters = <EntityDef>[
      for (final entity in level.ofType(PlatformerEntities.enemy))
        if (entity.string('kind') == 'hunter') entity,
    ];

    expect(
      hunters.length,
      greaterThanOrEqualTo(3),
      reason: 'the last level has ${hunters.length} things that follow',
    );
    for (final hunter in hunters) {
      expect(
        hunter.number('sight'),
        lessThanOrEqualTo(10.0),
        reason: '${hunter.name} sees across the whole flight',
      );
      expect(
        hunter.number('patience'),
        lessThanOrEqualTo(2.0),
        reason: '${hunter.name} never gives up',
      );
      // A hunter holds no route — it asks the level for the way — and a route
      // on one is a list nobody reads.
      expect(hunter.properties['route'], isNull);
    }

    // And they stand on the flights rather than on the landings the checkpoints
    // are on: something waiting exactly where the game told you to rest is the
    // cheap version of this.
    final climb = Climb(_spire);
    for (final hunter in hunters) {
      for (final post in climb.posts) {
        expect(
          (hunter.position.z - post.at.z).abs(),
          greaterThan(2.0),
          reason: '${hunter.name} is standing on ${post.name}',
        );
      }
    }
  });

  test('every part of it is behind the one before it', () {
    final climb = Climb(_spire);
    final posts = climb.posts;

    expect(posts, hasLength(6));
    for (var i = 1; i < posts.length; i++) {
      expect(
        posts[i].at.z,
        greaterThan(posts[i - 1].at.z),
        reason: '${posts[i].name} is behind ${posts[i - 1].name}',
      );
      // And each post is higher than the last, which no earlier level could
      // say: this is the one that climbs. A respawn at y = 0 under a flight
      // eighteen metres up is a runner reborn in the shaft.
      expect(
        posts[i].at.y,
        greaterThanOrEqualTo(posts[i - 1].at.y),
        reason: '${posts[i].name} sends a player back down the tower',
      );
    }
  });

  test('the key can be fetched and the beacon reached', () {
    // **The acceptance for the game.** The last level, walked from the foot of
    // the tower to the light on top of it, past everything that follows.
    final climb = Climb(_spire);
    // The ten over the shaft. The summit is the eleventh floor this finds and
    // it is not walked to directly: the gate stands across the middle of it, so
    // the place worth being there is the plate in front of the gate.
    final over = _shaftEnds(climb.level);
    final flights = <Brush>[
      for (final flight in _flights(climb.level))
        if (flight.centre.z < over) flight,
    ];
    final at = <(String, Vector3)>[
      for (var i = 0; i < flights.length; i++)
        (
          'flight ${i + 1}',
          Vector3(
            flights[i].centre.x,
            flights[i].centre.y + flights[i].size.y / 2.0 + 1.0,
            flights[i].centre.z,
          ),
        ),
    ];

    climb.walkThrough(
      <(String, Vector3)>[
        ('the foot', Vector3(0.0, 1.0, -2.0)),
        ...at.take(4),
        ('the slate key', climb.named('the slate key')),
        // Back onto the landing before going on: the shelf the key is on is a
        // step up off the landing's western side, and the way out of it is the
        // way in.
        ('the first landing again', at[3].$2),
        ...at.skip(4),
        ("the slate gate's plate", climb.named("the slate gate's plate")),
        // Straight from the plate to the beacon, with nothing named in between:
        // the summit is twelve metres deep, the gate stands across the middle of
        // it and the exit is four metres past the gate, so a waypoint between the
        // two would sit inside the volume that ends the level.
        ('the beacon', climb.named('the beacon')),
        // A longer leash than the other levels get, and for a reason that is
        // this level's alone: a missed jump here is a death, and a death is a
        // respawn at the last landing with two flights to climb again.
      ],
      finishAt: 'the beacon',
      fetching: 'the slate key',
      steps: 9000,
    );

    expect(
      climb.runner.keys,
      contains('slate'),
      reason: 'climbed the whole tower and never picked the key up',
    );
    expect(climb.sim.state, RunState.finished);
  });

  test('the gate is a wall with a door in it and no slot over the door', () {
    // **The defect this was written for, and the shape of claim it is allowed
    // to make.** The wall across the summit was eight metres and the door in it
    // was five, with nothing filling the three between the door's head and the
    // wall's top. In the document that reads as an arch. To a runner it reads
    // as a ledge, and an autopilot carrying no key climbed to 26.93 m — against
    // a wall top of 27 — went over the door and finished the game.
    //
    // **What is checked is the wall, not the bot.** Twelve metres of wall was
    // tried and the same autopilot reached 32.9: a wall jump takes any face
    // within fourteen centimetres, there is no height at which it stops and no
    // surface a level can mark as unclimbable, so no wall here seals anything.
    // Ascent's own test says the same about its two gates. A claim that this
    // gate is unavoidable would be a claim a bot can already disprove; a claim
    // that the wall has no hole in it is one the document either keeps or does
    // not.
    //
    // Mutation: delete the lintel, or shorten the side walls to the door's
    // height. The stack over the doorway stops being continuous and this names
    // the gap.
    final level = shippedLevel(_spire);
    final door = level.entities.firstWhere(
      (EntityDef e) => e.name == 'the slate gate',
    );
    final size = door.vector('size')!;
    final floor = door.position.y - size.y / 2.0;
    final across = door.position.z;

    // Every solid thing standing over the doorway, lowest first — the door
    // itself included, because a door is what fills the bottom of the hole.
    final stack = <(double, double)>[
      (floor, floor + size.y),
      for (final brush in level.brushes)
        if ((brush.centre.z - across).abs() < 1.5 &&
            (brush.centre.x - door.position.x).abs() <
                (size.x + brush.size.x) / 2.0 &&
            brush.centre.y > floor)
          (
            brush.centre.y - brush.size.y / 2.0,
            brush.centre.y + brush.size.y / 2.0,
          ),
    ]..sort(((double, double) a, (double, double) b) => a.$1.compareTo(b.$1));

    var sealed = floor;
    for (final (bottom, top) in stack) {
      if (bottom > sealed + 0.01) break;
      sealed = math.max(sealed, top);
    }

    final sides = <double>[
      for (final brush in level.brushes)
        if ((brush.centre.z - across).abs() < 1.5 &&
            (brush.centre.x - door.position.x).abs() >= size.x / 2.0 &&
            brush.centre.y > floor)
          brush.centre.y + brush.size.y / 2.0,
    ];
    expect(sides, isNotEmpty, reason: 'the gate stands in no wall at all');

    expect(
      sealed,
      greaterThanOrEqualTo(sides.reduce(math.max) - 0.01),
      reason:
          'the doorway is filled to $sealed and the wall beside it reaches '
          '${sides.reduce(math.max)}, so there is a slot over the door',
    );

    // And the door has somewhere to go that is not that slot: it sinks into the
    // summit rather than lifting into the stone above it.
    expect(
      door.vector('travel')!.y,
      lessThan(0.0),
      reason: 'the door opens upwards into a lintel it cannot pass through',
    );
  });

  test('it is the last level, and says so by saying nothing', () {
    // `finale` in the HUD is `nextLevel == null`, and that is the whole of how
    // the credits know the game is over.
    //
    // Mutation: give this document a `next`. The ending moves to whatever it
    // names, and the credits stop rolling here.
    final climb = Climb(_spire);
    expect(climb.level.next, isNull);
    expect(climb.sim.nextLevel, isNull);
  });

  test('there is enough in it to be worth playing', () {
    final level = shippedLevel(_spire);
    expect(
      level.ofType(PlatformerEntities.collectible).length,
      greaterThanOrEqualTo(40),
    );
    // Not a claim about scenery: the ledges hung off the flights are the only
    // places in this level that are not the way up, and a coin is the only
    // reason to go to one.
    final ledges = <Brush>[
      for (final brush in level.brushes)
        if (brush.size.y < 1.5 &&
            brush.centre.y > 0.0 &&
            brush.centre.x.abs() > 4.0)
          brush,
    ];
    expect(ledges.length, greaterThanOrEqualTo(8));
    expect(
      ledges.map((Brush b) => b.centre.z).reduce(math.max),
      greaterThan(120.0),
      reason: 'the top half of the tower has nothing beside the stair',
    );
  });
}
