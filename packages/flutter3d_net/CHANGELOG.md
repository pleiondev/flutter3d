## 0.6.0

* **`net-01` in `doc/tooling-plan.md`.** `NetSession`: input frames per step,
  prediction by the last frame that arrived, rollback on a disagreeing
  confirmation, a dropped-correction count. `NetTransport` as the one
  interface a real network implements; `LoopbackTransport` with a real fixed
  delay and seeded loss for tests that drive two sessions against each other
  rather than a mock that cannot lie about timing.
* **`net-02`'s relay** (`bin/relay.dart`): rooms by a short code in the URL
  path, no accounts, signalling and a WebSocket fallback beside the WebRTC
  transport in `flutter3d_net_webrtc`.
* Plain Dart. Nothing here imports Flutter, and a relay process needs no SDK
  to run.
