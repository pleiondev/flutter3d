/// The platformer's five levels: first steps, the ascent, the cisterns, the
/// foundry and the spire.
///
/// **Edit these, not the JSON.** Each function is one level's arrangement and
/// returns its document; `dart run tool/regenerate_levels.dart` from this
/// package writes them, and the files are identical unless something here
/// changed. The vocabulary is `platform_kit.dart`'s.
///
/// The `generatedBy` each document carries is the name its first generator had,
/// kept because it is part of the document and so of the level's digest;
/// `shipped.dart` maps it here.
library;

import 'dart:math' as math;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

import 'platform_kit.dart';

const String _levels = 'apps/flutter3d_demo_platformer/assets/levels';

/// `[a, b, c]` with an index from one, the way the levels number their
/// coins' names.
Iterable<(int, T)> _counted<T>(List<T> items) =>
    items.indexed.map(((int, T) e) => (e.$1 + 1, e.$2));

// MARK: - First steps

/// The level you play first. **A teaching level, and the teaching is the
/// whole design.** Every room shows a verb somewhere it cannot hurt you, and
/// then asks for it somewhere it can: walk, jump, double jump, wall jump,
/// dash, crouch, and then one guard to land on.
///
/// **Nothing here kills.** Every pit has a floor two metres down and a stair
/// back up. The rooms are sized against what the runner measurably does — 1.8
/// m of jump, 3.13 m with both, 7.5 m of gap, 18 m/s of dash — so a gap meant
/// to need a dash is one a double jump genuinely cannot cross.
Map<String, String> firstSteps(GeneratorSource _) {
  const wide = 22.0;
  final k = PlatformKit();

  // The ground under everything, in two levels: the walked floor, and the one
  // two metres below it that catches anybody who misses.
  void room(num z0, num z1) => k.route(
    <num>[0.0, 0.0 - 0.5, (z0 + z1) / 2.0],
    <num>[wide, 1.0, z1 - z0],
    'moss',
  );

  // The floor of a pit, and the stair out of it, butted rather than
  // overlapping: two faces in one plane z-fight.
  void catchPit(num z0, num z1) => k
    ..route(
      <num>[0.0, -2.5, (z0 + z1) / 2.0],
      <num>[wide, 1.0, z1 - z0],
      'stone',
    )
    ..route(<num>[0.0, -1.5, z1 - 2.4], <num>[wide, 1.0, 1.6], 'stone')
    ..route(<num>[0.0, -0.5, z1 - 0.8], <num>[wide, 1.0, 1.6], 'stone');

  // Sides, so a teaching level cannot be walked out of — sixteen metres,
  // because at six the autopilot climbed the chimney and walked off the top
  // of the world. **They cast no shadow**: a band of shade following the
  // player along the wall is not lighting anybody asked for.
  void walls(num z0, num z1) {
    const height = 16.0;
    k
      ..route(
        <num>[-wide / 2 - 0.5, height / 2 - 1.0, (z0 + z1) / 2.0],
        <num>[1.0, height, z1 - z0],
        'stone',
        casts: false,
      )
      ..route(
        <num>[wide / 2 + 0.5, height / 2 - 1.0, (z0 + z1) / 2.0],
        <num>[1.0, height, z1 - z0],
        'stone',
        casts: false,
      );
  }

  const length = (-10.0, 108.0);
  walls(length.$1, length.$2);
  k
    ..route(
      <num>[0.0, 7.0, length.$1 - 0.5],
      <num>[wide + 2, 16.0, 1.0],
      'stone',
      casts: false,
    )
    ..route(
      <num>[0.0, 7.0, length.$2 + 0.5],
      <num>[wide + 2, 16.0, 1.0],
      'stone',
      casts: false,
    );
  k.entities.add(<String, Object?>{
    'type': 'player_spawn',
    'at': <num>[0.0, 0.0, -8.0],
  });

  // Walking. Nothing to do but go forward, and coins to make going forward
  // the obvious thing — and off the straight line, the first reason to look
  // left and right.
  room(-10.0, 8.0);
  for (final (i, z) in _counted(<num>[-4.0, 0.0, 4.0])) {
    k.coin(<num>[0.0, 0.8, z], 'first coin $i');
  }
  for (final (i, (x, z)) in _counted(<(num, num)>[
    (-5.0, -6.0),
    (5.0, -6.0),
    (-7.0, 1.0),
    (7.0, 1.0),
    (-4.0, 6.0),
    (4.0, 6.0),
  ])) {
    k.coin(<num>[x, 0.8, z], 'first stray coin $i');
  }

  // A rise: the first slope is terrain rather than a verb. Its thin end is
  // where a player is walking towards, six metres ahead of the spawn.
  k
    ..slope(<num>[-9.5, 1.0, -1.0], <num>[3.0, 2.0, 6.0], 'stone', '+z')
    ..route(<num>[-9.5, 1.0, 3.0], <num>[3.0, 2.0, 2.0], 'stone')
    ..coin(<num>[-9.5, 2.8, 3.0], 'the coin at the top of the slope')
    // The first crate, where it can do no harm.
    ..crate(<num>[-2.0, 0.7, 2.0], 'the first crate')
    ..crate(<num>[2.0, 0.7, 2.0], 'the second crate')
    ..lamp('the first lamp', <num>[-6.0, 1.0, -2.0])
    ..lamp('the second lamp', <num>[6.0, 1.0, -2.0])
    // Jumping: a gap of three metres, one you cannot fail at.
    ..checkpoint('the first post', 8.0, 1, respawn: 6.0);
  catchPit(8.0, 14.0);
  room(14.0, 24.0);
  k
    ..coin(<num>[0.0, 2.2, 11.0], 'the jump coin')
    ..coin(<num>[-3.5, 2.2, 11.0], 'the jump coin to the left')
    ..coin(<num>[3.5, 2.2, 11.0], 'the jump coin to the right')
    // The first crate worth moving: a coin at 3.4 m is out of reach of both
    // jumps from the floor and easy from the top of a crate.
    ..crate(<num>[-6.0, 0.7, 17.0], 'the crate to stand on')
    ..coin(<num>[-6.0, 3.4, 19.0], 'the coin you need the crate for');
  for (final (i, x) in _counted(<num>[-8.0, -4.0, 4.0, 8.0])) {
    k.coin(<num>[x, 0.8, 15.5], 'landing coin $i');
  }

  // Twice. **Shown before it is asked for**: coins at 2.6 m over open floor,
  // the height of the shelf that is coming; then the shelf, and a step
  // beside it for a player who has not found the second jump yet.
  k
    ..checkpoint('the second post', 22.0, 2, respawn: 21.0)
    ..coin(<num>[0.0, 2.6, 19.0], 'the coin you cannot reach once')
    ..coin(<num>[-4.5, 2.6, 21.0], 'the coin you cannot reach twice')
    ..coin(<num>[4.5, 2.6, 21.0], 'the coin you cannot reach three times')
    ..route(<num>[0.0, 1.3, 26.0], <num>[wide, 2.6, 4.0], 'stone')
    ..route(<num>[9.0, 0.65, 23.0], <num>[4.0, 1.3, 2.0], 'moss')
    ..coin(<num>[0.0, 3.6, 26.0], 'the high coin')
    ..coin(<num>[9.0, 2.0, 23.0], 'the coin on the step');
  catchPit(28.0, 36.0);
  room(36.0, 46.0);
  k
    ..coin(<num>[0.0, 3.0, 32.0], 'the second jump coin')
    ..coin(<num>[-3.5, 3.0, 31.0], 'the coin left of the gap')
    ..coin(<num>[3.5, 3.0, 33.0], 'the coin right of the gap')
    // The shaft, and the floor under it the first version did not have.
    ..checkpoint('the third post', 44.0, 3, respawn: 43.0);
  room(46.0, 58.0);
  // **Two metres apart**, which is a chimney rather than a room: the runner's
  // wall probe reaches 0.14, so a wider slot is one it falls down the middle
  // of. Six tall, because a climb measurably reaches just over seven. The step
  // in the slot is aimed at *finding the way in*: 1.6 m, climbable by
  // somebody who has learned nothing yet, leaving 4.4 m that only a wall jump
  // answers.
  k
    ..route(<num>[-6.0, 3.0, 52.0], <num>[10.0, 6.0, 10.0], 'stone')
    ..route(<num>[6.0, 3.0, 52.0], <num>[10.0, 6.0, 10.0], 'stone')
    ..route(<num>[0.0, 3.0, 57.5], <num>[2.0, 6.0, 1.0], 'stone')
    ..route(<num>[0.0, 0.8, 48.0], <num>[2.0, 1.6, 2.0], 'stone')
    // A ladder of coins: a climb you are paid for at every metre is a climb
    // you keep trying.
    ..coin(<num>[0.0, 1.4, 52.0], 'the shaft coin one')
    ..coin(<num>[0.0, 3.0, 52.0], 'the shaft coin two')
    ..coin(<num>[0.0, 4.4, 52.0], 'the shaft coin three')
    ..coin(<num>[0.0, 5.8, 52.0], 'the shaft coin four')
    // In the room before the shaft, not in it: the shaft room's floor is
    // almost all under the chimney blocks.
    ..crate(<num>[-6.0, 0.7, 42.0], 'the crate before the shaft');
  for (final (i, x) in _counted(<num>[-9.0, -4.0, 4.0, 9.0])) {
    k.coin(<num>[x, 0.8, 46.4], 'shaft floor coin $i');
  }
  // The floor at the top, level with the blocks' tops and not inside the
  // slot, where it was a lid.
  k
    ..route(<num>[0.0, 5.5, 64.0], <num>[wide, 1.0, 12.0], 'stone')
    ..coin(<num>[0.0, 7.0, 62.0], 'the ledge coin')
    // The dash: nine metres, where a double jump crosses seven and a half.
    // Shown first, with a trail of coins along solid ground.
    ..checkpoint('the fourth post', 66.0, 4, respawn: 66.0)
    ..coin(<num>[0.0, 7.0, 68.0], 'the dash coin');
  for (final (i, z) in _counted(<num>[69.5, 70.5, 71.5])) {
    k.coin(<num>[0.0, 7.0, z], 'the dash trail $i');
  }
  k
    ..route(<num>[0.0, 5.5, 84.0], <num>[wide, 1.0, 10.0], 'stone')
    ..coin(<num>[0.0, 8.0, 74.0], 'the gap coin')
    ..coin(<num>[-4.0, 8.0, 74.0], 'the gap coin to the left')
    ..coin(<num>[4.0, 8.0, 74.0], 'the gap coin to the right')
    // Crates come with you.
    ..crate(<num>[7.0, 6.2, 82.0], 'the crate on the far side')
    ..coin(<num>[7.0, 8.9, 84.0], 'the coin above the far crate')
    // A shallow floor under the gap and a stair up: a miss costs seconds.
    ..route(<num>[0.0, 4.0, 74.5], <num>[wide, 1.0, 9.0], 'stone')
    ..route(<num>[0.0, 4.875, 77.0], <num>[wide, 0.75, 2.0], 'stone')
    ..route(<num>[0.0, 5.625, 78.5], <num>[wide, 0.75, 1.0], 'stone')
    // Crouching: a metre of headroom over a floor that carries on. A crouch
    // fits with room to spare and a standing runner does not.
    ..checkpoint('the fifth post', 88.0, 5, respawn: 88.0)
    ..route(<num>[0.0, 9.5, 94.0], <num>[wide, 5.0, 8.0], 'stone')
    ..route(<num>[0.0, 5.5, 96.0], <num>[wide, 1.0, 14.0], 'stone');
  for (final (i, z) in _counted(<num>[91.5, 94.0, 96.5])) {
    k.coin(<num>[0.0, 6.5, z], 'the crawl coin $i');
  }
  k
    ..coin(<num>[-5.0, 6.5, 94.0], 'the crawl coin to the left')
    ..coin(<num>[5.0, 6.5, 94.0], 'the crawl coin to the right')
    // The guard: one thing that walks, across the way out.
    ..enemy(
      'the guard',
      <num>[-6.0, 6.0, 101.0],
      route: <List<num>>[
        <num>[6.0, 6.0, 101.0],
      ],
      speed: 0.3,
    )
    ..coin(<num>[0.0, 6.8, 101.0], "the guard's coin")
    ..coin(<num>[-8.0, 6.8, 100.0], 'the coin the guard walks past')
    ..coin(<num>[8.0, 6.8, 102.0], 'the other coin the guard walks past')
    ..crate(<num>[-8.0, 6.2, 103.0], 'the last crate')
    ..crate(<num>[8.0, 6.2, 103.0], 'the other last crate');
  k.entities.add(<String, Object?>{
    'type': 'exit',
    'name': 'the way on',
    'at': <num>[0.0, 7.5, 104.0],
    'size': <num>[5.0, 3.0, 3.0],
    'text': 'First steps.',
  });

  Map<String, Object?> light(
    List<num> at,
    List<num> colour,
    num intensity,
    num range,
  ) => <String, Object?>{
    'at': at,
    'color': colour,
    'intensity': intensity,
    'range': range,
  };

  return <String, String>{
    '$_levels/first_steps.json': k.write(
      name: 'First Steps',
      lights: <Map<String, Object?>>[
        PlatformKit.sun,
        light(<num>[0.0, 6.0, 0.0], <num>[1.0, 0.94, 0.8], 24.0, 30.0),
        light(<num>[0.0, 6.0, 30.0], <num>[1.0, 0.94, 0.8], 24.0, 32.0),
        light(<num>[0.0, 9.0, 56.0], <num>[0.85, 0.92, 1.0], 26.0, 34.0),
        light(<num>[0.0, 11.0, 76.0], <num>[1.0, 0.9, 0.7], 26.0, 36.0),
        light(<num>[0.0, 11.0, 100.0], <num>[0.9, 1.0, 0.9], 26.0, 34.0),
      ],
      // Where the game goes when this is finished.
      next: 'assets/levels/ascent.json',
      tool: 'tool/make_first_steps.py',
    ),
  };
}

// MARK: - Ascent

/// The second level, and the big one: a hundred and twenty metres by two
/// hundred and sixty-four.
///
/// Two kinds of thing go into it, and the difference matters: the **route** —
/// everything the player's way through is made of and everything the tests
/// name, written out one by one — and the **fill** in between, placed in loops
/// and never allowed onto the ground the route needs (the `clear` list).
///
/// Sizes are chosen against what the runner measurably does: 6 m/s, a 1.8 m
/// jump, 3.13 m with both, about 7.5 m of gap.
Map<String, String> ascent(GeneratorSource _) {
  final k = PlatformKit(
    clear: const <Clear>[
      (-3.0, 3.0, -25.0, 26.0),
      (-5.0, 5.0, 29.0, 51.0),
      (-5.0, 5.0, 51.0, 72.0),
      (-4.0, 4.0, 72.0, 84.0),
      (-28.0, 28.0, 83.0, 121.0),
      (-6.0, 6.0, 121.0, 170.0),
      (-14.0, 14.0, 188.0, 233.0),
      (-52.0, -24.0, -24.0, 4.0),
      (4.0, 11.0, -9.0, -1.0),
      (25.0, 39.0, 1.0, 20.0),
      (-45.0, -31.0, 70.0, 82.0),
    ],
  );

  // Zone one. The yard: moss, a walled crate puzzle, a village.
  k
    ..route(<num>[0.0, -0.5, -2.5], <num>[120.0, 1.0, 55.0], 'moss')
    ..route(<num>[0.0, -0.5, 42.5], <num>[120.0, 1.0, 27.0], 'stone')
    ..route(<num>[0.0, -0.5, 69.5], <num>[120.0, 1.0, 3.0], 'stone')
    ..route(<num>[0.0, -0.5, 96.0], <num>[120.0, 1.0, 50.0], 'wood')
    ..route(<num>[0.0, -0.5, 124.5], <num>[120.0, 1.0, 7.0], 'ice', surface: 'ice')
    ..route(<num>[0.0, -0.5, 156.5], <num>[120.0, 1.0, 21.0], 'ice', surface: 'ice')
    ..route(<num>[0.0, -0.5, 200.0], <num>[120.0, 1.0, 66.0], 'stone')
    ..route(<num>[-60.5, 4.0, 105.0], <num>[1.0, 8.0, 274.0], 'stone')
    ..route(<num>[60.5, 4.0, 105.0], <num>[1.0, 8.0, 274.0], 'stone')
    ..route(<num>[0.0, 4.0, -30.5], <num>[122.0, 8.0, 1.0], 'stone')
    ..route(<num>[0.0, 4.0, 233.5], <num>[122.0, 8.0, 1.0], 'stone')
    ..spawn(<num>[0.0, 0.0, -22.0])
    ..coin(<num>[0.0, 0.8, -16.0], 'coin one')
    ..coin(<num>[-3.0, 0.8, -11.0], 'coin two')
    ..coin(<num>[3.0, 0.8, -11.0], 'coin three')
    ..crate(<num>[7.0, 0.0, -4.0], 'the crate')
    ..crate(<num>[8.8, 0.0, -4.0], 'the other crate')
    // The walled yard, and the vault above it. The ledge is 4.2: over a
    // double jump and under a crate plus a double jump, which is the puzzle.
    ..route(<num>[-50.5, 2.3, -10.0], <num>[1.0, 4.6, 25.0], 'stone')
    ..route(<num>[-38.5, 2.3, 2.5], <num>[25.0, 4.6, 1.0], 'stone')
    ..route(<num>[-38.5, 2.3, -22.5], <num>[25.0, 4.6, 1.0], 'stone')
    ..route(<num>[-25.5, 2.3, -19.25], <num>[1.0, 4.6, 6.5], 'stone')
    ..route(<num>[-25.5, 2.3, -4.75], <num>[1.0, 4.6, 14.5], 'stone')
    ..route(<num>[-46.0, 2.1, -10.0], <num>[8.0, 4.2, 25.0], 'stone')
    ..route(<num>[-33.0, 2.3, -14.75], <num>[1.0, 4.6, 15.5], 'wood')
    ..route(<num>[-37.0, 2.3, -0.75], <num>[1.0, 4.6, 6.5], 'wood')
    ..crate(<num>[-29.0, 0.0, -19.0], 'the yard crate')
    ..crate(<num>[-31.0, 0.0, -19.0], 'the second yard crate')
    ..crate(<num>[-30.0, 0.0, -21.0], 'the spare yard crate')
    ..coin(<num>[-29.0, 0.8, -13.0], 'yard coin one')
    ..coin(<num>[-35.0, 0.8, -6.0], 'yard coin two')
    ..coin(<num>[-40.0, 0.8, -12.0], 'yard coin three');
  for (final (i, z) in _counted(<num>[-18.0, -14.0, -6.0, -2.0])) {
    k.coin(<num>[-46.0, 5.0, z], 'vault coin $i');
  }
  k
    ..key('the green key', <num>[-46.0, 5.2, -10.0], 'green')
    // The east plateau, with its own stair up — and a way up it that is
    // walked rather than jumped, up the western face, where the field is
    // solid (against the northern face its foot hung over the drop).
    ..route(<num>[-30.0, 2.0, 18.0], <num>[12.0, 4.0, 12.0], 'stone')
    ..route(<num>[32.0, 3.0, 8.0], <num>[12.0, 6.0, 12.0], 'stone')
    ..route(<num>[32.0, 1.0, 16.5], <num>[8.0, 2.0, 5.0], 'stone')
    ..slope(<num>[20.0, 3.0, 5.0], <num>[12.0, 6.0, 6.0], 'stone', '+x')
    ..route(<num>[-8.0, 0.9, 22.0], <num>[3.0, 0.4, 2.4], 'brass')
    ..route(<num>[8.0, 0.9, 22.0], <num>[3.0, 0.4, 2.4], 'brass')
    ..coin(<num>[32.0, 6.8, 4.0], 'plateau coin one')
    ..coin(<num>[28.0, 6.8, 8.0], 'plateau coin two')
    ..coin(<num>[36.0, 6.8, 8.0], 'plateau coin three')
    ..spring('the high pad', <num>[32.0, 6.2, 11.0])
    ..coin(<num>[32.0, 11.0, 11.0], 'plateau coin four')
    ..spring('the first pad', <num>[-30.0, 4.2, 18.0], speed: 16.0)
    ..coin(<num>[-30.0, 10.0, 18.0], 'high coin')
    ..checkpoint('the brink', 20.0, 1, respawn: 18.0)
    ..coin(<num>[0.0, 2.0, 24.0], 'arc coin one')
    ..coin(<num>[0.0, 3.0, 27.0], 'arc coin two')
    ..coin(<num>[0.0, 2.0, 30.0], 'arc coin three')
    ..hazard(
      'the first drop',
      <num>[0.0, -4.0, 27.0],
      <num>[122.0, 6.0, 4.0],
      instant: true,
    )
    ..checkpoint('past the drop', 33.0, 2, respawn: 34.0);

  // The village: twelve huts with a coin on every roof and planks between
  // them, because a roof you cannot get to has a coin nobody will ever have.
  const xs = <num>[24.0, 33.0, 42.0, 51.0];
  for (final (row, z) in <num>[-26.0, -18.0, -10.0].indexed) {
    final heights = row.isEven
        ? const <num>[3.0, 5.6, 4.2, 6.4]
        : const <num>[5.2, 3.4, 6.0, 4.4];
    for (var i = 0; i < 4; i++) {
      k.hut(xs[i], z, heights[i]);
    }
    for (var i = 0; i < 3; i++) {
      final low = math.min(heights[i], heights[i + 1]);
      k.plank((xs[i] + xs[i + 1]) / 2, z, true, 9.0 - 7.0 + 2.0, low);
    }
  }
  for (final x in xs) {
    k.crate(<num>[x, 0.0, -22.0]);
  }

  // Stepping stones out to the eastern corner.
  for (final (i, x) in <num>[42.0, 48.0, 54.0].indexed) {
    for (final (j, z) in <num>[2.0, 8.0, 14.0, 20.0].indexed) {
      k.pillar(
        x,
        z,
        1.0 + ((i + j) % 4) * 0.8,
        width: 3.0,
        topCoin: (i + j).isEven,
      );
    }
  }

  // The western colonnade. **The cap goes on, then the coin goes on the
  // cap**: a top coin under a roof is a coin inside the roof.
  for (var i = 0; i < 7; i++) {
    final z = -26.0 + i * 8.0;
    final capped = i.isEven;
    k.pillar(-57.0, z, 5.0, width: 2.6, topCoin: !capped);
    if (capped) {
      k
        ..fill(<num>[-57.0, 5.6, z], <num>[4.0, 0.6, 4.0], 'wood')
        ..coin(<num>[-57.0, 6.7, z]);
    }
  }

  // The training ground: a grid of stumps to hop across.
  for (final (i, x) in <num>[-22.0, -17.0, -12.0, -7.0].indexed) {
    for (final (j, z) in <num>[-26.0, -20.0, -14.0, -8.0].indexed) {
      k.pillar(
        x,
        z,
        0.8 + ((i * 3 + j) % 5) * 0.6,
        width: 3.2,
        topCoin: (i + j).isEven,
      );
    }
  }

  // The ruin: two arches, a spike pit and a pad to clear it with.
  for (final x in <num>[13.0, 19.0]) {
    k
      ..fill(<num>[x, 3.0, -26.0], <num>[1.6, 6.0, 1.6], 'stone')
      ..fill(<num>[x, 3.0, -18.0], <num>[1.6, 6.0, 1.6], 'stone');
  }
  k
    ..fill(<num>[16.0, 6.3, -26.0], <num>[8.0, 0.6, 1.6], 'stone')
    ..fill(<num>[16.0, 6.3, -18.0], <num>[8.0, 0.6, 1.6], 'stone')
    ..coin(<num>[16.0, 7.4, -26.0])
    ..coin(<num>[16.0, 7.4, -18.0])
    ..hazard(
      'the ruin spikes',
      <num>[16.0, 0.4, -22.0],
      <num>[8.0, 0.8, 5.0],
      damage: 35.0,
    )
    ..spring('the ruin pad', <num>[16.0, 0.2, -13.0], speed: 14.0)
    ..coin(<num>[16.0, 5.0, -13.0]);

  // The yard of surfaces, off the route: a platform you pass through, a floor
  // that slides, a floor that carries.
  for (final (i, y) in <num>[1.6, 3.0, 4.4].indexed) {
    k
      ..oneway(
        'the gantry ${i + 1}',
        <num>[14.0 + i * 1.5, y, 10.0],
        size: const <num>[6.0, 0.3, 6.0],
      )
      ..coin(<num>[14.0 + i * 1.5, y + 1.0, 10.0]);
  }
  k
    // Under the lowest one, so the only way out is down through it.
    ..coin(<num>[14.0, 0.8, 10.0])
    // A rink, and a kerb so an overshoot stops rather than skates on.
    ..fill(<num>[-14.0, 0.05, 8.0], <num>[16.0, 0.1, 16.0], 'ice', surface: 'ice')
    ..fill(<num>[-14.0, 1.0, 16.5], <num>[16.0, 2.0, 1.0], 'stone')
    ..coin(<num>[-18.0, 0.9, 12.0])
    ..coin(<num>[-10.0, 0.9, 12.0])
    // The belts run north, clear of the walled yard: entities do not go
    // through the clear list, and a belt once delivered into a fence.
    ..conveyor(
      'the first belt',
      <num>[-44.0, 0.2, 13.0],
      <num>[0.0, 0.0, 5.0],
      size: const <num>[4.0, 0.4, 14.0],
    )
    ..conveyor(
      'the second belt',
      <num>[-39.0, 0.2, 13.0],
      <num>[0.0, 0.0, -5.0],
      size: const <num>[4.0, 0.4, 14.0],
    )
    ..coin(<num>[-44.0, 0.9, 19.0])
    ..coin(<num>[-39.0, 0.9, 7.0])
    // A crawlspace: the slot is one metre, a crouched runner 0.9.
    ..fill(<num>[7.0, 2.0, 14.0], <num>[7.0, 1.9, 7.0], 'stone')
    ..coin(<num>[7.0, 0.6, 14.0])
    ..coin(<num>[7.0, 3.9, 14.0])
    // The first things that walk, at a third of walking pace, on the moss.
    ..enemy(
      'the first guard',
      <num>[-10.0, 0.0, -4.0],
      route: <List<num>>[
        <num>[-10.0, 0.0, -20.0],
      ],
      speed: 0.32,
    )
    ..coin(<num>[-10.0, 0.8, -22.0])
    ..enemy(
      'the second guard',
      <num>[30.0, 0.0, -6.0],
      route: <List<num>>[
        <num>[44.0, 0.0, -6.0],
      ],
      speed: 0.42,
    );

  // The north strip: broken walls with coins behind them — except the one
  // that lands on the hut at (-30, 18).
  for (var i = 0; i < 6; i++) {
    final x = -54.0 + i * 8.0;
    k.fill(<num>[x, 1.2, 16.0], <num>[6.0, 2.4, 1.0], 'stone');
    if ((x - -30.0).abs() > 0.5) k.coin(<num>[x, 0.8, 18.5]);
  }

  // Zone two: the shaft, the quarry, the scaffold and the canyon.
  k
    ..route(<num>[-3.5, 6.0, 44.0], <num>[1.0, 12.0, 10.0], 'stone')
    ..route(<num>[3.5, 6.0, 44.0], <num>[1.0, 12.0, 10.0], 'stone')
    ..route(<num>[0.0, 4.0, 48.5], <num>[8.0, 8.0, 1.0], 'stone')
    ..route(<num>[-7.0, 4.0, 44.0], <num>[6.0, 8.0, 10.0], 'stone')
    ..route(<num>[7.0, 4.0, 44.0], <num>[6.0, 8.0, 10.0], 'stone')
    ..coin(<num>[0.0, 3.0, 44.0], 'the shaft coin')
    ..coin(<num>[0.0, 6.0, 42.0], 'the second shaft coin')
    ..coin(<num>[0.0, 9.0, 42.0], 'the third shaft coin')
    ..key('the blue key', <num>[0.0, 9.0, 46.0], 'blue')
    ..checkpoint('the canyon rim', 53.0, 3, respawn: 52.0)
    ..hazard(
      'the gulf',
      <num>[0.0, -4.0, 62.0],
      <num>[122.0, 6.0, 12.0],
      instant: true,
    )
    ..mover(
      'platform',
      'the first barge',
      <num>[-8.0, 1.0, 58.0],
      <num>[5.0, 0.6, 5.0],
      <num>[16.0, 0.0, 0.0],
      3.5,
      1.2,
    )
    ..mover(
      'platform',
      'the second barge',
      <num>[8.0, 1.0, 62.0],
      <num>[5.0, 0.6, 5.0],
      <num>[-16.0, 0.0, 0.0],
      3.5,
      1.2,
      phase: 2.5,
    )
    ..mover(
      'platform',
      'the third barge',
      <num>[-8.0, 1.0, 66.0],
      <num>[5.0, 0.6, 5.0],
      <num>[16.0, 0.0, 0.0],
      3.5,
      1.2,
      phase: 5.0,
    )
    ..coin(<num>[0.0, 3.0, 58.0], 'canyon coin one')
    ..coin(<num>[0.0, 3.0, 62.0], 'canyon coin two')
    ..coin(<num>[0.0, 3.0, 66.0], 'canyon coin three');

  // Two more ways across, so the canyon is a canyon rather than a doorway.
  for (final (side, x) in const <(String, num)>[('west', -30.0), ('east', 30.0)]) {
    k
      ..mover(
        'platform',
        'the $side ferry',
        <num>[x, 1.0, 59.0],
        <num>[4.5, 0.6, 4.5],
        <num>[0.0, 0.0, 8.0],
        3.0,
        1.2,
        phase: 1.5,
      )
      ..mover(
        'platform',
        'the $side skiff',
        <num>[x, 1.0, 67.0],
        <num>[4.5, 0.6, 4.5],
        <num>[x < 0 ? 8.0 : -8.0, 0.0, 0.0],
        3.0,
        1.0,
        phase: 3.0,
      )
      ..coin(<num>[x, 2.6, 59.0])
      ..coin(<num>[x, 2.6, 67.0]);
    // Columns out of the depths, tall enough to stand on and no taller.
    for (final z in <num>[60.0, 64.0]) {
      k
        ..fill(<num>[x + 10.0, -2.0, z], <num>[3.0, 6.0, 3.0], 'stone')
        ..coin(<num>[x + 10.0, 1.8, z]);
    }
  }

  // The quarry: terraces stepping up, with crates and a pad at the top.
  for (var i = 0; i < 6; i++) {
    final x = -54.0 + i * 8.0;
    final h = 1.2 + i * 0.9;
    k
      ..fill(<num>[x, h / 2, 40.0], <num>[7.0, h, 18.0], 'stone')
      ..coin(<num>[x, h + 0.8, 36.0])
      ..coin(<num>[x, h + 0.8, 44.0]);
  }
  for (final x in <num>[-52.0, -44.0, -36.0]) {
    k.crate(<num>[x, 0.0, 31.0]);
  }
  k
    ..spring('the quarry pad', <num>[-14.0, 6.0, 40.0], speed: 16.0)
    ..fill(<num>[-14.0, 2.9, 40.0], <num>[5.0, 5.8, 5.0], 'stone')
    ..coin(<num>[-14.0, 12.0, 40.0]);

  // The scaffold: platforms at three heights with movers between them.
  for (final (i, x) in <num>[16.0, 28.0, 40.0, 52.0].indexed) {
    for (final (j, z) in <num>[34.0, 44.0, 52.0].indexed) {
      final h = 2.0 + ((i + j) % 3) * 2.0;
      k
        ..fill(<num>[x, h - 0.3, z], <num>[7.0, 0.6, 7.0], 'wood')
        ..fill(<num>[x, (h - 0.6) / 2, z], <num>[1.0, h - 0.6, 1.0], 'stone')
        ..coin(<num>[x, h + 0.8, z]);
    }
  }
  k
    ..mover(
      'platform',
      'the scaffold hoist',
      <num>[22.0, 2.0, 48.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 4.0, 0.0],
      2.0,
      1.5,
    )
    ..mover(
      'platform',
      'the scaffold shuttle',
      <num>[46.0, 3.0, 39.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 0.0, 10.0],
      2.5,
      1.0,
      phase: 1.0,
    )
    // Zone three: the forecourt, the maze, and two wings of filling.
    ..route(<num>[-40.0, 3.5, 76.0], <num>[8.0, 7.0, 8.0], 'wood')
    ..route(<num>[-31.0, 4.0, 80.0], <num>[58.0, 8.0, 2.0], 'wood')
    ..route(<num>[31.0, 4.0, 80.0], <num>[58.0, 8.0, 2.0], 'wood')
    ..checkpoint('the forecourt', 72.0, 4, respawn: 73.0)
    ..mover(
      'lift',
      'the tower lift',
      <num>[-34.0, 0.3, 76.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 7.0, 0.0],
      2.0,
      4.0,
    )
    ..plate('the lift plate', 'the tower lift', <num>[-34.0, 1.6, 76.0])
    ..coin(<num>[-42.0, 7.8, 74.0], 'tower coin one')
    ..coin(<num>[-38.0, 7.8, 74.0], 'tower coin two')
    ..coin(<num>[-42.0, 7.8, 78.0], 'tower coin three')
    ..coin(<num>[-38.0, 7.8, 78.0], 'tower coin four')
    // Eight metres of wooden wall and a five-metre door: the lintel is three.
    ..gate(
      'the blue gate',
      <num>[0.0, 2.5, 80.0],
      'blue',
      lintel: 8.0,
      material: 'wood',
    )
    ..plate(
      "the blue gate's plate",
      'the blue gate',
      <num>[0.0, 1.6, 77.0],
      size: const <num>[6.0, 3.0, 3.0],
    )
    // The maze. Five metres tall: over a double jump, so it is not scenery.
    ..route(<num>[-27.5, 2.5, 102.0], <num>[1.0, 5.0, 37.0], 'stone')
    ..route(<num>[27.5, 2.5, 102.0], <num>[1.0, 5.0, 37.0], 'stone');
  for (final z in <num>[83.5, 114.0, 120.5]) {
    k
      ..route(<num>[-15.25, 2.5, z], <num>[24.5, 5.0, 1.0], 'stone')
      ..route(<num>[15.25, 2.5, z], <num>[24.5, 5.0, 1.0], 'stone');
  }
  for (final (z, x) in const <(num, num)>[
    (90.0, -3.0),
    (96.0, 3.0),
    (102.0, -3.0),
    (108.0, 3.0),
  ]) {
    k.route(<num>[x, 2.5, z], <num>[49.0, 5.0, 1.0], 'stone');
  }
  // Stubs inside the rows: without them a serpentine is a corridor.
  for (final (z, x) in const <(num, num)>[
    (87.0, 8.0),
    (93.0, -8.0),
    (99.0, 8.0),
    (105.0, -8.0),
    (111.0, 14.0),
  ]) {
    k.route(<num>[x, 2.5, z], <num>[1.0, 5.0, 3.6], 'stone');
  }
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-24.0, 87.0),
    (24.0, 87.0),
    (-24.0, 99.0),
    (24.0, 99.0),
    (-24.0, 111.0),
    (24.0, 111.0),
    (0.0, 93.0),
    (0.0, 105.0),
    (0.0, 117.0),
  ])) {
    k.lamp('the maze lamp $i', <num>[x, 2.2, z]);
  }
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-24.0, 87.0),
    (-18.0, 87.0),
    (12.0, 87.0),
    (24.0, 93.0),
    (18.0, 93.0),
    (-24.0, 99.0),
    (-18.0, 99.0),
    (24.0, 105.0),
    (18.0, 105.0),
    (-24.0, 111.0),
    (24.0, 111.0),
    (-24.0, 117.0),
    (24.0, 117.0),
  ])) {
    k.coin(<num>[x, 0.8, z], 'maze coin $i');
  }
  // The maze's walls and this door are both five metres: nothing to fill,
  // and said out loud, because a gate with no lintel is a gate nobody checked.
  k
    ..gate(
      'the green gate',
      <num>[0.0, 2.5, 120.5],
      'green',
      size: const <num>[6.0, 5.0, 2.0],
      lintel: 5.0,
    )
    ..plate(
      "the green gate's plate",
      'the green gate',
      <num>[0.0, 1.6, 118.0],
      size: const <num>[6.0, 3.0, 3.0],
    );

  // The forecourt filling: pillars, crates and a second tower with a lift.
  for (final (i, x) in <num>[-54.0, -22.0, -12.0, 12.0, 22.0, 54.0].indexed) {
    k
      ..pillar(x, 74.0, 4.0 + (i % 3), width: 3.0)
      ..crate(<num>[x < 0 ? x + 4.0 : x - 4.0, 0.0, 74.0]);
  }
  k
    ..fill(<num>[40.0, 3.5, 76.0], <num>[8.0, 7.0, 8.0], 'wood')
    ..mover(
      'lift',
      'the east lift',
      <num>[34.0, 0.3, 76.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 7.0, 0.0],
      2.0,
      4.0,
    )
    ..plate('the east plate', 'the east lift', <num>[34.0, 1.6, 76.0]);
  for (final dx in <num>[-2.0, 2.0]) {
    for (final dz in <num>[-2.0, 2.0]) {
      k.coin(<num>[40.0 + dx, 7.8, 76.0 + dz]);
    }
  }
  k
    // A leaper: it jumps the gaps in its own route.
    ..enemy(
      'the leaper',
      <num>[-16.0, 0.0, 74.0],
      route: <List<num>>[
        <num>[8.0, 0.0, 74.0],
      ],
      kind: 'leaper',
      speed: 0.45,
    )
    // A saw on an arm: a hazard riding a mover.
    ..mover(
      'platform',
      'the saw arm',
      <num>[20.0, 3.4, 76.0],
      <num>[2.0, 0.4, 2.0],
      <num>[0.0, 0.0, 9.0],
      3.5,
      0.6,
    )
    ..hazard(
      'the saw',
      <num>[20.0, 4.4, 76.0],
      <num>[1.8, 1.8, 1.8],
      damage: 55.0,
    );
  k.entities.last['follows'] = 'the saw arm';
  k
    // Above the plank, not inside it.
    ..coin(<num>[20.0, 8.8, 80.0])
    // A ladder to the gallery, and a rope over the drop beside it.
    ..climbable(
      'the gallery ladder',
      <num>[48.0, 4.0, 88.0],
      size: const <num>[1.2, 8.0, 1.2],
    )
    ..coin(<num>[48.0, 8.8, 88.0])
    ..climbable(
      'the rope',
      <num>[52.0, 6.0, 104.0],
      size: const <num>[1.0, 10.0, 1.0],
      swing: 3.5,
      period: 2.6,
    )
    ..coin(<num>[56.0, 10.0, 104.0]);

  // The warehouse, west of the maze: twelve crates, sheds, a gantry.
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 3; j++) {
      k.crate(<num>[-54.0 + i * 4.0, 0.0, 90.0 + j * 5.0]);
    }
  }
  for (final z in <num>[86.0, 98.0, 110.0]) {
    k
      ..fill(<num>[-36.0, 2.5, z], <num>[8.0, 5.0, 8.0], 'stone')
      ..coin(<num>[-36.0, 6.3, z]);
  }
  k.fill(<num>[-45.0, 5.0, 104.0], <num>[22.0, 0.6, 4.0], 'wood');
  for (var i = 0; i < 5; i++) {
    k.coin(<num>[-54.0 + i * 4.5, 6.0, 104.0]);
  }
  for (var i = 0; i < 3; i++) {
    final h = 1.4 + i * 1.4;
    k.fill(<num>[-33.0, h / 2, 116.0 - i * 4.0], <num>[5.0, h, 4.0], 'stone');
  }

  // The east gallery: a stair to a walkway along the maze's outer wall.
  for (var i = 0; i < 5; i++) {
    final h = 1.6 + i * 1.4;
    k
      ..fill(<num>[32.0, h / 2, 86.0 + i * 7.0], <num>[6.0, h, 6.0], 'stone')
      ..coin(<num>[32.0, h + 0.8, 86.0 + i * 7.0]);
  }
  k.fill(<num>[42.0, 8.0, 102.0], <num>[4.0, 0.6, 36.0], 'wood');
  for (var i = 0; i < 6; i++) {
    k.coin(<num>[42.0, 9.2, 86.0 + i * 6.0]);
  }
  for (var i = 0; i < 4; i++) {
    k.pillar(52.0, 88.0 + i * 9.0, 3.0 + i * 1.2, width: 3.4);
  }

  // Zone four. The ice: a crevasse with five ways across and spikes beyond.
  k
    ..checkpoint('the cold', 124.0, 5)
    ..hazard(
      'the crevasse',
      <num>[0.0, -4.0, 137.0],
      <num>[122.0, 6.0, 18.0],
      instant: true,
    )
    ..mover(
      'platform',
      'the ferry',
      <num>[0.0, 1.0, 131.0],
      <num>[5.0, 0.6, 5.0],
      <num>[0.0, 0.0, 13.0],
      3.0,
      1.5,
    )
    ..mover(
      'platform',
      'the west floe',
      <num>[-14.0, 1.0, 134.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 0.0, 8.0],
      2.5,
      1.0,
      phase: 1.0,
    )
    ..mover(
      'platform',
      'the east floe',
      <num>[14.0, 1.0, 142.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 0.0, -8.0],
      2.5,
      1.0,
      phase: 3.0,
    )
    ..coin(<num>[-14.0, 2.6, 134.0], 'floe coin one')
    ..coin(<num>[-14.0, 2.6, 142.0], 'floe coin two')
    ..coin(<num>[14.0, 2.6, 134.0], 'floe coin three')
    ..coin(<num>[14.0, 2.6, 142.0], 'floe coin four');
  for (final (side, x) in const <(String, num)>[
    ('far west', -34.0),
    ('far east', 34.0),
  ]) {
    k
      ..mover(
        'platform',
        'the $side floe',
        <num>[x, 1.0, 132.0],
        <num>[4.5, 0.6, 4.5],
        <num>[0.0, 0.0, 10.0],
        2.5,
        1.2,
        phase: 2.0,
      )
      ..coin(<num>[x, 2.6, 132.0])
      ..fill(<num>[x + 8.0, -2.0, 137.0], <num>[3.4, 6.4, 3.4], 'ice')
      ..coin(<num>[x + 8.0, 2.0, 137.0]);
  }
  // A bridge of shelves, each holding for under half a second.
  for (final (i, z) in _counted(<num>[129.0, 133.0, 137.0, 141.0, 145.0])) {
    k.crumbling('the shelf $i', <num>[-24.0, 0.8, z]);
  }
  k
    ..coin(<num>[-24.0, 1.8, 137.0])
    // The staircase to the cold pad, three steps with margin on every climb:
    // 2.0 off the ice, then 2.2, then 1.8. Its first step was once above
    // anything a double jump could reach.
    ..route(<num>[0.0, 1.0, 144.5], <num>[12.0, 2.0, 3.0], 'ice')
    ..route(<num>[0.0, 2.1, 148.0], <num>[12.0, 4.2, 3.0], 'ice')
    ..route(<num>[0.0, 3.0, 152.0], <num>[12.0, 6.0, 4.0], 'ice')
    ..route(<num>[-22.0, 1.5, 162.0], <num>[12.0, 3.0, 8.0], 'ice')
    ..route(<num>[22.0, 1.5, 162.0], <num>[12.0, 3.0, 8.0], 'ice')
    ..hazard('the spikes', <num>[-9.0, 0.4, 150.0], <num>[10.0, 0.8, 8.0])
    ..hazard('more spikes', <num>[9.0, 0.4, 158.0], <num>[10.0, 0.8, 8.0])
    ..hazard(
      'the far spikes',
      <num>[-30.0, 0.4, 154.0],
      <num>[14.0, 0.8, 8.0],
      damage: 35.0,
    )
    ..hazard(
      'the eastern spikes',
      <num>[30.0, 0.4, 154.0],
      <num>[14.0, 0.8, 8.0],
      damage: 35.0,
    )
    ..spring('the cold pad', <num>[0.0, 6.2, 152.0], speed: 17.0)
    ..coin(<num>[0.0, 12.5, 156.0], 'the cold coin')
    ..coin(<num>[-22.0, 3.8, 162.0], 'ice coin one')
    ..coin(<num>[22.0, 3.8, 162.0], 'ice coin two');

  // The near shore, and the ridges beyond the spikes.
  for (var i = 0; i < 7; i++) {
    final x = -48.0 + i * 16.0;
    if (x.abs() < 8.0) continue;
    k.pillar(x, 123.5, 1.4 + (i % 3) * 0.9, width: 4.0, material: 'ice');
  }
  for (final x in <num>[-46.0, -26.0, 26.0, 46.0]) {
    k
      ..fill(<num>[x, 1.5, 150.0], <num>[10.0, 3.0, 1.2], 'ice')
      ..fill(<num>[x, 1.5, 158.0], <num>[10.0, 3.0, 1.2], 'ice')
      ..coin(<num>[x, 4.2, 150.0])
      ..coin(<num>[x, 4.2, 158.0]);
  }
  for (final x in <num>[-44.0, 44.0]) {
    k
      ..spring(
        'the floe pad ${x < 0 ? 'west' : 'east'}',
        <num>[x, 0.2, 164.0],
        speed: 15.0,
      )
      ..coin(<num>[x, 5.5, 164.0]);
  }
  for (final x in <num>[-16.0, 16.0]) {
    k
      ..crate(<num>[x, 0.0, 148.0])
      ..crate(<num>[x, 0.0, 160.0]);
  }

  // Zone five. The summit — earned with the two verbs this level otherwise
  // never asks for, the wall jump and the dash, in a fenced corridor (the
  // fences cast no shadow).
  k.checkpoint('past the ice', 170.0, 6);
  for (final x in <num>[-13.0, 13.0]) {
    k.route(<num>[x, 5.0, 181.0], <num>[2.0, 12.0, 28.0], 'stone', casts: false);
  }
  // The chimney: **two metres**, measured, because the wall probe reaches
  // fourteen centimetres.
  for (final x in <num>[-6.5, 6.5]) {
    k.route(<num>[x, 3.5, 180.0], <num>[11.0, 7.0, 8.0], 'stone');
  }
  k
    ..route(<num>[0.0, 3.5, 184.5], <num>[2.0, 7.0, 1.0], 'stone')
    ..coin(<num>[0.0, 2.0, 180.0], 'the chimney coin one')
    ..coin(<num>[0.0, 5.0, 180.0], 'the chimney coin two')
    // And the dash, from the top of the chimney: nine metres measured from
    // the chimney's closing wall, not from the blocks. Nothing under the gap:
    // a miss drops onto the ground and costs the climb, not the run.
    ..coin(<num>[0.0, 8.2, 186.0], 'the dash coin')
    ..route(<num>[0.0, 6.5, 197.5], <num>[24.0, 1.0, 6.0], 'stone')
    ..coin(<num>[0.0, 8.5, 190.0], 'the coin over the gap')
    ..checkpoint('the foot of the stair', 190.0, 7)
    ..route(<num>[0.0, 1.2, 196.0], <num>[26.0, 2.4, 8.0], 'stone')
    ..route(<num>[0.0, 2.5, 206.0], <num>[22.0, 5.0, 8.0], 'stone')
    ..route(<num>[0.0, 3.8, 216.0], <num>[18.0, 7.6, 8.0], 'stone')
    ..route(<num>[0.0, 5.1, 226.0], <num>[14.0, 10.2, 8.0], 'stone')
    ..coin(<num>[0.0, 3.2, 196.0], 'stair coin one')
    ..spring('the last pad', <num>[9.0, 2.6, 196.0])
    ..coin(<num>[9.0, 8.0, 196.0], 'stair coin two')
    ..coin(<num>[0.0, 5.8, 206.0], 'stair coin three')
    ..coin(<num>[0.0, 8.4, 216.0], 'stair coin four')
    ..mover(
      'lift',
      'the summit lift',
      <num>[-12.0, 0.3, 214.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 7.0, 0.0],
      2.0,
      4.0,
    )
    ..plate('the summit plate', 'the summit lift', <num>[-12.0, 1.6, 214.0]);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (4.0, 226.0),
    (2.8, 228.8),
    (0.0, 230.0),
    (-2.8, 228.8),
    (-4.0, 226.0),
    (-2.8, 223.2),
    (0.0, 222.0),
    (2.8, 223.2),
  ])) {
    k.coin(<num>[x, 11.0, z], 'ring coin $i');
  }
  k.exitAt('the summit', <num>[0.0, 11.7, 226.0], 'The summit.');

  // The colonnade below the stair.
  for (var i = 0; i < 6; i++) {
    final z = 172.0 + i * 4.0;
    for (final x in <num>[-18.0, 18.0]) {
      k.pillar(x, z, 6.0, width: 2.4, topCoin: i.isEven);
    }
    k.coin(<num>[0.0, 0.8, z]);
  }
  for (var i = 0; i < 5; i++) {
    final x = -52.0 + i * 8.0;
    k
      ..pillar(x, 176.0, 2.0 + i * 0.8, width: 4.0)
      ..pillar(-x, 176.0, 2.0 + i * 0.8, width: 4.0);
  }
  // A gap of nine and a half metres beside the path: a long jump out of a
  // slide clears it, a double jump does not.
  k
    ..fill(<num>[-30.0, 1.0, 172.0], <num>[7.0, 2.0, 7.0], 'stone')
    ..fill(<num>[-30.0, 1.0, 185.0], <num>[7.0, 2.0, 7.0], 'stone')
    ..coin(<num>[-30.0, 3.0, 185.0])
    ..coin(<num>[-30.0, 3.0, 188.0]);

  // A cap of blocks over a pocket of coins: nothing but a pound gets through.
  const capAt = 30.0;
  for (final (i, dx) in _counted(<num>[-2.0, 0.0, 2.0])) {
    k.breakable(
      'the cap $i',
      <num>[capAt + dx, 3.6, 164.0],
      size: const <num>[2.0, 1.2, 4.0],
    );
  }
  k
    ..fill(<num>[capAt - 4.0, 1.5, 164.0], <num>[2.0, 3.0, 6.0], 'stone')
    ..fill(<num>[capAt + 4.0, 1.5, 164.0], <num>[2.0, 3.0, 6.0], 'stone')
    ..fill(<num>[capAt, 1.5, 167.5], <num>[10.0, 3.0, 1.0], 'stone')
    ..fill(<num>[capAt, 1.5, 160.5], <num>[10.0, 3.0, 1.0], 'stone')
    ..coin(<num>[capAt, 0.8, 164.0])
    ..coin(<num>[capAt - 2.0, 0.8, 164.0])
    ..coin(<num>[12.0, 0.8, 176.0])
    // Two ziggurats flanking the stair, and lifts up the outer walls.
    ..ziggurat(-34.0, 208.0, 4, 2.4, 20.0)
    ..ziggurat(34.0, 208.0, 4, 2.4, 20.0);
  for (final x in <num>[-50.0, 50.0]) {
    final side = x < 0 ? 'west' : 'east';
    k
      ..mover(
        'lift',
        'the $side hoist',
        <num>[x, 0.3, 196.0],
        <num>[4.0, 0.6, 4.0],
        <num>[0.0, 8.0, 0.0],
        2.0,
        4.0,
      )
      ..plate('the $side hoist plate', 'the $side hoist', <num>[x, 1.6, 196.0])
      ..fill(<num>[x, 4.0, 204.0], <num>[8.0, 8.0, 8.0], 'stone')
      ..coin(<num>[x, 8.8, 204.0])
      ..fill(<num>[x, 8.3, 212.0], <num>[8.0, 0.6, 8.0], 'wood')
      ..coin(<num>[x, 9.4, 212.0]);
  }
  // The back wall, so the summit has something behind it.
  for (var i = 0; i < 9; i++) {
    final x = -48.0 + i * 12.0;
    if (x.abs() < 20.0) continue;
    k
      ..fill(<num>[x, 2.0, 230.0], <num>[8.0, 4.0, 4.0], 'stone')
      ..coin(<num>[x, 5.2, 230.0]);
  }

  return <String, String>{
    '$_levels/ascent.json': k.write(
      name: 'Ascent',
      lights: <Map<String, Object?>>[
        // Back at an angle that casts: the renderer has cascades now.
        PlatformKit.sun,
        for (final (x, y, z, colour, range) in const <(num, num, num, List<num>, num)>[
          (0.0, 7.0, -12.0, <num>[0.6, 0.75, 1.0], 46.0),
          (-38.0, 7.0, -10.0, <num>[1.0, 0.85, 0.6], 34.0),
          (36.0, 8.0, -18.0, <num>[1.0, 0.85, 0.6], 40.0),
          (0.0, 9.0, 44.0, <num>[1.0, 0.8, 0.55], 40.0),
          (-30.0, 8.0, 40.0, <num>[1.0, 0.86, 0.62], 44.0),
          (34.0, 8.0, 44.0, <num>[1.0, 0.86, 0.62], 44.0),
          (0.0, 9.0, 62.0, <num>[0.8, 0.85, 1.0], 44.0),
          (0.0, 7.0, 78.0, <num>[1.0, 0.86, 0.62], 40.0),
          (0.0, 8.0, 96.0, <num>[1.0, 0.9, 0.7], 46.0),
          (0.0, 8.0, 114.0, <num>[1.0, 0.9, 0.7], 46.0),
          (-42.0, 8.0, 100.0, <num>[1.0, 0.88, 0.66], 44.0),
          (42.0, 9.0, 100.0, <num>[1.0, 0.88, 0.66], 44.0),
          (0.0, 8.0, 137.0, <num>[0.7, 0.9, 1.0], 48.0),
          (0.0, 8.0, 155.0, <num>[0.7, 0.9, 1.0], 42.0),
          (0.0, 8.0, 178.0, <num>[0.95, 0.95, 1.0], 46.0),
          (0.0, 14.0, 214.0, <num>[0.9, 1.0, 0.95], 50.0),
        ])
          <String, Object?>{
            'at': <num>[x, y, z],
            'color': colour,
            'intensity': 26.0,
            'range': range,
          },
      ],
      // What a finished level does next is a line in the document, so the
      // ending moves by moving this.
      next: 'assets/levels/cisterns.json',
      tool: 'tool/make_level.py',
    ),
  };
}

// MARK: - Cisterns

/// The third level, and the wet one. **Water is the hazard, and how deep it
/// is is the difficulty**: the wading pool costs a little health, the race
/// under the belts more, and the great cistern is deep, and deep water is a
/// life. Three ways across it, because a crossing with one way over is a
/// doorway: the pilings, a barge along either side, and the weir — the one the
/// tests walk, because a moving platform is something an autopilot gets lucky
/// on.
Map<String, String> cisterns(GeneratorSource _) {
  const w = 40.0;
  const length = (-14.0, 170.0);
  final k = PlatformKit(
    clear: const <Clear>[
      (-4.0, 4.0, -14.0, 170.0),
      (12.0, 18.0, 78.0, 114.0),
      (-12.0, -6.0, 78.0, 114.0),
      (5.0, 11.0, 78.0, 114.0),
      (-5.0, 5.0, 2.0, 24.0),
    ],
  );

  // Dry floor, top at nought.
  void quay(num z0, num z1) => k.route(
    <num>[0.0, -0.5, (z0 + z1) / 2.0],
    <num>[w, 1.0, z1 - z0],
    'stone',
  );

  // A floor below the waterline and the water over it. [damage] is what
  // wading costs a second; none is a drowning. The bed is moss: weed.
  void basin(String name, num z0, num z1, num depth, {num? damage}) => k
    ..route(
      <num>[0.0, -depth - 0.5, (z0 + z1) / 2.0],
      <num>[w, 1.0, z1 - z0],
      'moss',
    )
    ..hazard(
      name,
      <num>[0.0, -depth / 2.0, (z0 + z1) / 2.0],
      <num>[w, depth, z1 - z0],
      damage: damage,
      instant: damage == null,
    );

  // A stepping stone rising out of a basin whose bed is at [floor].
  void stone(num x, num z, num floor, {num top = 0.4, num width = 3.0}) =>
      k.route(
        <num>[x, (floor + top) / 2.0, z],
        <num>[width, top - floor, width],
        'stone',
      );

  // The walls, fourteen metres, casting no shadow.
  for (final x in <num>[-w / 2 - 0.5, w / 2 + 0.5]) {
    k.route(
      <num>[x, 6.0, (length.$1 + length.$2) / 2.0],
      <num>[1.0, 14.0, length.$2 - length.$1],
      'stone',
      casts: false,
    );
  }
  for (final z in <num>[length.$1 - 0.5, length.$2 + 0.5]) {
    k.route(<num>[0.0, 6.0, z], <num>[w + 2.0, 14.0, 1.0], 'stone', casts: false);
  }

  // The quay.
  quay(length.$1, 2.0);
  k.spawn(<num>[0.0, 0.0, -10.0]);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-3.0, -6.0),
    (3.0, -6.0),
    (0.0, -2.0),
  ])) {
    k.coin(<num>[x, 0.8, z], 'quay coin $i');
  }
  k
    ..lamp('the quay lamp west', <num>[-8.0, 1.0, -8.0])
    ..lamp('the quay lamp east', <num>[8.0, 1.0, -8.0])
    ..checkpoint('the quay', 0.0, 1, respawn: -2.0);

  // The wading pool. **Fifteen a second rather than twenty**: 3.7 s in the
  // water at twenty is three quarters of a runner's health, for the room
  // whose whole job is to teach that water hurts.
  basin('the shallows', 2.0, 24.0, 1.2, damage: 15.0);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (0.0, 5.5),
    (-3.0, 10.0),
    (3.0, 14.5),
    (0.0, 19.0),
  ])) {
    stone(x, z, -1.2);
    k.coin(<num>[x, 1.2, z], 'stone coin $i');
  }

  // The landing, and the first thing that walks.
  quay(24.0, 40.0);
  k
    ..checkpoint('the landing', 27.0, 2, respawn: 26.0)
    ..enemy(
      'the warden',
      <num>[-8.0, 0.0, 34.0],
      route: <List<num>>[
        <num>[8.0, 0.0, 34.0],
      ],
      speed: 0.35,
    )
    ..coin(<num>[0.0, 0.8, 34.0], "the warden's coin");
  for (final x in <num>[-14.0, 14.0]) {
    k
      ..hut(x, 32.0, 3.6, width: 6.0)
      ..crate(<num>[x, 0.0, 37.5]);
  }

  // The belt hall. **Decks a quarter of a metre clear of the waterline**, so
  // whether a passenger touches the water is not a question about the
  // broadphase's comparisons.
  basin('the race', 40.0, 64.0, 1.0, damage: 30.0);
  k
    ..conveyor(
      'the slow belt',
      <num>[0.0, 0.0, 52.0],
      <num>[0.0, 0.0, -3.5],
      size: const <num>[5.0, 0.5, 24.0],
    )
    ..conveyor(
      'the west belt',
      <num>[-7.0, 0.0, 52.0],
      <num>[0.0, 0.0, 4.0],
      size: const <num>[5.0, 0.5, 24.0],
    )
    ..conveyor(
      'the east belt',
      <num>[7.0, 0.0, 52.0],
      <num>[0.0, 0.0, 4.0],
      size: const <num>[5.0, 0.5, 24.0],
    );
  for (final (i, z) in _counted(<num>[44.0, 48.0, 52.0, 56.0, 60.0])) {
    k.coin(<num>[0.0, 0.8, z], 'belt coin $i');
  }
  for (final z in <num>[46.0, 58.0]) {
    k
      ..coin(<num>[-7.0, 0.8, z])
      ..coin(<num>[7.0, 0.8, z]);
  }

  // The sluice.
  quay(64.0, 80.0);
  k
    ..checkpoint('the sluice', 67.0, 3, respawn: 66.0)
    ..lamp('the sluice lamp', <num>[0.0, 1.0, 70.0]);
  for (final x in <num>[-15.0, -10.0]) {
    k.crate(<num>[x, 0.0, 72.0]);
  }
  k
    ..pillar(-15.0, 77.0, 2.6, width: 3.0)
    ..pillar(15.0, 68.0, 3.4, width: 3.0)
    // A post at the head of the weir, off the centre line: a checkpoint also
    // says which way the level is walked from here, and this one says
    // "along the stones" rather than diagonally across deep water.
    ..checkpoint('the head of the weir', 78.0, 4, respawn: 78.0, x: 15.0);

  // The great cistern: four metres deep, and three ways across.
  basin('the deep', 80.0, 112.0, 4.0);
  for (final (i, z) in <num>[84.0, 90.0, 96.0, 102.0, 108.0].indexed) {
    stone(0.0, z, -4.0);
    if (i.isEven) k.coin(<num>[0.0, 1.2, z], 'piling coin ${i ~/ 2 + 1}');
  }
  // The barges: named, and not on the tested route.
  k
    ..mover(
      'platform',
      'the west barge',
      <num>[-9.0, -0.3, 83.0],
      <num>[5.0, 0.6, 5.0],
      <num>[0.0, 0.0, 26.0],
      3.5,
      1.5,
    )
    ..mover(
      'platform',
      'the east barge',
      <num>[8.0, -0.3, 83.0],
      <num>[5.0, 0.6, 5.0],
      <num>[0.0, 0.0, 26.0],
      3.5,
      1.5,
      phase: 4.0,
    )
    ..coin(<num>[-9.0, 1.4, 96.0], 'the west barge coin')
    ..coin(<num>[8.0, 1.4, 96.0], 'the east barge coin');
  // The weir: **a metre** of water between stones, inside the runner's step,
  // so walking works — at a metre and a half a walker clipped the next face.
  const weirX = 15.0;
  for (final z in <num>[84.0, 88.0, 92.0, 100.0, 104.0, 108.0]) {
    stone(weirX, z, -4.0, width: 3.0);
  }
  k
    ..route(<num>[weirX, -1.8, 96.0], <num>[5.0, 4.4, 5.0], 'stone')
    ..key('the rust key', <num>[weirX, 1.4, 96.0], 'red')
    ..coin(<num>[weirX, 1.2, 88.0], 'weir coin one')
    ..coin(<num>[weirX, 1.2, 104.0], 'weir coin two');

  // The far shore.
  quay(112.0, 130.0);
  k
    ..checkpoint('the far shore', 114.0, 5, respawn: 114.0)
    ..enemy(
      'the second warden',
      <num>[-6.0, 0.0, 118.0],
      route: <List<num>>[
        <num>[6.0, 0.0, 118.0],
      ],
      speed: 0.4,
    );
  for (final x in <num>[-13.0, 13.0]) {
    k.pillar(x, 116.0, 2.0, width: 3.0);
  }
  // The rust gate, across the whole width, and its plate in front of it.
  for (final x in <num>[-12.0, 12.0]) {
    k.route(<num>[x, 3.0, 124.0], <num>[16.0, 6.0, 2.0], 'stone');
  }
  k
    ..gate(
      'the rust gate',
      <num>[0.0, 2.5, 124.0],
      'red',
      size: const <num>[8.0, 5.0, 2.0],
      lintel: 6.0,
    )
    ..plate(
      "the rust gate's plate",
      'the rust gate',
      <num>[0.0, 1.6, 121.0],
      size: const <num>[6.0, 3.0, 3.0],
    )
    ..lamp('the gate lamp west', <num>[-6.0, 1.0, 122.0])
    ..lamp('the gate lamp east', <num>[6.0, 1.0, 122.0])
    // The spillway: deep water, and the way over it is up, through shelves
    // a walk straight off the shore goes under.
    ..checkpoint('the spillway', 128.0, 6, respawn: 127.0);
  basin('the spill', 130.0, 142.0, 4.0);
  const shelves = <(num, num)>[(132.0, 1.2), (136.0, 2.4), (140.0, 3.6)];
  for (final (i, (z, y)) in _counted(shelves)) {
    k
      ..oneway('the shelf $i', <num>[0.0, y, z], size: const <num>[6.0, 0.3, 4.0])
      ..coin(<num>[0.0, y + 1.0, z], 'shelf coin $i');
  }
  for (final (i, (z, y)) in _counted(shelves)) {
    k
      ..oneway(
        'the side shelf $i',
        <num>[-12.0, y, z],
        size: const <num>[6.0, 0.3, 4.0],
      )
      ..coin(<num>[-12.0, y + 1.0, z]);
  }

  // The gallery, four metres up, and the exit at the end of it.
  k
    ..route(<num>[0.0, 2.0, 156.0], <num>[w, 4.0, 28.0], 'stone')
    ..checkpoint('the gallery', 144.0, 7, respawn: 144.0, y: 4.0)
    ..climbable(
      'the bell rope',
      <num>[10.0, 7.0, 150.0],
      size: const <num>[1.0, 6.0, 1.0],
      swing: 3.0,
      period: 2.6,
    )
    ..coin(<num>[13.0, 10.0, 150.0], 'the bell coin')
    ..enemy(
      'the keeper',
      <num>[-5.0, 4.0, 160.0],
      route: <List<num>>[
        <num>[5.0, 4.0, 160.0],
      ],
      speed: 0.4,
    );
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-4.0, 148.0),
    (4.0, 148.0),
    (0.0, 156.0),
  ])) {
    k.coin(<num>[x, 4.8, z], 'gallery coin $i');
  }
  for (final x in <num>[-14.0, 14.0]) {
    // **Standing on the gallery, not through it**: a column on a terrace
    // starts at the terrace.
    k
      ..crate(<num>[x, 4.0, 158.0])
      ..fill(<num>[x, 5.25, 165.0], <num>[3.0, 2.5, 3.0], 'stone')
      ..coin(<num>[x, 7.3, 165.0]);
  }
  k.exitAt('the outflow', <num>[0.0, 4.7, 165.0], 'The cisterns drain.');

  return <String, String>{
    '$_levels/cisterns.json': k.write(
      name: 'Cisterns',
      lights: <Map<String, Object?>>[
        PlatformKit.sun,
        for (final (at, colour, range) in const <(List<num>, List<num>, num)>[
          (<num>[0.0, 6.0, -6.0], <num>[0.7, 0.9, 1.0], 36.0),
          (<num>[0.0, 6.0, 14.0], <num>[0.6, 0.9, 0.9], 40.0),
          (<num>[0.0, 6.0, 32.0], <num>[1.0, 0.9, 0.7], 36.0),
          (<num>[0.0, 6.0, 52.0], <num>[0.6, 0.9, 0.9], 44.0),
          (<num>[0.0, 6.0, 72.0], <num>[1.0, 0.9, 0.7], 36.0),
          (<num>[0.0, 7.0, 96.0], <num>[0.5, 0.85, 1.0], 50.0),
          (<num>[0.0, 7.0, 118.0], <num>[1.0, 0.9, 0.7], 40.0),
          (<num>[0.0, 8.0, 136.0], <num>[0.6, 0.9, 0.9], 40.0),
          (<num>[0.0, 10.0, 156.0], <num>[0.9, 1.0, 0.95], 44.0),
        ])
          PlatformKit.pointLight(at, colour, range: range),
      ],
      fog: const <num>[0.04, 0.09, 0.10],
      density: 0.006,
      next: 'assets/levels/foundry.json',
      tool: 'tool/make_cisterns.py',
    ),
  };
}

// MARK: - Foundry

/// The fourth level: hot metal, which is water that is worse. Its verbs are
/// shown in the scrap yard where nothing is over anything hot, then asked for
/// over the pours: the catwalk, the gangway of planks that give, the ladle,
/// and the tap hole, which is not a number.
Map<String, String> foundry(GeneratorSource _) {
  const w = 44.0;
  const length = (-14.0, 178.0);
  final k = PlatformKit(
    clear: const <Clear>[
      (-5.0, 5.0, -14.0, 178.0),
      (-18.0, -10.0, 17.0, 32.0),
      (9.0, 19.0, 21.0, 31.0),
      (-18.0, -10.0, 39.0, 57.0),
      (10.0, 19.0, 39.0, 57.0),
      (-19.0, -3.0, 62.0, 88.0),
      (-22.0, -7.0, 95.0, 127.0),
      (-9.0, 9.0, 128.0, 137.0),
    ],
  );

  // Dry floor, top at nought.
  void deck(num z0, num z1) => k.route(
    <num>[0.0, 0.0 - 0.5, (z0 + z1) / 2.0],
    <num>[w, 1.0, z1 - z0],
    'stone',
  );

  // A floor sunk below a pool of hot metal, and the pool over it. No
  // [damage] is a tap hole: see `Hazard.instant`.
  void melt(String name, num z0, num z1, num depth, {num? damage}) => k
    ..route(
      <num>[0.0, -depth - 0.5, (z0 + z1) / 2.0],
      <num>[w, 1.0, z1 - z0],
      'stone',
    )
    ..hazard(
      name,
      <num>[0.0, -depth / 2.0, (z0 + z1) / 2.0],
      <num>[w, depth, z1 - z0],
      damage: damage,
      instant: damage == null,
    );

  // The walls: sixteen metres, because the gantry stands at nine.
  for (final x in <num>[-w / 2 - 0.5, w / 2 + 0.5]) {
    k.route(
      <num>[x, 7.0, (length.$1 + length.$2) / 2.0],
      <num>[1.0, 16.0, length.$2 - length.$1],
      'stone',
      casts: false,
    );
  }
  for (final z in <num>[length.$1 - 0.5, length.$2 + 0.5]) {
    k.route(<num>[0.0, 7.0, z], <num>[w + 2.0, 16.0, 1.0], 'stone', casts: false);
  }

  // The cold floor.
  deck(length.$1, 14.0);
  k.spawn(<num>[0.0, 0.0, -10.0]);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (0.0, -6.0),
    (-4.0, -2.0),
    (4.0, -2.0),
  ])) {
    k.coin(<num>[x, 0.8, z], 'cold floor coin $i');
  }
  k
    ..lamp('the door lamp west', <num>[-9.0, 1.0, -8.0])
    ..lamp('the door lamp east', <num>[9.0, 1.0, -8.0])
    ..checkpoint('the cold floor', -4.0, 1, respawn: -6.0);
  for (final x in <num>[-17.0, 17.0]) {
    k
      ..hut(x, 2.0, 3.4, width: 6.0)
      ..crate(<num>[x, 0.0, 8.0]);
  }

  // The scrap: a ramp you walk up, a cap you pound through, a pad that
  // throws you — nothing over anything hot.
  deck(14.0, 40.0);
  k
    ..checkpoint('the scrap', 16.0, 2, respawn: 15.0)
    ..slope(<num>[-14.0, 1.5, 22.0], <num>[6.0, 3.0, 8.0], 'stone', '+z')
    ..route(<num>[-14.0, 1.5, 28.0], <num>[6.0, 3.0, 4.0], 'stone')
    ..coin(<num>[-14.0, 4.8, 28.0], 'the ramp coin')
    ..coin(<num>[-14.0, 4.8, 30.5], 'the second ramp coin');
  // The caps: four walls butted, not overlapped, and three blocks on top.
  for (final x in <num>[10.0, 18.0]) {
    k.route(<num>[x, 1.5, 26.0], <num>[2.0, 3.0, 8.0], 'stone');
  }
  for (final z in <num>[22.5, 29.5]) {
    k.route(<num>[14.0, 1.5, z], <num>[6.0, 3.0, 1.0], 'stone');
  }
  for (final (i, dx) in _counted(<num>[-2.0, 0.0, 2.0])) {
    k.breakable(
      'the mould cap $i',
      <num>[14.0 + dx, 3.6, 26.0],
      size: const <num>[2.0, 1.2, 6.0],
    );
  }
  for (final (i, dx) in _counted(<num>[-2.0, 0.0, 2.0])) {
    k.coin(<num>[14.0 + dx, 0.8, 26.0], "the cap's coin $i");
  }
  // The pad, over solid ground: a pad shown where a miss costs nothing is a
  // pad a player believes later.
  k.spring('the scrap pad', <num>[0.0, 0.2, 36.0], speed: 17.0);
  for (final (i, y) in _counted(<num>[2.6, 4.0, 5.4])) {
    k.coin(<num>[0.0, y, 36.0], 'the pad coin $i');
  }
  k.enemy(
    'the foreman',
    <num>[-9.0, 0.0, 33.0],
    route: <List<num>>[
      <num>[9.0, 0.0, 33.0],
    ],
    speed: 0.4,
  );

  // The shallow pour: a fall costs health and a climb, not a life.
  melt('the shallow pour', 40.0, 56.0, 2.5, damage: 30.0);
  // The catwalk, west: brass on legs, three centimetres shy of a step.
  k.route(<num>[-14.0, 0.05, 48.0], <num>[6.0, 0.5, 16.0], 'brass');
  for (final z in <num>[43.0, 53.0]) {
    k
      ..route(<num>[-14.0, -1.35, z], <num>[1.6, 2.3, 1.6], 'stone')
      ..coin(<num>[-14.0, 1.1, z]);
  }
  // The gangway: **a rest every other plank** is what makes it crossable
  // rather than timed.
  for (final (i, z) in <num>[42.0, 46.0, 50.0, 54.0].indexed) {
    if (i == 1) {
      k.route(<num>[0.0, 0.3, z], <num>[5.0, 0.4, 4.0], 'brass');
    } else {
      k.crumbling(
        'the gangway plank ${i + 1}',
        <num>[0.0, 0.3, z],
        size: const <num>[5.0, 0.4, 4.0],
        delay: 1.1,
        gone: 3.0,
      );
    }
    k.coin(<num>[0.0, 1.3, z], 'gangway coin ${i + 1}');
  }
  // The ladle, east.
  k
    ..mover(
      'platform',
      'the ladle',
      <num>[14.0, 0.0, 42.0],
      <num>[5.0, 0.6, 5.0],
      <num>[0.0, 0.0, 12.0],
      3.0,
      1.5,
    )
    ..coin(<num>[14.0, 1.4, 48.0], "the ladle's coin");
  // Two pads on the pool's bed: a pit you can only walk out of the way you
  // fell in reads as a punishment.
  for (final x in <num>[-6.0, 6.0]) {
    k
      ..spring(
        'the relief pad ${x < 0 ? 'west' : 'east'}',
        <num>[x, -2.3, 48.0],
        speed: 17.0,
      )
      ..coin(<num>[x, -1.4, 44.0]);
  }

  // The moulds: a stair of terraces, each under a single jump, and the key
  // on the top one.
  deck(56.0, 96.0);
  k.checkpoint('the mould floor', 58.0, 3, respawn: 57.0);
  for (final (i, (z, top)) in _counted(const <(num, num)>[
    (66.0, 1.6),
    (72.0, 3.2),
    (78.0, 4.8),
    (84.0, 6.4),
  ])) {
    k
      ..route(<num>[-11.0, top / 2.0, z], <num>[14.0, top, 6.0], 'stone')
      ..coin(<num>[-15.0, top + 0.8, z], 'mould coin $i')
      ..coin(<num>[-7.0, top + 0.8, z], 'mould coin ${i + 4}');
  }
  k
    ..key('the amber key', <num>[-11.0, 7.4, 84.0], 'amber')
    ..lamp('the mould lamp', <num>[-11.0, 7.4, 80.0])
    // East of it, a pad and a rope.
    ..spring('the mould pad', <num>[12.0, 0.2, 70.0], speed: 17.0);
  for (final (i, y) in _counted(<num>[2.6, 4.2, 5.8])) {
    k.coin(<num>[12.0, y, 70.0], 'the mould pad coin $i');
  }
  k
    ..climbable(
      'the charging rope',
      <num>[16.0, 5.0, 84.0],
      size: const <num>[1.0, 8.0, 1.0],
      swing: 3.0,
      period: 2.6,
    )
    ..coin(<num>[19.0, 8.6, 84.0], "the rope's coin")
    ..enemy(
      'the moulder',
      <num>[-2.0, 0.0, 92.0],
      route: <List<num>>[
        <num>[16.0, 0.0, 92.0],
      ],
      kind: 'leaper',
      speed: 0.45,
    );
  for (final x in <num>[-19.0, 19.0]) {
    k
      ..pillar(x, 60.0, 2.4, width: 3.0)
      ..pillar(x, 92.0, 3.6, width: 3.0)
      ..crate(<num>[x, 0.0, 76.0]);
  }

  // The tap hole. The anvils are a hop you cannot miss: what makes this hard
  // is what is underneath, not how far apart they are.
  deck(96.0, 104.0);
  k.checkpoint('the tap', 98.0, 4, respawn: 97.0);
  melt('the tap hole', 104.0, 122.0, 6.0);
  for (final (i, z) in _counted(<num>[106.0, 110.0, 114.0, 118.0])) {
    k
      ..route(<num>[0.0, -2.8, z], <num>[2.5, 6.4, 2.5], 'brass')
      ..coin(<num>[0.0, 1.2, z], 'anvil coin $i');
  }
  // The lift, west, and the gantry it reaches — which **stops short of the
  // gate**, or the key would be an ornament.
  k
    ..route(<num>[-18.0, 4.5, 100.0], <num>[7.0, 9.0, 7.0], 'stone')
    ..mover(
      'lift',
      'the charging lift',
      <num>[-12.0, 0.3, 100.0],
      <num>[4.0, 0.6, 4.0],
      <num>[0.0, 9.0, 0.0],
      2.0,
      4.0,
    )
    ..plate(
      "the charging lift's plate",
      'the charging lift',
      <num>[-12.0, 1.6, 100.0],
    )
    ..route(<num>[-12.0, 9.3, 114.0], <num>[6.0, 0.6, 20.0], 'wood');
  for (var i = 0; i < 4; i++) {
    k.coin(<num>[-12.0, 10.4, 107.0 + i * 5.0], 'gantry coin ${i + 1}');
  }

  // The gatehouse — **not "the amber gate"**: a name is what everything else
  // points at, and two things wearing one is a reference nobody can resolve.
  deck(122.0, length.$2);
  k.checkpoint('the gatehouse', 128.0, 5, respawn: 127.0);
  for (final x in <num>[-13.0, 13.0]) {
    k.route(<num>[x, 4.0, 134.0], <num>[18.0, 8.0, 2.0], 'stone');
  }
  k
    ..gate(
      'the amber gate',
      <num>[0.0, 2.5, 134.0],
      'amber',
      size: const <num>[8.0, 5.0, 2.0],
      lintel: 8.0,
    )
    ..plate(
      "the amber gate's plate",
      'the amber gate',
      <num>[0.0, 1.6, 131.0],
      size: const <num>[6.0, 3.0, 3.0],
    )
    ..lamp('the gate lamp west', <num>[-6.0, 1.0, 131.0])
    ..lamp('the gate lamp east', <num>[6.0, 1.0, 131.0])
    // The cooling yard: two hoists, a yard of crates, and the way out.
    ..checkpoint('the cooling yard', 142.0, 6, respawn: 141.0);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-4.0, 142.0),
    (4.0, 142.0),
    (0.0, 148.0),
  ])) {
    k.coin(<num>[x, 0.8, z], 'yard coin $i');
  }
  for (final x in <num>[-16.0, 16.0]) {
    final side = x < 0 ? 'west' : 'east';
    k
      ..mover(
        'lift',
        'the $side hoist',
        <num>[x, 0.3, 146.0],
        <num>[4.0, 0.6, 4.0],
        <num>[0.0, 7.0, 0.0],
        2.0,
        4.0,
      )
      ..plate("the $side hoist's plate", 'the $side hoist', <num>[
        x,
        1.6,
        146.0,
      ])
      ..fill(<num>[x, 3.75, 154.0], <num>[8.0, 7.5, 8.0], 'stone')
      ..coin(<num>[x, 8.6, 154.0])
      ..fill(<num>[x, 7.8, 162.0], <num>[8.0, 0.6, 8.0], 'wood')
      ..coin(<num>[x, 9.0, 162.0])
      ..crate(<num>[x < 0 ? x - 5.0 : x + 5.0, 0.0, 150.0]);
  }
  // Two stacks of cooling ingots off the walked line. **Stacked rather than
  // nested**, unlike a ziggurat: slabs one on another share only a face, and
  // each tier's coin sits outside the footprint of the tier above.
  void stack(num x, num z, int tiers, num step, num base) {
    for (var i = 0; i < tiers; i++) {
      final side = base - i * 2.0;
      final top = step * (i + 1);
      k
        ..fill(<num>[x, top - step / 2.0, z], <num>[side, step, side], 'brass')
        ..coin(<num>[x + side / 2.0 - 0.5, top + 0.8, z]);
    }
  }

  for (final x in <num>[-11.0, 11.0]) {
    stack(x, 166.0, 3, 1.8, 8.0);
  }
  k.enemy(
    'the yard keeper',
    <num>[-6.0, 0.0, 172.0],
    route: <List<num>>[
      <num>[6.0, 0.0, 172.0],
    ],
    speed: 0.4,
  );
  for (final (i, x) in _counted(<num>[-6.0, 6.0])) {
    k.coin(<num>[x, 0.8, 170.0], 'the last coin $i');
  }
  k.exitAt('the shipping door', <num>[0.0, 0.7, 174.0], 'The foundry cools.');

  return <String, String>{
    '$_levels/foundry.json': k.write(
      name: 'Foundry',
      lights: <Map<String, Object?>>[
        PlatformKit.sun,
        for (final (at, colour, range) in const <(List<num>, List<num>, num)>[
          (<num>[0.0, 6.0, -6.0], <num>[0.7, 0.8, 1.0], 36.0),
          (<num>[0.0, 6.0, 26.0], <num>[1.0, 0.86, 0.6], 40.0),
          (<num>[0.0, 4.0, 48.0], <num>[1.0, 0.55, 0.25], 44.0),
          (<num>[0.0, 8.0, 76.0], <num>[1.0, 0.8, 0.5], 46.0),
          (<num>[0.0, 5.0, 113.0], <num>[1.0, 0.45, 0.2], 48.0),
          (<num>[0.0, 7.0, 132.0], <num>[1.0, 0.88, 0.66], 40.0),
          (<num>[0.0, 8.0, 156.0], <num>[0.85, 0.92, 1.0], 46.0),
          (<num>[0.0, 8.0, 174.0], <num>[0.9, 1.0, 0.95], 40.0),
        ])
          PlatformKit.pointLight(at, colour, range: range),
      ],
      fog: const <num>[0.10, 0.05, 0.04],
      density: 0.006,
      next: 'assets/levels/spire.json',
      tool: 'tool/make_foundry.py',
    ),
  };
}

// MARK: - Spire

/// A flight of the spire: `(z, depth, top, x, width)`.
typedef _Flight = (num, num, num, num, num);

/// The last level: a tower. **The whole of the difficulty is one entity** —
/// everything below the flights is fatal, so a missed jump is a death rather
/// than a fall, which is what makes the landings worth their checkpoints.
///
/// The flights are written out one by one: every one of them is a place a
/// player stands and a jump is measured from, so none is generated.
Map<String, String> spire(GeneratorSource _) {
  const w = 36.0;
  const length = (-12.0, 154.0);
  // How deep the shaft goes and how high the walls stand.
  const floor = -9.0;
  const ceiling = 33.0;
  const flights = <_Flight>[
    (22.0, 8.0, 1.8, 0.0, 18.0),
    (33.0, 8.0, 3.6, -3.0, 16.0),
    (45.0, 8.0, 5.4, 3.0, 16.0),
    (56.5, 9.0, 7.2, 0.0, 18.0),
    (68.0, 8.0, 9.0, -3.0, 16.0),
    (80.0, 8.0, 10.8, 3.0, 16.0),
    (91.5, 9.0, 12.6, 0.0, 18.0),
    (103.0, 8.0, 14.4, -3.0, 16.0),
    (115.0, 8.0, 16.2, 3.0, 16.0),
    (126.5, 9.0, 18.0, 0.0, 20.0),
  ];
  // The shelf the key is on stands *against* the first landing, a step up,
  // rather than two metres of shaft away from it: a detour off the route
  // should cost a detour, not a life.
  const spur = (56.5, 9.0, 8.4, -13.5, 9.0);
  const summit = (140.0, 12.0, 19.0, 0.0, 24.0);

  final k = PlatformKit(
    clear: <Clear>[
      (-6.0, 6.0, length.$1, 18.0),
      for (final (z, depth, _, x, width) in <_Flight>[...flights, spur, summit])
        (x - width / 2.0, x + width / 2.0, z - depth / 2.0, z + depth / 2.0),
    ],
  );

  // A flight of the stair: a column out of the dark with a floor on it.
  void tower(_Flight flight) {
    final (z, depth, top, x, width) = flight;
    k.route(
      <num>[x, (top + floor) / 2.0, z],
      <num>[width, top - floor, depth],
      'stone',
    );
  }

  // The shaft the whole climb stands in; its sides are what keeps a player
  // in it, and they cast no shadow.
  for (final x in <num>[-w / 2 - 0.5, w / 2 + 0.5]) {
    k.route(
      <num>[x, (floor + ceiling) / 2.0, (length.$1 + length.$2) / 2.0],
      <num>[1.0, ceiling - floor, length.$2 - length.$1],
      'stone',
      casts: false,
    );
  }
  for (final z in <num>[length.$1 - 0.5, length.$2 + 0.5]) {
    k.route(
      <num>[0.0, (floor + ceiling) / 2.0, z],
      <num>[w + 2.0, ceiling - floor, 1.0],
      'stone',
      casts: false,
    );
  }

  // The foot.
  k
    ..route(
      <num>[0.0, -0.5, (length.$1 + 18.0) / 2.0],
      <num>[w, 1.0, 18.0 - length.$1],
      'stone',
    )
    ..spawn(<num>[0.0, 0.0, -8.0]);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (0.0, -4.0),
    (-4.0, 0.0),
    (4.0, 0.0),
    (0.0, 6.0),
  ])) {
    k.coin(<num>[x, 0.8, z], 'the foot coin $i');
  }
  k
    ..lamp('the foot lamp west', <num>[-8.0, 1.0, -6.0])
    ..lamp('the foot lamp east', <num>[8.0, 1.0, -6.0])
    ..checkpoint('the foot', -2.0, 1, respawn: -4.0);
  for (final x in <num>[-14.0, 14.0]) {
    k
      ..hut(x, 2.0, 3.0, width: 6.0)
      ..crate(<num>[x, 0.0, 10.0]);
  }

  // The shaft, `instant` rather than a large number: see `Hazard.instant`.
  k.hazard(
    'the shaft',
    <num>[0.0, floor / 2.0, (18.0 + 134.0) / 2.0],
    <num>[w, -floor, 134.0 - 18.0],
    instant: true,
  );

  // The flights, each with a ledge on its open side a metre down: the only
  // place in this level a coin can be that is not on the way up.
  for (final (i, flight) in _counted(flights)) {
    final (z, depth, top, x, width) = flight;
    tower(flight);
    k.coin(<num>[x, top + 0.8, z], 'flight coin $i');
    final away = x <= 0.0 ? 1.0 : -1.0;
    final ledge = x + away * (width / 2.0 + 2.5);
    k
      ..fill(<num>[ledge, top - 1.5, z], <num>[4.0, 1.0, depth - 2.0], 'stone')
      ..coin(<num>[ledge, top - 0.2, z], 'ledge coin $i');
    for (final dz in <num>[-depth / 4.0, depth / 4.0]) {
      k.coin(<num>[x + away * 4.0, top + 0.8, z + dz]);
    }
  }
  k
    ..checkpoint('the second flight', 33.0, 2, respawn: 33.0, y: 3.6, x: -3.0)
    ..checkpoint('the first landing', 56.5, 3, respawn: 56.5, y: 7.2)
    ..checkpoint('the high landing', 91.5, 4, respawn: 91.5, y: 12.6)
    ..checkpoint('the crown', 124.0, 5, respawn: 125.0, y: 18.0);

  // The spur, and the key on it.
  tower(spur);
  final (spurZ, _, spurTop, spurX, _) = spur;
  k
    ..key('the slate key', <num>[spurX, spurTop + 1.0, spurZ], 'slate')
    ..lamp('the key lamp', <num>[spurX, spurTop + 1.0, spurZ - 3.0]);
  for (final dz in <num>[-2.5, 2.5]) {
    k.coin(<num>[spurX, spurTop + 0.8, spurZ + dz]);
  }

  // The hunters, on the flights rather than the landings: something waiting
  // where the game told you to rest is the cheap version. Eight metres of
  // sight and a second and a half of memory: a runner who keeps moving
  // outruns one.
  for (final (name, at) in const <(String, List<num>)>[
    ('the first watcher', <num>[8.0, 5.4, 45.0]),
    ('the second watcher', <num>[8.0, 10.8, 80.0]),
    ('the third watcher', <num>[-8.0, 14.4, 103.0]),
    ("the crown's watcher", <num>[7.0, 18.0, 128.0]),
  ]) {
    k.enemy(name, at, kind: 'hunter', sight: 8.0, patience: 1.5);
  }
  // And two that only walk, for the contrast.
  k
    ..enemy(
      'the first warden',
      <num>[-7.0, 7.2, 59.0],
      route: <List<num>>[
        <num>[7.0, 7.2, 59.0],
      ],
      speed: 0.35,
    )
    ..enemy(
      'the second warden',
      <num>[-7.0, 12.6, 94.0],
      route: <List<num>>[
        <num>[7.0, 12.6, 94.0],
      ],
      speed: 0.4,
    );

  // The summit.
  tower(summit);
  final (_, _, summitTop, _, _) = summit;
  k.checkpoint('the threshold', 136.0, 6, respawn: 136.0, y: summitTop);

  // The slate gate: a wall across the summit, a door in it, and stone from
  // the door's head to the parapet, from one number so the two cannot drift
  // apart and leave a slot again. **The lintel does not make the gate
  // compulsory** — no wall in this game seals anything against somebody
  // willing to wall-jump it forty times — but a wall with a hole in it is a
  // mistake whatever the wall jump can do.
  final gateTop = summitTop + 8.0;
  final doorTop = summitTop + 5.0;
  for (final x in <num>[-8.0, 8.0]) {
    k.route(
      <num>[x, (summitTop + gateTop) / 2.0, 140.0],
      <num>[8.0, gateTop - summitTop, 2.0],
      'stone',
    );
  }
  k
    ..gate(
      'the slate gate',
      <num>[0.0, (summitTop + doorTop) / 2.0, 140.0],
      'slate',
      size: <num>[8.0, doorTop - summitTop, 2.0],
      lintel: gateTop,
    )
    // **Five metres deep, from the summit's own lip**: a door takes nine
    // tenths of a second to open, and a runner covers five and a half metres
    // in that time.
    ..plate(
      "the slate gate's plate",
      'the slate gate',
      <num>[0.0, summitTop + 1.6, 136.5],
      size: const <num>[8.0, 3.0, 5.0],
    )
    ..lamp('the gate lamp west', <num>[-6.0, summitTop + 1.0, 137.0])
    ..lamp('the gate lamp east', <num>[6.0, summitTop + 1.0, 137.0]);
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-4.0, 143.0),
    (4.0, 143.0),
    (0.0, 137.0),
  ])) {
    k.coin(<num>[x, summitTop + 0.8, z], 'summit coin $i');
  }
  for (final (i, (x, z)) in _counted(const <(num, num)>[
    (-2.8, 143.8),
    (0.0, 145.0),
    (2.8, 143.8),
  ])) {
    k.coin(<num>[x, summitTop + 2.4, z], "the beacon's ring $i");
  }
  // `route` rather than `fill` for the corner blocks: the summit is clear
  // ground, and something meant to stand on the route is part of it.
  for (final x in <num>[-10.0, 10.0]) {
    k
      ..route(<num>[x, summitTop + 1.5, 134.5], <num>[3.0, 3.0, 3.0], 'stone')
      ..coin(<num>[x, summitTop + 3.8, 134.5])
      ..crate(<num>[x, summitTop, 143.0]);
  }
  k.exitAt(
    'the beacon',
    <num>[0.0, summitTop + 1.5, 144.5],
    'The spire is climbed.',
  );

  return <String, String>{
    '$_levels/spire.json': k.write(
      name: 'Spire',
      lights: <Map<String, Object?>>[
        PlatformKit.sun,
        for (final (at, colour, range) in const <(List<num>, List<num>, num)>[
          (<num>[0.0, 6.0, 0.0], <num>[1.0, 0.9, 0.7], 40.0),
          (<num>[0.0, 8.0, 33.0], <num>[0.85, 0.9, 1.0], 40.0),
          (<num>[0.0, 13.0, 56.5], <num>[1.0, 0.9, 0.75], 44.0),
          (<num>[0.0, 15.0, 80.0], <num>[0.8, 0.88, 1.0], 42.0),
          (<num>[0.0, 18.0, 91.5], <num>[1.0, 0.9, 0.75], 44.0),
          (<num>[0.0, 21.0, 115.0], <num>[0.8, 0.88, 1.0], 42.0),
          (<num>[0.0, 24.0, 126.5], <num>[1.0, 0.92, 0.8], 46.0),
          (<num>[0.0, 25.0, 143.0], <num>[1.0, 1.0, 0.9], 50.0),
        ])
          PlatformKit.pointLight(at, colour, range: range),
      ],
      fog: const <num>[0.04, 0.05, 0.09],
      density: 0.005,
      // No `next`: this is where the game ends, and a null next level is how
      // the credits know it.
      tool: 'tool/make_spire.py',
    ),
  };
}
