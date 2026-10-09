/// Two machines taking turns: one plays, the other watches it played.
library;

import 'dart:collection' show ListQueue;

import 'package:flutter3d_net/flutter3d_net.dart' show PeerWire;

/// Turns across two machines: the one holding the baton runs the game, and
/// the other replays what it is told.
///
/// **One machine at a time decides.** The holder runs its game as a game on
/// its own would — its input, its hitboxes, its rules — and each step
/// [tellFrame]s what the other needs to draw it, and [tellEvent]s whatever
/// was decided: what went down, what it scored, that the player was lost.
/// The watcher draws the frames and applies the events. Nothing has to be
/// deterministic and nothing is rolled back: what the watcher's own
/// scenery does between frames may differ a little, and what counts
/// arrives as a message from the machine that decided it.
///
/// **Replayed at the pace it was played.** Frames come over a real network
/// in bunches; the watcher's [step] hands on the events in order up to one
/// frame a step, so the replay runs as smoothly as the flight it shows,
/// a fraction of a second behind. A watcher more than [catchUpAfter] frames
/// behind — a stall, a slow machine — takes several in one step until it
/// is close again, rather than stay late for the rest of the turn.
///
/// **The baton goes with the state.** [pass] sends whatever the next turn
/// starts from — both players' scores and lives, whose turn it is — and
/// from then on this machine watches. The other machine's [onBaton] gets
/// that state and holds the baton. Only one machine sends frames at a time,
/// so the state never has two authors.
///
/// **Sent reliably, and put back in order here.** Everything goes as a
/// reliable message: an event lost is a target that went down on one
/// machine and not the other. Each is numbered as well, and one that
/// arrives ahead of its turn waits until the ones before it have come, so a
/// wire that keeps every message but not always their order — dashwire's
/// network simulator is one — replays the turn as it was played. A wire
/// that loses reliable messages is not one this can mend.
final class BatonStream {
  BatonStream(
    this.transport, {
    required bool holding,
    required this.onFrame,
    required this.onEvent,
    required this.onBaton,
    this.catchUpAfter = 4,
  }) : // A plain named parameter, not `this._holding`: the signature a user
       // reads, and the API snapshot, then spell no private name.
       // ignore: prefer_initializing_formals
       _holding = holding {
    transport.listen(_arrive);
  }

  final PeerWire transport;

  /// A frame of the other machine's turn, to draw.
  final void Function(Map<String, Object?> frame) onFrame;

  /// Something the other machine decided or asked, in the order it was
  /// sent among the frames.
  final void Function(Map<String, Object?> event) onEvent;

  /// The baton, and the state the turn starts from: this machine plays now.
  final void Function(Map<String, Object?> state) onBaton;

  final int catchUpAfter;

  /// Whether this machine is the one playing.
  bool get isHolding => _holding;
  bool _holding;

  /// What has arrived in order and not been handed on yet.
  final ListQueue<Map<String, Object?>> _inbox =
      ListQueue<Map<String, Object?>>();

  /// What arrived ahead of a message still on its way, by number.
  final Map<int, Map<String, Object?>> _early = <int, Map<String, Object?>>{};
  int _sent = 0;
  int _expected = 0;

  /// Frames waiting to be replayed.
  int get behind => _inbox.where((m) => m['k'] == _frame).length;

  static const String _frame = 'f';
  static const String _event = 'e';
  static const String _baton = 'b';

  /// This step of the holder's turn, for the watcher to draw.
  void tellFrame(Map<String, Object?> frame) {
    assert(_holding, 'only the machine playing tells the turn');
    _send(_frame, frame);
  }

  /// Something decided, or asked, for the other machine to act on.
  void tellEvent(Map<String, Object?> event) => _send(_event, event);

  /// Hands the game to the other machine, with the [state] its turn starts
  /// from; this one watches from now on.
  void pass(Map<String, Object?> state) {
    _holding = false;
    _send(_baton, state);
  }

  void _send(String kind, Map<String, Object?> body) =>
      transport.send(<String, Object?>{'k': kind, 'n': _sent++, 'body': body});

  void _arrive(Map<String, Object?> message) {
    final n = message['n'];
    if (n is! int || n < _expected) return;
    _early[n] = message;
    while (_early.containsKey(_expected)) {
      _inbox.add(_early.remove(_expected++)!);
    }
  }

  /// Takes the baton without it being passed: the first turn, or a new game,
  /// on the machine whose turn that is.
  void claim() => _holding = true;

  /// Hands on what arrived: every event while holding, and while watching
  /// the events and frames up to one frame — more when far behind. Once a
  /// fixed step.
  void step() {
    final queued = behind;
    var frames = queued > catchUpAfter ? queued - catchUpAfter + 1 : 1;
    while (_inbox.isNotEmpty) {
      final message = _inbox.removeFirst();
      final body = message['body'];
      if (body is! Map) continue;
      final said = body.cast<String, Object?>();
      switch (message['k']) {
        case _baton:
          _holding = true;
          onBaton(said);
        case _event:
          onEvent(said);
        case _frame:
          // A frame left over from a turn this machine has since taken is
          // a turn that is over.
          if (_holding) continue;
          onFrame(said);
          if (--frames <= 0) return;
      }
    }
  }
}
