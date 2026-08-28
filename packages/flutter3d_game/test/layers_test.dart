/// What each collision bit means, and who reads the names.
///
///     flutter test test/layers_test.dart
///
/// **Written because the doc comment was wrong in the most expensive way.** It
/// said "nothing in either package reads these names" and invited a game to
/// "declare its own set and ignore this one" — while thirteen places in this
/// package read them, including the layer every unlabelled brush in every level
/// is built on. A game that took the invitation would lose camera
/// wall-avoidance, mover pushing, actor ground checks and brush layering at
/// once, all of it presenting as "the physics feels wrong".
///
/// A comment cannot be tested. The count can.
library;

import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every use of a named bit in this package's own source.
List<String> _readers() {
  final found = <String>[];
  for (final file
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File it) => it.path.endsWith('.dart'))) {
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.startsWith('///') || trimmed.startsWith('//')) continue;
      if (trimmed.contains('CollisionLayers.')) {
        found.add('${file.path}: $trimmed');
      }
    }
  }
  return found..sort();
}

void main() {
  test('the names are read by this package, not merely offered to games', () {
    // The number is not the point — being non-trivial is. A default nobody
    // reads can be ignored for free; a default read in a dozen load-bearing
    // places cannot, and the doc has to say which of those it is.
    final readers = _readers();

    expect(
      readers,
      hasLength(greaterThan(8)),
      reason: 'found only ${readers.join('\n')}',
    );
  });

  test('and the four that would break silently are among them', () {
    // Named one at a time, because these are the four systems a game that
    // declared its own set would lose without an error: the camera keeping out
    // of walls, a mover pushing what stands on it, an actor finding the ground,
    // and every brush that does not name a layer.
    final readers = _readers().join('\n');

    expect(readers, contains('camera_rig.dart'));
    expect(readers, contains('mover.dart'));
    expect(readers, contains('actor_system.dart'));
    expect(readers, contains('level_collision.dart'));
  });

  test('and every bit is a different bit', () {
    // The gap at three is real and now has a name; what matters is that naming
    // it did not put two meanings on one bit.
    final bits = <int>[
      CollisionLayers.world,
      CollisionLayers.player,
      CollisionLayers.actor,
      CollisionLayers.reserved,
      CollisionLayers.pickup,
      CollisionLayers.trigger,
    ];

    expect(bits.toSet(), hasLength(bits.length));
    for (final bit in bits) {
      expect(bit & (bit - 1), 0, reason: '$bit is more than one bit');
      expect(bit & CollisionLayers.all, bit);
    }
  });

  test('and nothing has quietly taken the free one', () {
    // A game may take bit three — deliberately, by editing that file. What must
    // not happen is this package taking it and the doc going on telling
    // extenders the hole is there.
    final readers = _readers();

    expect(
      readers.where((String it) => it.contains('CollisionLayers.reserved')),
      isEmpty,
    );
  });
}
