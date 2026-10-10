# flutter3d_net

The network core of [flutter3d](https://flutter3d.pleion.dev), over
[flutter3d_sim](https://pub.dev/packages/flutter3d_sim): one wire between
machines, a room two machines meet in, and rollback for two machines or a
party. Peers exchange input frames every step, predict with the last frame
that arrived, and roll back when a confirmation disagrees. The session keeps
a count of dropped corrections that a game can show without having to
explain what a rollback is.

It is plain Dart. `PeerWire` is the only way out to a real network: send a
JSON-shaped map, reliably or not, and listen — any number of listeners, each
with the `Registration` that takes it away. `LoopbackWire` and
`LoopbackParty` stand in for it with a real delay and a real, seeded loss
rate, and the tests drive sessions through them instead of through a mock
that cannot lie about timing. `WebSocketTransport` goes through the relay,
and [flutter3d_net_webrtc](https://pub.dev/packages/flutter3d_net_webrtc)
peer to peer over a WebRTC data channel.

```dart
import 'package:flutter3d_net/flutter3d_net.dart';

// Over the engine's loop: its snapshots and its steps.
final rollback = EngineRollback(
  loop: loop,
  wire: seat.wire,
  players: seat.size,
  captureLocalFrame: () => {'move': stick.x.round()},
  applyFrames: (frames) => game.applyHands(frames),
);
// Once a fixed step, in place of loop.frame:
rollback.advance();
```

`RollbackSession` is the same rollback for a game whose state is not a loop's:
it takes four functions — capture this machine's hands, apply every slot's
and step, save, restore. `PeerRoom` is who is who, with a hello
(`WireHello`) that refuses a machine on another protocol or simulation.

**The engine's messages carry a reserved key.** A rollback's frames go as
`{"f3d": "rollback", "frames": …}` (`PeerWire.engineKey`), so a game's own
message on the same wire is never taken for one; a game never sets `f3d`.
That is protocol 3.

`bin/relay.dart` is the relay from `net-02`: one process, rooms identified by a
short code in the URL path, parties found by code or among strangers, and no
accounts. Its role is limited to signalling and a WebSocket fallback for
networks WebRTC cannot cross.
