import 'dart:async';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationVersion;

import 'peer_wire.dart';
import 'websocket_transport.dart';
import 'wire_hello.dart';

/// The relay's own words on the wire: what it names under
/// `PeerWire.engineKey`, and the events its messages are.
///
/// **Under the reserved key, as every engine message is.** A relay's
/// message is `{"f3d": "relay", "event": "welcome" | "full" | "left", …}`,
/// so a game's message with a `relay` field is never taken for one. A
/// message a machine wants to reach one slot alone travels in the route
/// envelope (`PeerWire.routeFrame`), `{"f3d": "route", "to": n, "body": …}`,
/// which the relay reads and nobody else sees: it hands the slot
/// `{"from": k, "body": …}` as it hands everything it forwards in a party,
/// `from` signed by the relay itself.
abstract final class RelayMessages {
  /// What the relay's own messages name under the reserved key.
  static const String relay = 'relay';

  /// The key a relay message names its event under.
  static const String event = 'event';

  /// The first thing a machine hears: its slot, the party's size and code,
  /// the owner's token for whoever opened it, and the relay's protocol.
  static const String welcome = 'welcome';

  /// Every player's slot is taken.
  static const String full = 'full';

  /// A machine went away, and which slot it held.
  static const String left = 'left';
}

/// A machine's place in a relay's party: its wire, the slot the relay gave
/// it, the party's [code] — the one to send a friend — and [full], which
/// completes once every player's slot is taken.
///
/// `owner` is the token the relay welcomed the machine that opened the
/// party with, and null for everybody else: it is what a spectator is let
/// in with ([joinParty]'s `owner`), so the host hands it only to whoever it
/// invites to watch.
///
/// A class rather than a record, so a seat can later carry more of what
/// the relay said without breaking a caller.
final class PartySeat {
  const PartySeat({
    required this.wire,
    required this.slot,
    required this.size,
    required this.code,
    required this.full,
    required this.socket,
    this.owner,
  });

  /// The wire to the other machines of the party.
  final PeerWire wire;

  /// This machine's slot.
  final int slot;

  /// How many players the party is for.
  final int size;

  /// The party's code.
  final String code;

  /// Completes once every player's slot is taken.
  final Future<void> full;

  /// The connection to the relay.
  final WebSocketTransport socket;

  /// The owner's token, for the machine that opened the party; null for
  /// everybody else.
  final String? owner;
}

/// Joins the party [code] on the relay at [relay] — `ws://host:port/` —
/// as a player, or with [watching] as a spectator, and answers once the
/// relay has said which slot is this machine's; a party of [size] when this
/// machine is the first to ask for [code].
///
/// The relay's own messages ([RelayMessages]) — the welcome, who left —
/// arrive on the socket, and the seat's wire passes on only what machines
/// sent, each with the slot the relay signed it with. [left] is told of a
/// slot whose machine went away.
///
/// **The welcome's protocol is read.** A relay of another protocol major,
/// or one from before its messages carried the reserved key, is refused
/// here: the future fails with a sentence naming the protocol to update to,
/// rather than playing on a relay whose messages this build misreads.
///
/// [terms] is what every machine in the party has to share, the physics
/// backend for one: the first to ask sets them, and the relay turns away a
/// machine asking with others — the future fails with the relay's reason.
///
/// [simulation] is the game's ([SimulationVersion], as `WireHello` carries
/// it), held the same way: a party runs one, and a machine on another is
/// turned away with a reason naming both. Null names none, which meets only
/// another that names none. The protocol this build speaks
/// always goes with it, and a relay of another major turns the machine away.
///
/// [owner] is what a spectator is let in with: the `owner` of the seat the
/// party's host was given. A relay turns a watcher away without it.
Future<PartySeat> joinParty(
  Uri relay,
  String code, {
  int size = 4,
  bool watching = false,
  String? owner,
  String terms = '',
  SimulationVersion? simulation,
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: <String>[watching ? 'watch' : 'party', code],
    queryParameters: <String, String>{
      if (!watching) 'size': '$size',
      if (watching) 'owner': ?owner,
      if (terms.isNotEmpty) 'terms': terms,
      ..._versions(simulation),
    },
  ),
  code: code,
  left: left,
  timeout: timeout,
);

/// Joins the party [code] on the relay at [relay] as an observer of the
/// authoritative simulation its slot 0 runs: the relay's observer path,
/// let in by the [owner]'s token as a watcher is, whatever [simulation]
/// it names. What it sends reaches the authority alone, and the
/// authority's messages addressed to its slot reach it alone; a
/// `SimulationObserver` on the seat's wire does the rest.
Future<PartySeat> observeParty(
  Uri relay,
  String code, {
  required String owner,
  SimulationVersion? simulation,
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: <String>['observe', code],
    queryParameters: <String, String>{'owner': owner, ..._versions(simulation)},
  ),
  code: code,
  left: left,
  timeout: timeout,
);

/// Finds a party of [size] for [game] on the relay at [relay] — one still
/// filling with strangers who asked for the same, or a new one — and
/// answers with this machine's seat in it. The seat's `code` is the
/// party's, for a friend to join by; its `full` completes when the last
/// player arrives, which is when a game should start.
///
/// [game] keeps games apart: two games on one relay, or one game's
/// circuits, never match each other's players. So do [terms] and
/// [simulation], as [joinParty] reads them: a match forms only between
/// builds on the same simulation.
Future<PartySeat> findParty(
  Uri relay, {
  required String game,
  int size = 4,
  String terms = '',
  SimulationVersion? simulation,
  void Function(int slot)? left,
  Duration timeout = const Duration(seconds: 10),
}) => _seat(
  relay.replace(
    pathSegments: const <String>['match'],
    queryParameters: <String, String>{
      'size': '$size',
      'game': game,
      if (terms.isNotEmpty) 'terms': terms,
      ..._versions(simulation),
    },
  ),
  left: left,
  timeout: timeout,
);

/// The address of the two-player room [code] on the relay at [relay] —
/// `ws://host:port/` — for [WebSocketTransport.connect], asking with
/// [terms], this build's protocol and the game's [simulation], as
/// [joinParty] does: a machine on another simulation is closed with
/// the relay's reason, which [WebSocketTransport.closed] answers.
Uri relayRoom(
  Uri relay,
  String code, {
  String terms = '',
  SimulationVersion? simulation,
}) => relay.replace(
  pathSegments: <String>['room', code],
  queryParameters: <String, String>{
    if (terms.isNotEmpty) 'terms': terms,
    ..._versions(simulation),
  },
);

/// The versions a relay is asked with: this build's protocol, and the
/// game's [simulation] when it names one.
Map<String, String> _versions(SimulationVersion? simulation) =>
    <String, String>{
      'protocol':
          '${WireHello.currentProtocolMajor}.${WireHello.currentProtocolMinor}',
      'simulation': ?simulation?.describe(),
    };

Future<PartySeat> _seat(
  Uri at, {
  String? code,
  void Function(int slot)? left,
  required Duration timeout,
}) async {
  final socket = await WebSocketTransport.connect(at);
  final welcomed =
      Completer<({int slot, int size, String code, String? owner})>();
  final full = Completer<void>();
  void Function(Map<String, Object?>)? onward;
  void refuse(String reason) {
    if (welcomed.isCompleted) return;
    welcomed.completeError(StateError('the relay at $at: $reason'));
    unawaited(socket.close());
  }

  socket.listen((Map<String, Object?> message) {
    if (message[PeerWire.engineKey] != RelayMessages.relay) {
      // A relay from before 3.1 said its welcome under a bare `relay` key.
      // Nothing else comes before the welcome, so this is that relay.
      if (!welcomed.isCompleted && message['relay'] == RelayMessages.welcome) {
        refuse(_relayRefusal(message['protocol'], bare: true)!);
        return;
      }
      onward?.call(message);
      return;
    }
    switch (message) {
      case {
            RelayMessages.event: RelayMessages.welcome,
            'slot': final int slot,
            'size': final int of,
          }
          when !welcomed.isCompleted:
        if (_relayRefusal(message['protocol']) case final reason?) {
          refuse(reason);
          return;
        }
        // A relay from before matchmaking names no code; the one asked
        // for is the party's.
        final named = message['code'];
        final owner = message['owner'];
        welcomed.complete((
          slot: slot,
          size: of,
          code: named is String ? named : code ?? '',
          owner: owner is String ? owner : null,
        ));
      case {RelayMessages.event: RelayMessages.full}:
        if (!full.isCompleted) full.complete();
      case {RelayMessages.event: RelayMessages.left, 'slot': final int slot}:
        left?.call(slot);
      default:
        // An event of a later minor: within a major the relay only adds,
        // and what this build does not know it passes over.
        break;
    }
  });
  // Turned away — a full party, other terms — before a welcome: say why
  // now rather than at the timeout.
  unawaited(
    socket.closed.then((String? reason) {
      if (welcomed.isCompleted) return;
      welcomed.completeError(
        StateError('the relay closed $at: ${reason ?? 'no reason given'}'),
      );
    }),
  );
  final seat = await welcomed.future.timeout(timeout);
  final wire = PeerWire.party(
    _Forwarding(socket, (listener) => onward = listener),
    slot: seat.slot,
  );
  return PartySeat(
    wire: wire,
    slot: seat.slot,
    size: seat.size,
    code: seat.code,
    full: full.future,
    socket: socket,
    owner: seat.owner,
  );
}

/// Why this build cannot play through a relay whose welcome named
/// [protocol] (`[major, minor]`), a sentence naming what to update; null
/// when it can. [bare] is a welcome from before the relay's messages
/// carried the reserved key, which this build cannot read whatever it
/// names.
String? _relayRefusal(Object? protocol, {bool bare = false}) {
  const ours =
      '${WireHello.currentProtocolMajor}.${WireHello.currentProtocolMinor}';
  final (major, theirs) = switch (protocol) {
    [final int major, final int minor] => (major, '$major.$minor'),
    _ => (null, null),
  };
  if (bare) {
    return 'it speaks protocol ${theirs ?? 'from before versions'}, whose '
        'messages this machine ($ours) does not read: update the relay to '
        'protocol $ours';
  }
  if (major == null) {
    return 'its welcome names no protocol and this machine speaks $ours: '
        'update the relay to protocol $ours';
  }
  if (major == WireHello.currentProtocolMajor) return null;
  return major > WireHello.currentProtocolMajor
      ? 'it speaks protocol $theirs and this machine $ours: update this game '
            'to protocol $major'
      : 'it speaks protocol $theirs and this machine $ours: update the relay '
            'to protocol ${WireHello.currentProtocolMajor}';
}

/// [inner]'s sending, and what [attach] hands on from behind the relay's
/// own messages delivered to whoever listens.
final class _Forwarding extends PeerWire {
  _Forwarding(this.inner, this.attach) {
    attach((message) => deliver(PeerDelivery(message: message)));
  }

  @override
  WireState get state => inner.state;

  @override
  Future<void> close() => inner.close();

  final PeerWire inner;
  final void Function(void Function(Map<String, Object?>) listener) attach;

  @override
  void send(PeerSend context) => inner.send(context);
}
