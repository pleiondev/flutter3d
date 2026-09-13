# flutter3d_net

Rollback netcode over [flutter3d_sim](https://pub.dev/packages/flutter3d_sim),
part of [flutter3d](https://flutter3d.pleion.dev): input frames exchanged
per step, prediction by the last frame that arrived, a rollback when a
confirmation disagreed, and a dropped-correction count a game can show
without asking what a rollback is.

**Plain Dart.** `NetSession` reads a caller's input through two callbacks
and never names a genre, a widget or a socket. `NetTransport` is the one
door to a real network; `LoopbackTransport` stands in for it with a real
fixed delay and a real, seeded loss rate, which is what the test suite
drives two sessions through rather than a mock that cannot lie about
timing. A real transport — a relay over WebSocket, or WebRTC through
[flutter3d_net_webrtc](https://pub.dev/packages/flutter3d_net_webrtc) —
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

`bin/relay.dart` is `net-02`'s relay: one process, rooms by a short code
in the URL path, no accounts, its role narrowed to signalling and a
WebSocket fallback for a network WebRTC cannot cross.
