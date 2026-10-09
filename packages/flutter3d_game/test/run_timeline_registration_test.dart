/// Several `RunTimeline`s on one VM service, in one process.
///
///     flutter test test/run_timeline_registration_test.dart
///
/// What `run_timeline_extensions_test.dart` drives from outside is one
/// timeline. This holds the part that needs no second process: a second
/// timeline registers beside the first instead of throwing, the same one
/// twice is refused, and a cancelled registration lets it register again.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

RunTimeline _timeline() => RunTimeline(
  rewind: RewindBuffer(stepsPerSecond: 60, history: 1.0),
  loop: EngineLoop(input: InputState()),
);

void main() {
  test('a second timeline registers, the same one twice does not, and a '
      'cancelled one registers again', () {
    final first = _timeline();
    final second = _timeline();

    // Mutation: register the extensions on every call, as before, and the
    // second timeline throws: the VM service holds one name per isolate.
    final one = registerTimelineExtensions(first);
    final two = registerTimelineExtensions(second);
    expect(() => registerTimelineExtensions(first), throwsArgumentError);

    // Mutation: leave a cancelled timeline in the list, and this throws.
    one.cancel();
    final again = registerTimelineExtensions(first);
    expect(again.isCanceled, isFalse);

    // Every timeline off, then on again: the names were switched off and
    // are taken back rather than registered a second time, which
    // `dart:developer` would refuse.
    two.cancel();
    again.cancel();
    registerTimelineExtensions(second).cancel();
  });
}
