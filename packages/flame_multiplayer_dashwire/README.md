# flame_multiplayer_dashwire

A [dashwire](https://pub.dev/packages/dashwire) connection as a
[`flame_multiplayer`](https://pub.dev/packages/flame_multiplayer) wire.

```dart
final wire = DashwireWire(await connectWebSocket(roomUri));
final room = PeerRoom(wire, slot: 0);
```

A reliable message goes on dashwire's reliable channel and an unreliable one
on its unreliable channel, so a rollback frame or a ghost's position is not
held up behind a lost packet on a transport that has both. Messages travel
as JSON in UTF-8.

dashwire's own `LoopbackConnection` and `SimulatorConnection` work too, and
the simulator — latency, jitter, loss and duplication — is a harder test than
`flame_multiplayer`'s loopback: this package's tests run a rollback, a
handshake and a turn through it.

dashwire's WebSocket sends binary frames, and `flutter3d_net`'s relay passes
them on as they are, so two games connected through dashwire meet in a room
of that relay. One test starts the relay and checks exactly that.

A package of its own so that `flame_multiplayer` keeps no dependencies, and
a game that talks through `flutter3d_net` does not carry dashwire as well.
