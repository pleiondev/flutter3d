/// The other machine's latest word about itself, for a ghost or a score.
library;

import 'peer_wire.dart';

/// Two machines playing their own games side by side — a race over the same
/// course — each telling the other where it is.
///
/// **Only the latest counts.** Nothing is replayed, stepped or agreed on:
/// each machine [tell]s its own state now and then, and [latest] is the last
/// the other one told. A late message is a ghost a little behind; a lost one
/// is made up for by the next. So it asks nothing of the wire, and nothing
/// of the game but what to say about itself.
final class PeerFeed {
  PeerFeed(this.transport, {this.every = 1}) : assert(every > 0) {
    transport.listen((Map<String, Object?> message) {
      final count = message['n'];
      final body = message['body'];
      if (count is! int || body is! Map) return;
      // Out of order on a wire that reorders: older than what is shown.
      if (count <= _heardCount) return;
      _heardCount = count;
      _latest = body.cast<String, Object?>();
    });
  }

  final PeerWire transport;

  /// Tells every this many calls to [tell]: fewer messages, a ghost that
  /// moves in steps.
  final int every;

  /// What the other machine last said; null until it has said anything.
  Map<String, Object?>? get latest => _latest;
  Map<String, Object?>? _latest;

  int _toldCount = 0;
  int _heardCount = -1;
  int _calls = 0;

  /// Tells [state] to the other machine, or skips it to keep to [every].
  /// [state] is built only when it is going to be sent.
  void tell(Map<String, Object?> Function() state) {
    if (_calls++ % every != 0) return;
    transport.send(<String, Object?>{
      'n': _toldCount++,
      'body': state(),
    }, reliable: false);
  }
}
