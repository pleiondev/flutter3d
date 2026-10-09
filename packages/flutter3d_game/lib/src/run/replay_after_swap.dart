import 'package:flutter/foundation.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show HotSwap;

import 'game_events.dart';
import 'run_timeline.dart';

/// Lives the last [seconds] of [timeline] again under the new code after
/// every hot reload, and says where the new code parts from the old.
///
/// **A reload answers what the code does now, not what it changed.** The
/// world survives a hot reload and carries on under the new step, which
/// shows the new code running and hides whether the last seconds would have
/// gone differently under it. `RunTimeline.replayUnderNewCode` answers that;
/// this asks it on its own each time `HotSwap` finishes a swap, which a
/// `SceneSurface`'s `reassemble` starts, so nobody has to remember to.
///
/// The present is the loop's capture, which the timeline takes itself. What
/// happened goes to [onReplayed] — by default a line in the
/// console — and, through [postToolEvent], to the VM service as a
/// `flutter3d.timeline.replayedUnderNewCode` event, for an editor listening
/// there. Nothing happens in a build where `HotSwap` is off, which is every
/// build but a debug one.
///
/// [hotSwap] is the swapper whose finished swaps start a replay:
/// `HotSwap.instance` unless the game runs its own — an engine with a
/// `HotSwap` of its own, or a test that swaps by hand.
///
/// Returns the call that stops it.
VoidCallback replayAfterHotSwap(
  RunTimeline timeline, {

  /// How much of the timeline's end is replayed, in seconds.
  double seconds = 3.0,
  void Function(CodeReplay replay)? onReplayed,
  HotSwap? hotSwap,
}) {
  final swaps = (hotSwap ?? HotSwap.instance).swaps;
  void replay() {
    final done = timeline.replayUnderNewCode(seconds: seconds);
    if (done == null) return;
    postToolEvent('timeline.replayedUnderNewCode', done.toJson());
    (onReplayed ?? _say)(done);
  }

  swaps.addListener(replay);
  return () => swaps.removeListener(replay);
}

void _say(CodeReplay replay) => debugPrint(switch (replay.divergence) {
  null =>
    'flutter3d: steps ${replay.fromStep}–${replay.toStep} replayed under the '
        'new code and came out the same',
  final ReplayDivergence parted =>
    'flutter3d: the new code parts from the old $parted',
});
