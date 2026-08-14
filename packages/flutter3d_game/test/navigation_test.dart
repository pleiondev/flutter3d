/// The grid, the field, and the monster that walks round a corner.
///
/// The last group is the one the whole stage exists for, and it is written as
/// an A/B: the *same* room, the *same* monster, the *same* number of steps,
/// once with navigation and once without. The mutation check is built into the
/// pair — an implementation that quietly ignored the field would fail the
/// first test, and one that reached the player by luck rather than by routing
/// would fail the second.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/src/actors/actor_system.dart';
import 'package:flutter3d_game/shooter.dart';
import 'package:flutter3d_game/src/combat/hitscan.dart';
import 'package:flutter3d_game/src/combat/projectile.dart';
import 'package:flutter3d_game/src/combat/weapon_behaviour.dart';
import 'package:flutter3d_game/src/level/level.dart';
import 'package:flutter3d_game/src/level/level_issue.dart';
import 'package:flutter3d_game/src/nav/flow_field.dart';
import 'package:flutter3d_game/src/nav/nav_grid.dart';
import 'package:flutter3d_game/src/nav/navigation.dart';
import 'package:flutter3d_game/src/physics/layers.dart';
import 'package:flutter3d_game/sample.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Brush _box(double cx, double cy, double cz, double sx, double sy, double sz) =>
    Brush(centre: Vector3(cx, cy, cz), size: Vector3(sx, sy, sz));

/// Twenty metres square, its top face at y = 0.
Brush _floor() => _box(0.0, -0.5, 0.0, 20.0, 1.0, 20.0);

/// A room split down the middle by a wall that stops short of the south edge,
/// so the only way across is round the end of it.
///
/// ```
///   z=-10  ##########|##########
///                    |
///          M         |         P     <- monster, player, at z = -8
///                    |
///   z=+2             +
///                                    <- the way round
///   z=+10  ####################
/// ```
List<Brush> _uRoom() => <Brush>[
      _floor(),
      _box(0.0, 1.5, -4.0, 1.0, 3.0, 12.0),
    ];

CollisionWorld _worldOf(List<Brush> brushes) {
  final world = CollisionWorld();
  for (final brush in brushes) {
    world.addBox(brush.centre, brush.size);
  }
  return world;
}

void main() {
  group('bake', () {
    test('a plain floor is walkable everywhere, at the height of its top', () {
      final grid = NavGrid.bake(<Brush>[_floor()]);

      expect(grid.columns, 40);
      expect(grid.rows, 40);

      final cell = grid.cellAtPoint(3.2, -7.1);
      expect(grid.isWalkable(cell), isTrue);
      expect(grid.floorAt(cell), closeTo(0.0, 1e-5),
          reason: 'the surface is the top of the brush, not its centre');
      expect(grid.headroomAt(cell), NavGrid.maxHeadroom);
    });

    test('the cell reported is the one containing the point', () {
      final grid = NavGrid.bake(<Brush>[_floor()]);
      final centre = Vector3.zero();
      grid.centreOf(grid.cellAtPoint(3.2, -7.1), centre);
      expect(centre.x, closeTo(3.25, 1e-6));
      expect(centre.z, closeTo(-7.25, 1e-6));
    });

    test('off the level is not a cell', () {
      final grid = NavGrid.bake(<Brush>[_floor()]);
      expect(grid.cellAtPoint(40.0, 0.0), -1);
      expect(grid.cellAtPoint(0.0, -10.001), -1);
    });

    test('a level with nothing solid in it bakes an empty grid', () {
      final grid = NavGrid.bake(<Brush>[
        Brush(
          centre: Vector3.zero(),
          size: Vector3(4.0, 1.0, 4.0),
          solid: false,
        ),
      ]);
      expect(grid.isEmpty, isTrue);
      expect(grid.cellAtPoint(0.0, 0.0), -1);
    });

    test('the floor of a room is the floor, not the top of its ceiling', () {
      // The reason the *lowest* span wins. A ceiling's upper face has a floor
      // under it and open sky above it, which is every local property a
      // standing surface has. Taking the highest span puts the whole level's
      // population on the roof.
      //
      // Mutation: keep the last valid span instead of the first. This fails.
      final grid = NavGrid.bake(<Brush>[
        _floor(),
        _box(0.0, 3.2, 0.0, 20.0, 0.4, 20.0), // ceiling, 3.0 to 3.4
      ]);

      final cell = grid.cellAtPoint(1.0, 1.0);
      expect(grid.floorAt(cell), closeTo(0.0, 1e-5));
      expect(grid.headroomAt(cell), closeTo(3.0, 1e-5),
          reason: 'the ceiling is what limits the room, so it is 3 not 8');
    });

    test('a room with a roof is not reported as ambiguous', () {
      // The other half of the same point, and the reason the warning counts
      // *enclosed* surfaces rather than surfaces: every enclosed room in every
      // level has two spans, and a warning that fires on all of them says
      // nothing at all.
      final issues = <LevelIssue>[];
      NavGrid.bake(
        <Brush>[_floor(), _box(0.0, 3.2, 0.0, 20.0, 0.4, 20.0)],
        issues: issues,
      );
      expect(issues, isEmpty);
    });

    test('a walkway over a floor, both under a ceiling, is reported', () {
      // The case a single height per column genuinely cannot express. It is a
      // warning rather than an error because the level plays: everything walks
      // on the lower floor and nothing paths across the walkway.
      //
      // Mutation: drop the issue. This fails.
      final issues = <LevelIssue>[];
      final grid = NavGrid.bake(
        <Brush>[
          _floor(),
          _box(0.0, 2.4, 0.0, 4.0, 0.2, 20.0), // walkway, top at 2.5
          _box(0.0, 6.2, 0.0, 20.0, 0.4, 20.0), // ceiling, bottom at 6.0
        ],
        issues: issues,
      );

      expect(issues, hasLength(1));
      expect(issues.single.severity, LevelIssueSeverity.warning);
      expect(issues.single.message, contains('lowest'));

      final under = grid.cellAtPoint(0.5, 0.5);
      expect(grid.floorAt(under), closeTo(0.0, 1e-5),
          reason: 'the lower floor is the one kept');
      expect(grid.headroomAt(under), closeTo(2.3, 1e-5),
          reason: 'up to the underside of the walkway');
    });

    test('a wall thinner than a cell still blocks the cells it crosses', () {
      // The reason the surface pass samples the cell centre and the headroom
      // pass does not. A 10cm wall between two cell centres would be invisible
      // to a pure point sample, and every monster in the level would path through
      // it — the one failure of a grid nav that is impossible to explain to
      // whoever built the level.
      //
      // Mutation: restrict the headroom pass to brushes containing the centre.
      // This fails.
      final grid = NavGrid.bake(<Brush>[
        _floor(),
        // Straddling the cell boundary at x = 0.5, so it contains neither of
        // the two centres it lies between (0.25 and 0.75).
        _box(0.5, 1.5, 0.0, 0.1, 3.0, 20.0),
      ]);

      expect(grid.isWalkable(grid.cellAtPoint(0.6, 0.0)), isFalse,
          reason: 'a wall crossing a cell is in the way whether or not it '
              'happens to cover the exact centre');
    });

    test('the top of a wall does not count as room beside it', () {
      // Clearance measured from walkability alone counts a wall's own roof as
      // open space, and every corridor comes out two cells wider than it is —
      // which is the bug that lets a body path straight into the wall it was
      // supposed to keep clear of.
      //
      // Mutation: seed the transform from `headroom > 0` only, dropping the
      // height test. The corridor's clearance rises and this fails.
      final grid = NavGrid.bake(_uRoom());

      final beside = grid.cellAtPoint(-0.75, -8.0);
      expect(grid.isWalkable(beside), isTrue);
      expect(grid.clearanceAt(beside), 1,
          reason: 'it is touching the wall, so there is one cell of room');

      final onTop = grid.cellAtPoint(0.0, -8.0);
      expect(grid.floorAt(onTop), closeTo(3.0, 1e-5),
          reason: 'the top of a wall really is a surface; that is the point');
      expect(grid.clearanceAt(onTop), 1);
    });

    test('a body needs the room its radius asks for', () {
      final grid = NavGrid.bake(<Brush>[_floor()], cellSize: 0.25);
      // (k - 0.5) cells of half-width, so 0.35 needs 2 and 0.62 needs 3.
      expect(grid.clearanceForRadius(0.35), 2);
      expect(grid.clearanceForRadius(0.62), 3);
      expect(grid.clearanceForRadius(0.0), 1,
          reason: 'zero means unwalkable, so nothing may round down to it');
    });

    test('a step is a step and a wall is a wall', () {
      final grid = NavGrid.bake(<Brush>[
        _floor(),
        _box(-5.0, 0.15, 0.0, 10.0, 0.3, 20.0), // a 30cm step, top at 0.3
      ]);
      final low = grid.cellAtPoint(1.0, 0.0);
      final high = grid.cellAtPoint(-1.0, 0.0);
      expect(grid.floorAt(high), closeTo(0.3, 1e-5));
      expect(grid.canMove(low, high), isTrue, reason: '0.3 is under the 0.4');
      expect(grid.canMove(high, low), isTrue);

      final wall = NavGrid.bake(<Brush>[
        _floor(),
        _box(-5.0, 1.5, 0.0, 10.0, 3.0, 20.0), // 3m, top at 3.0
      ]);
      expect(wall.canMove(wall.cellAtPoint(1.0, 0.0), wall.cellAtPoint(-1.0, 0.0)),
          isFalse);
    });
  });

  group('flow field', () {
    test('the route round a wall is longer than the way through it', () {
      // The field's whole content in one number. Straight across is 8 metres;
      // round the end of the wall is more than twenty.
      //
      // Mutation: let the sweep cross cells it does not fit in, or drop the
      // `canMove` test. The cost collapses towards 8 and this fails.
      final grid = NavGrid.bake(_uRoom());
      final field = FlowField(grid, minClearance: 2)
        ..rebuild(Vector3(4.0, 0.7, -8.0));

      final walk = field.walkingDistanceTo(Vector3(-4.0, 0.9, -8.0));
      expect(walk, isNotNull);
      expect(walk!, greaterThan(20.0));
      expect(walk, lessThan(40.0), reason: 'it is a detour, not a wander');
    });

    test('it points away from the player when the player is behind a wall', () {
      // What a monster actually reads, and the whole visible difference: the
      // player is due east and the first step is southward.
      final grid = NavGrid.bake(_uRoom());
      final field = FlowField(grid, minClearance: 2)
        ..rebuild(Vector3(4.0, 0.7, -8.0));

      final direction = Vector3.zero();
      expect(field.descend(Vector3(-4.0, 0.9, -8.0), direction), isTrue);
      expect(direction.z, greaterThan(0.5),
          reason: 'the way round is south, towards the open end');
      expect(direction.y, 0.0, reason: 'a flow field is horizontal');
      expect(direction.length, closeTo(1.0, 1e-6));
    });

    test('inside the goal cell it says nothing, so the caller goes straight',
        () {
      // Steering by the field within one cell of the target would have a
      // monster circling a cell centre half a metre from the player.
      final grid = NavGrid.bake(<Brush>[_floor()]);
      final field = FlowField(grid, minClearance: 2)
        ..rebuild(Vector3(4.0, 0.7, -8.0));
      expect(field.descend(Vector3(4.1, 0.9, -7.9), Vector3.zero()), isFalse);
    });

    test('somewhere with no route reports none rather than a direction', () {
      // An island: the floor, and a second floor with nothing joining them.
      final grid = NavGrid.bake(<Brush>[
        _box(0.0, -0.5, 0.0, 6.0, 1.0, 6.0),
        _box(20.0, -0.5, 0.0, 6.0, 1.0, 6.0),
      ]);
      final field = FlowField(grid, minClearance: 1)
        ..rebuild(Vector3(0.0, 0.7, 0.0));
      expect(field.walkingDistanceTo(Vector3(20.0, 0.9, 0.0)), isNull);
      expect(field.descend(Vector3(20.0, 0.9, 0.0), Vector3.zero()), isFalse);
    });

    test('two walls meeting at a point are not a doorway', () {
      // The corner rule, and the only thing that distinguishes a route from a
      // body sliding through a crack. These two walls touch at exactly one
      // point and divide the level in two; the cells either side of that point
      // are diagonal neighbours, and both cells between them are wall.
      //
      // ```
      //     ##########·          north
      //              ·##########
      //                          south
      // ```
      //
      // Mutation: drop the two-sides test on the diagonal. The route opens,
      // and this fails.
      final grid = NavGrid.bake(<Brush>[
        _floor(),
        _box(-5.0, 1.5, 0.25, 10.0, 3.0, 0.5), // x -10 to 0, z 0 to 0.5
        _box(5.0, 1.5, -0.25, 10.0, 3.0, 0.5), // x 0 to 10, z -0.5 to 0
      ]);
      final field = FlowField(grid)..rebuild(Vector3(5.0, 0.7, 5.0));

      expect(field.walkingDistanceTo(Vector3(5.0, 0.9, 2.0)), isNotNull,
          reason: 'the same side of the corner is of course reachable');
      expect(field.walkingDistanceTo(Vector3(-5.0, 0.9, -5.0)), isNull,
          reason: 'a corner two walls share is not a gap to walk through');
    });

    test('before the first sweep nothing is reachable', () {
      // A zeroed cost array reads as "you are standing on the goal" for every
      // cell in the level.
      //
      // Mutation: drop the fill in the constructor. This fails.
      final grid = NavGrid.bake(<Brush>[_floor()]);
      final field = FlowField(grid);
      expect(field.goalCell, -1);
      expect(field.walkingDistanceTo(Vector3.zero()), isNull);
    });

    test('a goal where the body does not fit becomes the nearest place it does',
        () {
      // The player standing in a doorway too narrow for a tank should bring
      // the tank as close as it fits, not stop it where it stands.
      //
      // Mutation: return -1 instead of searching outwards. The tank's field
      // has no goal and this fails.
      final grid = NavGrid.bake(_narrowDoorway(), cellSize: 0.25);
      final wide = FlowField(grid, minClearance: grid.clearanceForRadius(0.62))
        ..rebuild(Vector3(0.0, 0.7, 0.0)); // in the doorway itself

      expect(wide.goalCell, isNot(-1));
      expect(wide.fits(wide.goalCell), isTrue);
      // The nearest place a body 1.24 wide fits is just outside the doorway,
      // and the rest of that room is open.
      expect(wide.walkingDistanceTo(Vector3(4.0, 0.9, 0.0)), isNotNull);
    });

    test('a gap wide enough for one body is not wide enough for another', () {
      // Why there is a field per class rather than one shared field. The same
      // doorway, the same grid, two answers.
      final grid = NavGrid.bake(_narrowDoorway(), cellSize: 0.25);
      final goal = Vector3(4.0, 0.7, 0.0);
      final here = Vector3(-4.0, 0.9, 0.0);

      final slim = FlowField(grid, minClearance: grid.clearanceForRadius(0.35))
        ..rebuild(goal);
      final wide = FlowField(grid, minClearance: grid.clearanceForRadius(0.62))
        ..rebuild(goal);

      expect(slim.walkingDistanceTo(here), isNotNull);
      expect(wide.walkingDistanceTo(here), isNull,
          reason: 'a metre of doorway is not a metre of room for a body 1.24 '
              'wide');
    });

    test('a tunnel too low is refused by height and not by width', () {
      // The other axis, and it is a separate one: a passage can be wide open
      // and still be something a tall body cannot enter.
      final grid = NavGrid.bake(_lowTunnel());
      final goal = Vector3(0.0, 0.7, 4.0);
      final here = Vector3(0.0, 0.9, -4.0);

      final short = FlowField(grid, minClearance: 2, minHeadroom: 1.75)
        ..rebuild(goal);
      final tall = FlowField(grid, minClearance: 2, minHeadroom: 2.5)
        ..rebuild(goal);

      expect(short.walkingDistanceTo(here), isNotNull);
      expect(tall.walkingDistanceTo(here), isNull);
    });
  });

  group('navigation', () {
    test('bodies of the same class share one sweep', () {
      final nav = Navigation(NavGrid.bake(<Brush>[_floor()]))
        ..update(Vector3(4.0, 0.7, -8.0));
      final a = nav.fieldFor(radius: 0.35, height: 1.7);
      final b = nav.fieldFor(radius: 0.38, height: 1.7);
      expect(identical(a, b), isTrue);
      expect(nav.fields, hasLength(1));

      nav.fieldFor(radius: 0.62, height: 2.4);
      expect(nav.fields, hasLength(2));
    });

    test('a field built after the goal was set is already pointing at it', () {
      // Lazily building a field is only safe if it catches up. Without the
      // rebuild the monster that asked for it walks nowhere until the player
      // happens to cross into another cell.
      //
      // Mutation: drop the `rebuild` in `putIfAbsent`. This fails.
      final nav = Navigation(NavGrid.bake(_uRoom()))
        ..update(Vector3(4.0, 0.7, -8.0));

      final direction = Vector3.zero();
      expect(
        nav.steer(Vector3(-4.0, 0.9, -8.0), direction,
            radius: 0.35, height: 1.7),
        isTrue,
      );
      expect(direction.z, greaterThan(0.5));
    });

    test('the sweep is skipped while the goal stays in its cell', () {
      final nav = Navigation(NavGrid.bake(<Brush>[_floor()]));
      nav.update(Vector3(4.0, 0.7, -8.0));
      final field = nav.fieldFor(radius: 0.35);
      final before = field.goalCell;
      nav.update(Vector3(4.2, 0.7, -7.8));
      expect(field.goalCell, before);
    });
  });

  group('a monster in a U-shaped room', () {
    /// Runs the same fight twice, differing only in whether the system has a
    /// grid, and reports how close the monster got.
    double closest({required bool navigating}) {
      final brushes = _uRoom();
      final world = _worldOf(brushes);
      final playerAt = Vector3(4.0, 0.9, -8.0);
      final player = world.add(
        Collider(
          shape: CollisionBox(Vector3(0.35, 0.9, 0.35)),
          position: playerAt,
          kind: ColliderKind.kinematic,
          layer: CollisionLayers.player,
        ),
      );
      world.update();

      final system = ActorSystem(world: world, random: math.Random(7));
      final bestiary = Bestiary(
        actors: system,
        shot: WeaponShot(
          world: world,
          hitscan: Hitscan(world: world),
          projectiles: ProjectileSystem(world: world),
        ),
        catalog: Monsters.byName,
      );
      if (navigating) {
        system.navigation = Navigation(NavGrid.bake(brushes));
      }

      final monster = bestiary.spawn(Monsters.runner, Vector3(-4.0, 0.9, -8.0));
      // It cannot see the player through the wall, and would otherwise stand
      // still for ever. Being shot is how a monster notices someone it could
      // not see — the system says so itself.
      system.hurt(monster, 1.0);

      final eye = playerAt + Vector3(0.0, 0.7, 0.0);
      var best = double.infinity;
      for (var i = 0; i < 900; i++) {
        system.step(_dt, focus: eye, focusBody: player);
        world.update();
        final gap = (monster.position! - playerAt).length;
        if (gap < best) best = gap;
      }
      return best;
    }

    test('with navigation it walks round the wall and reaches the player', () {
      expect(closest(navigating: true), lessThan(2.5),
          reason: 'fifteen seconds is more than enough for a thirty metre '
              'detour at 5.4 metres a second');
    });

    test('without navigation it presses itself against the wall', () {
      // The mutation check, and it is the other test. If navigation were being
      // silently ignored, both would agree — and this one asserts they do not.
      expect(closest(navigating: false), greaterThan(4.0),
          reason: 'walking straight at a player behind a wall is walking into '
              'the wall');
    });
  });
}

/// Two rooms joined by a doorway one metre wide.
List<Brush> _narrowDoorway() => <Brush>[
      _floor(),
      _box(0.0, 1.5, -5.25, 1.0, 3.0, 9.5), // wall, z from -10 to -0.5
      _box(0.0, 1.5, 5.25, 1.0, 3.0, 9.5), // wall, z from 0.5 to 10
    ];

/// A wall across the room with a two-metre gap in it, and a lintel over the gap
/// leaving two metres of headroom.
List<Brush> _lowTunnel() => <Brush>[
      _floor(),
      _box(-5.5, 2.5, 0.0, 9.0, 5.0, 1.0), // x from -10 to -1
      _box(5.5, 2.5, 0.0, 9.0, 5.0, 1.0), // x from 1 to 10
      _box(0.0, 3.5, 0.0, 2.0, 3.0, 1.0), // lintel, 2.0 up to 5.0
    ];
