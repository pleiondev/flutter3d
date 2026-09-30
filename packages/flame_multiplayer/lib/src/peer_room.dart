/// Two machines on one wire: who is who, whether the other is there yet, and
/// separate conversations that do not hear each other.
library;

import 'peer_wire.dart';

/// The room two machines meet in, over the one [PeerWire] a relay gives
/// them.
///
/// **Slots are the room's, not the machine's.** Whoever made the room is
/// slot nought on both machines and whoever joined it slot one. Each
/// machine calling itself nought would be two people each sure the other is
/// the guest — two games that never meet.
///
/// **A hello until the other has said one.** A relay passes on what arrives
/// while both are connected and nothing from before, so a single greeting
/// sent before the other machine joined is lost. [step] says hello every
/// [helloEvery] seconds until it hears one. Each hello says whether its
/// sender has heard the other yet, and one that has not is answered — so the
/// machine that joined second is heard too, and a lost answer is made up
/// for by the next hello it answers. What a machine says about itself — the class it plays, the car it drives —
/// rides in the hello and is [peer] on the other side.
///
/// **A conversation per [channel], none crossing.** The rollback of one
/// level counts its steps from nought, and frames of the last level still
/// on the wire when the next begins would land in it as steps it has not
/// run yet. Each channel hears only messages sent on its own tag, and a
/// channel nobody is listening to drops what arrives.
final class PeerRoom {
  PeerRoom(
    this.wire, {
    required this.slot,
    this.about = const <String, Object?>{},
    this.helloEvery = 0.5,
  }) : assert(slot == 0 || slot == 1, 'a room holds two: nought and one') {
    wire.listen(_hear);
  }

  final PeerWire wire;

  /// Nought for whoever made the room, one for whoever joined it.
  final int slot;

  /// What this machine says about itself in its hello.
  final Map<String, Object?> about;

  final double helloEvery;

  /// The other machine's slot.
  int get otherSlot => 1 - slot;

  /// Whether this machine made the room.
  bool get isHost => slot == 0;

  /// What the other machine said about itself; null until it has.
  Map<String, Object?>? get peer => _peer;
  Map<String, Object?>? _peer;

  /// Whether the other machine has been heard.
  bool get met => _peer != null;

  final Map<String, void Function(Map<String, Object?>)> _listeners =
      <String, void Function(Map<String, Object?>)>{};
  double _helloIn = 0.0;

  /// The conversation named [tag]: a [PeerWire] of its own.
  PeerWire channel(String tag) {
    assert(tag != _helloTag, 'the hello is the room\'s own');
    return _Channel(this, tag);
  }

  /// Says hello while the other machine has not. Once a fixed step.
  void step(double dt) {
    if (met) return;
    _helloIn -= dt;
    if (_helloIn > 0.0) return;
    _helloIn = helloEvery;
    _sayHello();
  }

  static const String _helloTag = 'hello';

  // Unreliable: it is said again until it is answered.
  void _sayHello() => wire.send(<String, Object?>{
    'tag': _helloTag,
    'met': met,
    'body': about,
  }, reliable: false);

  void _hear(Map<String, Object?> message) {
    final tag = message['tag'];
    final body = message['body'];
    if (tag is! String || body is! Map) return;
    final said = body.cast<String, Object?>();
    if (tag == _helloTag) {
      _peer = said;
      // The other has not heard this one yet: joined after its last hello,
      // or lost the answer.
      if (message['met'] != true) _sayHello();
      return;
    }
    _listeners[tag]?.call(said);
  }
}

final class _Channel implements PeerWire {
  _Channel(this._room, this._tag);

  final PeerRoom _room;
  final String _tag;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      _room.wire.send(<String, Object?>{
        'tag': _tag,
        'body': message,
      }, reliable: reliable);

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _room._listeners[_tag] = onMessage;
}
