/// Turns at putting what loads in the background into a scene.
///
///     dart test test/scene_turn_test.dart
///
/// The order meshes are registered in reaches the picture, so a scene hands
/// out turns when loads start and each waits for the one before it — see
/// `Scene.reserveTurn`.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

void main() {
  test('each turn is ready only once every turn reserved before it is '
      'released, whatever order they are released in', () async {
    // Mutation: hand back an already-completed future for `ready` in
    // `reserveTurn`, and the second and third turns are ready first.
    final scene = Scene();
    final first = scene.reserveTurn();
    final second = scene.reserveTurn();
    final third = scene.reserveTurn();
    final ready = <String>[];
    for (final (name, turn) in <(String, SceneTurn)>[
      ('first', first),
      ('second', second),
      ('third', third),
    ]) {
      turn.ready.then((_) => ready.add(name)).ignore();
    }

    // The later loads finish first; nothing is ready but the first.
    third.release();
    second.release();
    await pumpEventQueue();
    expect(ready, <String>['first']);

    first.release();
    await pumpEventQueue();
    expect(ready, <String>['first', 'second', 'third']);
  });

  test(
    'a released turn stays released, and turns belong to their scene',
    () async {
      // A loader releases in a `finally`, after a load that may already have
      // released on its own path: the second call must change nothing.
      final scene = Scene();
      final failed = scene.reserveTurn()
        ..release()
        ..release();
      final next = scene.reserveTurn();
      // Another scene's line is its own: a load stuck there holds up nothing
      // here.
      Scene().reserveTurn();
      final elsewhere = Scene().reserveTurn();

      await expectLater(failed.ready, completes);
      await expectLater(next.ready, completes);
      await expectLater(elsewhere.ready, completes);
    },
  );

  test('a turn released before it is ready keeps its place, and a turn is '
      'opened by the release itself, not by a later event', () {
    // A loader let go of mid-load releases a turn that is still waiting:
    // the turns after it must wait for the ones before it all the same.
    // And opening is a plain call — no microtask, no timer — so a turn
    // awaited from another zone (a widget test's real one, say) does not
    // wait on a zone nobody pumps.
    //
    // Mutation: in `release`, pass on whether or not the turn is ready —
    // the third is open while the first still holds its turn.
    final scene = Scene();
    final first = scene.reserveTurn();
    final second = scene.reserveTurn();
    final third = scene.reserveTurn();
    expect(first.isReady, isTrue);

    second.release();
    expect(third.isReady, isFalse);

    first.release();
    expect(second.isReady, isTrue);
    expect(third.isReady, isTrue);
  });
}
