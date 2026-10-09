## 1.0.0-rc.1

- **`WebRtcTransport` carries bytes as binary messages** on the data
  channel (`sendBytes`), and delivers a binary message to `listenBytes`.
- **Breaking: `WebRtcTransport` delivers through `PeerWire.deliver`**, so
  any number of listeners hear it and each `listen` returns the
  `Registration` that takes it away.
- **Breaking: `WebRtcTransport.createOffer` and `awaitOffer` are
  `openOffering` and `openAnswering`**: a transport is a connection, opened
  asynchronously.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `signalling` is `signaling`. Only the Dart names changed: a file
  keeps the keys it was written with, and `dart fix` carries the renames.
- **Breaking: `WebRtcTransport` is a `PeerWire`**, and its signalling any
  `PeerWire`; `NetTransport` is gone.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

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
