import 'package:flutter3d_game/flutter3d_game.dart'; // postGameEvent, RunStatus
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart' show Pickup;
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'run_cubit.dart';

/// What the crawl tells whoever watches it from outside — the editor's Play
/// panel, an agent polling `play_events` — through `postGameEvent`:
///
/// | kind | when | data |
/// |---|---|---|
/// | `level.loaded` | a level is up, first or next or again | `level` |
/// | `player.respawned` | the level is up again after a death | `level` |
/// | `player.died` | the run is lost | `level` |
/// | `pickup.taken` | something on the floor was taken | `level`, `pickup`, `gift`, `amount`, `detail`, `at` |
/// | `level.exited` | the way out was reached | `level`, `next` |
/// | `run.finished` | the way out of the last level | `levels`, `kills`, `seconds` |
///
/// **Read off what the run already says, not watched for again.** The run's
/// status is what the screen reacts to, and the step's mechanism events are
/// what the soundtrack plays the pickup chime from; these are the same
/// moments, posted once more for somebody who is not looking at the screen.
final class GamePosts {
  GamePosts(this.run);

  final DungeonRun run;

  /// The status before the one being told, to tell a level coming up from a
  /// level being replaced under a running game, which is not a load.
  RunStatus<LevelReady>? _was;

  /// Whether the last level to end ended in a death, so the next one up is
  /// the player coming back.
  bool _died = false;

  /// What [status], just published by the run, means to somebody watching.
  void changed(RunStatus<LevelReady> status) {
    final was = _was;
    _was = status;
    switch (status) {
      case RunPlaying<LevelReady>(:final asset, outcome: RunOutcome.playing)
          when was is! RunPlaying<LevelReady>:
        postGameEvent('level.loaded', <String, Object?>{'level': asset});
        if (_died) {
          postGameEvent('player.respawned', <String, Object?>{'level': asset});
        }
        _died = false;
      case RunPlaying<LevelReady>(:final asset, outcome: RunOutcome.lost):
        _died = true;
        postGameEvent('player.died', <String, Object?>{'level': asset});
      case RunPlaying<LevelReady>(
        :final asset,
        :final level,
        outcome: RunOutcome.won,
      ):
        final next = level.staged.sim.nextLevel;
        postGameEvent('level.exited', <String, Object?>{
          'level': asset,
          'next': next,
        });
        if (next == null) {
          final crawl = run.crawl;
          postGameEvent('run.finished', <String, Object?>{
            'levels': crawl.levels,
            'kills': crawl.kills,
            'seconds': crawl.seconds,
          });
        }
      case RunPlaying<LevelReady>() ||
          RunLoading<LevelReady>() ||
          RunFailed<LevelReady>():
        break;
    }
  }

  /// What the step that just ran took off the floor. Once per step, after
  /// it: the mechanisms' events are the step's and are emptied by the next.
  void stepped() {
    if (run.status case RunPlaying<LevelReady>(:final asset, :final level)) {
      for (final taken in level.staged.mechanisms.events.taken) {
        postGameEvent('pickup.taken', <String, Object?>{
          'level': asset,
          'pickup': taken.name,
          if (taken case Pickup(:final gift, :final amount, :final detail)) ...{
            'gift': gift.name,
            'amount': amount,
            'detail': detail,
            'at': taken.origin.storage.toList(),
          },
        });
      }
    }
  }
}
