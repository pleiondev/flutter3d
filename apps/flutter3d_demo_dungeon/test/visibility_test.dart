/// The crypt's visibility table, held against rays it never sampled.
///
///     flutter test test/visibility_test.dart
///
/// The table is a sample and this is the check on it: thousands of random
/// pairs of points in the crypt's empty space, a straight ray between each
/// pair through the level's own collision world, and the rule that an
/// unblocked ray between two cells means the table says they see each other.
/// A table that hides a room somebody can see into fails here, which is the
/// one failure the whole feature must not have. It also has to hide
/// *something*, or it is a table that costs draw calls for nothing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Level _level(String name) => Level.fromJson(
  jsonDecode(File('assets/levels/$name.json').readAsStringSync())
      as Map<String, dynamic>,
);

LevelVisibility _sidecar(String name) => LevelVisibility.fromJson(
  jsonDecode(File('assets/levels/$name.visibility.json').readAsStringSync())
      as Map<String, Object?>,
);

bool _insideSolid(Level level, Vector3 p) {
  for (final brush in level.brushes) {
    if (!brush.solid) continue;
    final lo = brush.min;
    final hi = brush.max;
    if (p.x > lo.x &&
        p.x < hi.x &&
        p.y > lo.y &&
        p.y < hi.y &&
        p.z > lo.z &&
        p.z < hi.z) {
      return true;
    }
  }
  return false;
}

/// A point in the level's empty space, by rejection.
Vector3 _emptyPoint(Level level, GameRandom dice, Aabb3 extent) {
  for (var attempt = 0; attempt < 10000; attempt++) {
    final p = Vector3(
      extent.min.x + dice.nextDouble() * (extent.max.x - extent.min.x),
      extent.min.y + dice.nextDouble() * (extent.max.y - extent.min.y),
      extent.min.z + dice.nextDouble() * (extent.max.z - extent.min.z),
    );
    if (!_insideSolid(level, p)) return p;
  }
  throw StateError('the level has no empty space to stand in');
}

Aabb3 _extent(Level level) {
  final box = Aabb3();
  var first = true;
  for (final brush in level.brushes) {
    if (!brush.solid) continue;
    final b = Aabb3.minMax(brush.min, brush.max);
    if (first) {
      box.copyFrom(b);
      first = false;
    } else {
      box.hull(b);
    }
  }
  return box;
}

void main() {
  for (final name in <String>['crypt', 'vaults', 'deep']) {
    group(name, () {
      final level = _level(name);
      final table = _sidecar(name);

      test('the committed table was baked from these brushes', () {
        expect(
          table.isStaleFor(level),
          isFalse,
          reason: 'run dart run flutter3d_game:bake_visibility',
        );
      });

      test('never hides a cell a ray can reach', () {
        final world = CollisionWorld();
        level.addTo(world);
        world.update();
        final dice = GameRandom(1234);
        final extent = _extent(level);
        final hit = RayHit();
        final direction = Vector3.zero();
        var checked = 0;
        var unblocked = 0;
        final violations = <String>[];
        for (var i = 0; i < 4000; i++) {
          final p = _emptyPoint(level, dice, extent);
          final q = _emptyPoint(level, dice, extent);
          final a = table.cellAt(p);
          final b = table.cellAt(q);
          if (a < 0 || b < 0) continue;
          checked++;
          direction
            ..setFrom(q)
            ..sub(p);
          final distance = direction.length;
          if (distance <= 0.0) continue;
          direction.scale(1.0 / distance);
          if (world.raycast(p, direction, distance, hit)) continue;
          unblocked++;
          // The question a frame asks, with the query margin: an eye at p,
          // a batch whose box is the point q.
          if (!table.canSeeFrom(p, Aabb3.minMax(q, q))) {
            violations.add('$p -> $q (cells $a, $b)');
          }
        }
        expect(checked, greaterThan(1000), reason: 'enough pairs landed');
        expect(unblocked, greaterThan(100), reason: 'enough of them saw');
        expect(
          violations,
          isEmpty,
          reason:
              '${violations.length} of $unblocked unblocked rays cross '
              'cells the table calls hidden:\n${violations.take(5).join('\n')}',
        );
      });

      test('and hides something', () {
        // Averaged over random standing points: the share of open cells the
        // table says are visible. A level of one room would be at one.
        final dice = GameRandom(99);
        final extent = _extent(level);
        var total = 0.0;
        var samples = 0;
        for (var i = 0; i < 200; i++) {
          final eye = _emptyPoint(level, dice, extent);
          final from = table.cellAt(eye);
          if (from < 0) continue;
          var seen = 0;
          for (var cell = 0; cell < table.cellCount; cell++) {
            if (table.canSee(from, cell)) seen++;
          }
          total += seen / table.cellCount;
          samples++;
        }
        final visibleShare = total / samples;
        // ignore: avoid_print
        print(
          '$name: ${table.cellCount} cells, a standing point sees '
          '${(visibleShare * 100).toStringAsFixed(0)}% of them on average',
        );
        expect(visibleShare, lessThan(0.85), reason: 'nothing is hidden');
      });
    });
  }
}
