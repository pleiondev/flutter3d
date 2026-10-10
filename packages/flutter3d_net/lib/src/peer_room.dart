/// Two machines on one wire: who is who, whether the other is there yet, and
/// separate conversations that do not hear each other.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration, SimulationVersion;

import 'peer_wire.dart';
import 'wire_hello.dart';

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
/// **A hello names its versions, and a mismatch is refused.** Beside what
/// the machine says about itself, each hello carries the protocol and the
/// [simulation] ([WireHello]). A machine that hears a hello it
/// cannot play with does not meet it: [refusal] says why, naming the
/// version to update to, and the room answers once more so the other
/// machine hears the same, then goes quiet. A game shows [refusal] and
/// leaves the room.
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
    this.simulation = SimulationVersion.engineOnly,
  }) : assert(slot == 0 || slot == 1, 'a room holds two: nought and one') {
    _hearing = wire.listen(_hear);
  }

  late final Registration _hearing;

  /// Stops hearing [wire]: the room's own listener goes, and the wire's
  /// other listeners keep theirs. The wire itself is left open.
  void leave() => _hearing.cancel();

  final PeerWire wire;

  /// Nought for whoever made the room, one for whoever joined it.
  final int slot;

  /// What this machine says about itself in its hello.
  final Map<String, Object?> about;

  /// Seconds between hellos while the other machine has not been heard.
  final double helloEvery;

  /// The game's simulation, which the other machine's has to equal — see
  /// [WireHello]. The engine's alone for a game that names none, which meets
  /// only another that names none.
  final SimulationVersion simulation;

  /// The versions this machine says hello with.
  WireHello get hello => WireHello(simulation: simulation);

  /// The versions the other machine said hello with; null until it has.
  WireHello? get peerHello => _peerHello;
  WireHello? _peerHello;

  /// Why the other machine cannot be played with, a sentence naming the
  /// version to update to; null while it can, or has not been heard.
  String? get refusal => _refusal;
  String? _refusal;

  /// The other machine's slot.
  int get otherSlot => 1 - slot;

  /// Whether this machine made the room.
  bool get isHost => slot == 0;

  /// What the other machine said about itself; null until it has.
  Map<String, Object?>? get peer => _peer;
  Map<String, Object?>? _peer;

  /// Whether the other machine has been heard, and can be played with.
  bool get hasMet => _peer != null;

  /// Whether the other machine has been heard at all, met or refused.
  bool get _heard => _peer != null || _refusal != null;

  final Map<String, _Channel> _channels = <String, _Channel>{};
  double _helloIn = 0.0;

  /// The conversation named [tag]: a [PeerWire] of its own, the same one
  /// every time it is asked, which any number of listeners may hear.
  PeerWire channel(String tag) {
    assert(tag != _helloTag, 'the hello is the room\'s own');
    return _channels[tag] ??= _Channel(this, tag);
  }

  /// Says hello while the other machine has not been heard. Once a fixed
  /// step.
  void step(double dt) {
    if (_heard) return;
    _helloIn -= dt;
    if (_helloIn > 0.0) return;
    _helloIn = helloEvery;
    _sayHello();
  }

  static const String _helloTag = 'hello';

  // Unreliable: it is said again until it is answered. `met` is whether
  // the other has been heard, refused or not, so a refusal is answered once
  // and not back and forth.
  void _sayHello() => wire.send(<String, Object?>{
    'tag': _helloTag,
    'met': _heard,
    'body': about,
    ...hello.toJson(),
  }, reliable: false);

  void _hear(Map<String, Object?> message) {
    final tag = message['tag'];
    final body = message['body'];
    if (tag is! String) return;
    // A hello is read whatever its body: one without (a build from before
    // the hello carried `about`) is a machine to refuse by name, and it
    // only learns which version to update to from the answer.
    if (tag == _helloTag) {
      final theirs = WireHello.read(message);
      _peerHello = theirs;
      final reason = hello.refusal(theirs);
      if (reason == null) {
        _peer = body is Map
            ? body.cast<String, Object?>()
            : const <String, Object?>{};
      } else {
        _refusal = reason;
      }
      // The other has not heard this one yet: joined after its last hello,
      // or lost the answer.
      if (message['met'] != true) _sayHello();
      return;
    }
    // Nothing but the hello passes from a machine that cannot be played
    // with. Before any hello a channel still hears: a frame can overtake
    // the hello it follows.
    if (_refusal != null || body is! Map) return;
    _channels[tag]?.deliver(body.cast<String, Object?>());
  }
}

final class _Channel extends PeerWire {
  _Channel(this._room, this._tag);

  final PeerRoom _room;
  final String _tag;

  @override
  int get slot => _room.slot;

  @override
  WireState get state => _room.wire.state;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      _room.wire.send(<String, Object?>{
        'tag': _tag,
        'body': message,
      }, reliable: reliable);
}
