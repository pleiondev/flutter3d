# flutter3d_net_webrtc

A [flutter3d_net](https://pub.dev/packages/flutter3d_net) `NetTransport` over
a real WebRTC data channel — part of
[flutter3d](https://flutter3d.pleion.dev): `net-02`'s primary transport,
peer to peer, with the relay carrying only the SDP/ICE handshake rather
than every game frame.

Its own package rather than a file in `flutter3d_net`, because
`flutter_webrtc` is a real plugin with native code per platform — a
dependency `flutter3d_net`'s own claim (flat Dart, testable under plain
`dart test`) is built specifically not to carry.

```dart
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_net_webrtc/flutter3d_net_webrtc.dart';

// Whoever created the room offers; the one who joined answers — both take
// the signalling transport (net-02's relay) that carries the handshake.
final transport = await WebRtcTransport.createOffer(signallingTransport);
final session = NetSession(transport: transport, /* captureLocalFrame, ... */);
```
