## 0.7.0

* **The first publication, and no code since 0.6.0 was written.** That number
  was carried inside the workspace and never reached pub.dev. 0.7.0 is the one
  number the whole shelf goes out on, so `^0.7.0` here resolves against
  `^0.7.0` on any other `flutter3d_*` package; `doc/boundary-0.7.0.md` has the
  list. What changed is the floor on `flutter3d_net`, now `^0.7.0`, and the
  formatter's line breaks in `webrtc_transport.dart`.
* Worth knowing before depending on it, since the entry below does not say:
  this is the one package of the two that needs Flutter, through
  `flutter_webrtc` `^1.6.2`, and `flutter3d_net` stays plain Dart because of
  that split. The connection is configured with one public STUN server and no
  TURN, so a NAT that neither side's candidates get through is
  `WebSocketTransport`'s case. `ready` completes when the data channel opens,
  and the channel is unordered.

## 0.6.0

* **`net-02`'s primary transport.** `WebRtcTransport.createOffer`/`awaitOffer`
  set up a real `RTCPeerConnection` and a data channel over it, exchanging
  SDP/ICE through whatever `NetTransport` carries signalling (`net-02`'s
  relay) — game frames afterwards go peer to peer, never through the relay.
