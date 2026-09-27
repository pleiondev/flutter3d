# flutter3d_net_webrtc

A [flutter3d_net](https://pub.dev/packages/flutter3d_net) `NetTransport` over
a real WebRTC data channel, part of [flutter3d](https://flutter3d.pleion.dev).
It is `net-02`'s primary transport. Traffic goes peer to peer, and the relay
carries only the SDP/ICE handshake, not every game frame.

It is a separate package instead of a file in `flutter3d_net` because
`flutter_webrtc` is a plugin with native code for each platform.
`flutter3d_net` is flat Dart and testable under plain `dart test`, and it is
built so that it never has to carry a dependency like that.

```dart
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_net_webrtc/flutter3d_net_webrtc.dart';

// Whoever created the room offers; the one who joined answers — both take
// the signalling transport (net-02's relay) that carries the handshake.
final transport = await WebRtcTransport.createOffer(signallingTransport);
final session = NetSession(transport: transport, /* captureLocalFrame, ... */);
```
