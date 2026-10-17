/// The readback's idle staging textures are held to a number.
///
///     flutter test test/staging_pool_test.dart
library;

import 'package:flutter3d_impeller/src/staging_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hundred sizes leave at most the capacity idle', () {
    // Mutation: `give` without the eviction loop, as the map of lists was —
    // a hundred idle textures for a hundred sizes, none of them freeable.
    final pool = StagingPool<String, Object>(capacity: 4);
    final dropped = <Object>[];
    final made = <Object>[for (var i = 0; i < 100; i++) Object()];
    for (var i = 0; i < 100; i++) {
      pool.give('size $i', made[i], onDropped: dropped.add);
    }
    expect(pool.idle, 4);
    expect(dropped, hasLength(96));
    // The oldest go first: the four kept are the last four given back.
    expect(dropped.first, same(made.first));
    expect(pool.take('size 99'), same(made[99]));
    expect(pool.take('size 0'), isNull);
  });

  test('a size asked for again gets its idle texture back', () {
    final pool = StagingPool<String, Object>(capacity: 4);
    final texture = Object();
    pool.give('64x64', texture);
    expect(pool.take('64x64'), same(texture));
    expect(pool.take('64x64'), isNull, reason: 'it is in flight now');
  });
}
