import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_net/flutter3d_net.dart';

const GameAction _throttle = GameAction('throttle');
const GameAction _brake = GameAction('brake');
const GameAction _left = GameAction('steerLeft');
const GameAction _right = GameAction('steerRight');
const GameAction _handbrake = GameAction('handbrake');

/// Reads this device's own driver into the small JSON shape [NetSession]
/// sends over the wire — the same four lines `main.dart`'s own private
/// `_readDriver` turns into a [VehicleInput], aimed at a [Map] instead so
/// it can travel.
Map<String, Object?> captureDriverFrame(InputState input) => <String, Object?>{
  'throttle': input.value(_throttle),
  'brake': input.value(_brake),
  'handbrake': input.held(_handbrake),
  'steer': input.value(_right) - input.value(_left),
};

/// The far side of [captureDriverFrame]: writes a received frame into
/// whichever car it belongs to.
void applyDriverFrame(Map<String, Object?> frame, VehicleInput out) => out
  ..throttle = (frame['throttle'] as num?)?.toDouble() ?? 0.0
  ..brake = (frame['brake'] as num?)?.toDouble() ?? 0.0
  ..handbrake = (frame['handbrake'] as bool?) ?? false
  ..steer = (frame['steer'] as num?)?.toDouble() ?? 0.0;

/// `net-03`: a two-car [RacingSimulation] kept in step with a remote peer
/// through a [NetSession] — [localCarIndex] is this device's own driver,
/// the other slot is the network's.
///
/// **[localCarIndex] must be the same physical slot on both devices' idea
/// of who is who, or there is no race — only two people watching different
/// cars.** Found the hard way: an early version let each side call itself
/// car 0 and the other car 1, which staged two simulations that agreed on
/// every input and disagreed on every digest, because "car 0" was a
/// different grid slot — and therefore a different starting position and a
/// different set of collisions with the other car — on each side. Exactly
/// one of the two devices in a race must be handed `localCarIndex: 0` and
/// the other `localCarIndex: 1`; which one is a question for whatever
/// establishes the connection (the one who creates the room, say), not for
/// this class.
///
/// **Not a new mechanism — `net-01`'s, aimed at a real genre.** Everything
/// [NetSession] already does — input delay, prediction by the last frame,
/// rollback on a guess that turned out wrong — is unchanged; this class is
/// only the four functions a [RacingSimulation] needs to hand it, in the
/// shape net-01 already asks for, plus the ghost that stands in for the
/// remote car before the far side has said anything at all.
final class NetRace {
  NetRace({
    required RacingSimulation sim,
    required this.localCarIndex,
    required this.localInput,
    required NetTransport transport,
    int inputDelay = 3,
    int maxRollbackFrames = 20,
    void Function(int step, Snapshot after)? onSettled,
  }) : assert(
         localCarIndex == 0 || localCarIndex == 1,
         'net-03 is a two-player design; see net-01 for more than that',
       ),
       // ignore: prefer_initializing_formals
       _sim = sim {
    session = NetSession(
      transport: transport,
      captureLocalFrame: () => captureDriverFrame(localInput),
      applyAndStep: _applyAndStep,
      save: _sim.save,
      restore: _sim.restore,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      onSettled: onSettled,
    );
  }

  final RacingSimulation _sim;

  /// Which grid slot this device drives — see the class doc for why both
  /// devices in a race must agree on this rather than each assuming 0.
  final int localCarIndex;

  int get _remoteCarIndex => 1 - localCarIndex;

  /// This device's own driver — read once per [advance], the same moment
  /// `main.dart`'s own `_readDriver` would have been called at.
  final InputState localInput;

  late final NetSession session;

  /// Whether at least one frame from the far side has actually arrived.
  /// Before this, the remote car is the ghost described in the class doc,
  /// not the opponent — there is nothing yet to say the opponent has done
  /// anything at all.
  bool get connected => _connected;
  bool _connected = false;

  void _applyAndStep(Map<String, Object?> local, Map<String, Object?> remote) {
    // **Symmetric on purpose, found the hard way.** `local` reads empty for
    // the first `inputDelay` steps too — nothing has been captured long
    // enough ago yet to apply — and an earlier version ghosted only the
    // remote slot for that: this side's own car sat at a dead stop while
    // the *other* rolled forward on a guess. Two devices each doing that
    // for their own local car disagreed about which car had done which for
    // steps neither one would ever revisit — `net-01`'s messages are
    // tagged for the step they apply at, and the very first one is tagged
    // `inputDelay`, so step 0 through `inputDelay - 1` never get a message
    // addressed to them from either side, ever. Nothing corrects a step
    // nothing is ever sent for. Ghosting whichever slot is actually empty,
    // local or remote, keeps both devices agreeing on those steps instead.
    _driveOrGhost(local, _sim.inputs[localCarIndex]);
    if (remote.isNotEmpty) _connected = true;
    _driveOrGhost(remote, _sim.inputs[_remoteCarIndex]);
    _sim.step(1.0 / 60.0);
  }

  /// [frame] as driven, or — before it exists at all — a light, dead-straight
  /// throttle, so the car rolls forward on the grid rather than sitting
  /// still with its brake lights confusingly unlit.
  ///
  /// **Not [AiDriver].** An opponent that raced off decisively while its
  /// seat was still empty would read as a bug the moment the real player
  /// connected and inherited a car already a corner behind — the ghost
  /// promises nothing about where that car ends up, only that the grid
  /// looks occupied for the handful of steps neither side has anything
  /// real to say about yet.
  void _driveOrGhost(Map<String, Object?> frame, VehicleInput out) {
    if (frame.isEmpty) {
      out
        ..throttle = 0.3
        ..brake = 0.0
        ..handbrake = false
        ..steer = 0.0;
    } else {
      applyDriverFrame(frame, out);
    }
  }

  /// Advances by one fixed step — call once per fixed step, the same
  /// moment `RacingSimulation.step` would otherwise have been called at
  /// directly.
  void advance() => session.advance();
}
