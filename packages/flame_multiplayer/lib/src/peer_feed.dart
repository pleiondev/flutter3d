/// The other machine's latest word about itself, for a ghost or a score.
library;

import 'package:flutter3d_net/flutter3d_net.dart' show PeerSend, PeerWire;

/// Two machines playing their own games side by side — a race over the same
/// course — each telling the other where it is.
///
/// **Only the latest counts.** Nothing is replayed, stepped or agreed on:
/// each machine [tell]s its own state now and then, and [latest] is the last
/// the other one told. A late message is a ghost a little behind; a lost one
/// is made up for by the next. So it asks nothing of the wire, and nothing
/// of the game but what to say about itself.
///
/// **The engine's messages, behind the room's hello.** Each is
/// `{"f3d": "feed", "n": …, "body": …}`, under the wire's reserved key, so
/// a game's message — or a turn's, on a shared wire — is never taken for
/// the other machine's word. Two machines meet in a `PeerRoom` and tell on
/// one of its channels (`room.channel('ghost')`), so a machine on another
/// protocol or simulation is refused by the room's hello.
final class PeerFeed {
  /// A feed over [transport], listening from now on, that sends on one
  /// [tell] in [every]. Asserts [every] is above nought.
  PeerFeed(this.transport, {this.every = 1}) : assert(every > 0) {
    transport.listen((Map<String, Object?> message) {
      if (message[PeerWire.engineKey] != _feed) return;
      final count = message['n'];
      final body = message['body'];
      if (count is! int || body is! Map) return;
      // Out of order on a wire that reorders: older than what is shown.
      if (count <= _heardCount) return;
      _heardCount = count;
      _latest = body.cast<String, Object?>();
    });
  }

  /// The wire both machines tell on, unreliably; a game's own messages on
  /// it pass by untouched.
  final PeerWire transport;

  /// What the feed's messages name under [PeerWire.engineKey].
  static const String _feed = 'feed';

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
    transport.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: _feed,
          'n': _toldCount++,
          'body': state(),
        },
        reliable: false,
      ),
    );
  }
}
