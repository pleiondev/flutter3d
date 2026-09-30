/// Two machines playing one simulation at once, each with its own player.
library;

import 'peer_wire.dart';
import 'rollback_session.dart';

/// One simulation run on two machines in step, each driving its own player,
/// through a [RollbackSession].
///
/// **Not a new mechanism.** The session does the input delay, the guess of
/// the far side's hands by the last frame that arrived, and the rollback
/// when a guess was wrong. This is what a game hands it, for two players in
/// the room's [PeerRoom] slots: the frames arrive as a pair indexed by slot,
/// so the same player's hands go to the same player on both machines.
///
/// **A game that can be saved and loaded is all it asks.** [save] and
/// [restore] have to take the whole of it — whatever was born or buried
/// since, as well — because a rollback past a birth is a restore into a
/// world that has one too many.
///
/// **An ending both agree on.** A step that has run may still rest on a
/// guess and be taken back; a game over on a guess is a game over one
/// machine then takes back. [endsAt] names what an ending looks like in a
/// saved state, and [agreedEnd] is the first settled step that shows one,
/// with the state it left — the same step on both machines, since it is the
/// same settled run. A game that goes on from its end (to a next level, a
/// rematch) goes on from [agreedEnd] on both, not from wherever each ran on
/// past it.
///
/// **Keep advancing after the end,** for a while: the other machine may
/// still be waiting for this one's last frames before it can settle the
/// same step.
final class RollbackPlay<S> {
  RollbackPlay({
    required PeerWire wire,
    required this.localSlot,
    required this.capture,
    required this.applyAndStep,
    required S Function() save,
    required void Function(S state) restore,
    this.endsAt,
    this.onSettled,
    int inputDelay = 3,
    int maxRollbackFrames = 20,
  }) : assert(
         localSlot == 0 || localSlot == 1,
         'two machines, one player each: the room decides which',
       ) {
    session = RollbackSession<S>(
      wire: wire,
      captureLocalFrame: capture,
      applyAndStep: _applyAndStep,
      save: save,
      restore: restore,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      onSettled: _settled,
    );
  }

  /// Which player this machine drives.
  final int localSlot;

  /// This machine's player's hands for the step about to be captured. What
  /// goes in is compared by equality and applied on both machines, so it
  /// wants whole numbers rather than doubles read off a stick.
  final Map<String, Object?> Function() capture;

  /// Writes both players' hands — [bySlot] nought and one — into the game
  /// and runs one fixed step of it. Called again for a step being
  /// corrected. An empty frame is a player not heard from yet.
  final void Function(List<Map<String, Object?>> bySlot) applyAndStep;

  /// Whether a settled state is an ending.
  final bool Function(S after)? endsAt;

  /// Told of every settled step: what a test compares two machines by.
  final void Function(int step, S after)? onSettled;

  late final RollbackSession<S> session;

  /// Whether the other machine's hands have arrived yet.
  bool get connected => _connected;
  bool _connected = false;

  /// The first settled ending and the step it came on; null until there is
  /// one.
  ({int step, S after})? get agreedEnd => _agreedEnd;
  ({int step, S after})? _agreedEnd;

  /// Captures, sends and runs one step. Once a fixed step.
  void advance() => session.advance();

  void _applyAndStep(Map<String, Object?> local, Map<String, Object?> remote) {
    if (remote.isNotEmpty) _connected = true;
    applyAndStep(
      localSlot == 0
          ? <Map<String, Object?>>[local, remote]
          : <Map<String, Object?>>[remote, local],
    );
  }

  void _settled(int step, S after) {
    onSettled?.call(step, after);
    if (_agreedEnd != null) return;
    if (endsAt?.call(after) ?? false) _agreedEnd = (step: step, after: after);
  }
}
