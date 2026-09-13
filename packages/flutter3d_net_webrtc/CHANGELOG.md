## 0.6.0

* **`net-02`'s primary transport.** `WebRtcTransport.createOffer`/`awaitOffer`
  set up a real `RTCPeerConnection` and a data channel over it, exchanging
  SDP/ICE through whatever `NetTransport` carries signalling (`net-02`'s
  relay) — game frames afterwards go peer to peer, never through the relay.
