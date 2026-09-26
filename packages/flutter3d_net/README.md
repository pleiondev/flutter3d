# flutter3d_net

Rollback netcode over [flutter3d_sim](https://pub.dev/packages/flutter3d_sim),
part of [flutter3d](https://flutter3d.pleion.dev). Peers exchange input frames
every step, predict with the last frame that arrived, and roll back when a
confirmation disagrees. The session also keeps a count of dropped corrections
that a game can show without having to explain what a rollback is.

It is plain Dart. `NetSession` reads the caller's input through two callbacks
and never names a genre, a widget or a socket. `NetTransport` is the only way
out to a real network. `LoopbackTransport` stands in for it with a real fixed
delay and a real, seeded loss rate, and the test suite drives two sessions
through it instead of through a mock that cannot lie about timing. A real
transport, such as a relay over WebSocket or WebRTC through
[flutter3d_net_webrtc](https://pub.dev/packages/flutter3d_net_webrtc),
implements the same interface.

```dart
import 'package:flutter3d_net/flutter3d_net.dart';

final session = NetSession(
  transport: myTransport,
  captureLocalFrame: () => myLatestInput(),
  applyAndStep: (local, remote) => myGame.step(local, remote),
  save: () => myGame.snapshot(),
  restore: (snapshot) => myGame.restore(snapshot),
);
```

`bin/relay.dart` is the relay from `net-02`: one process, rooms identified by a
short code in the URL path, and no accounts. Its role is limited to signalling
and a WebSocket fallback for networks WebRTC cannot cross.
