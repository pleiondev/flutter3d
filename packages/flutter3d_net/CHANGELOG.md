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

* **The first publication.** The 0.6.0 below was a number this package carried
  inside the workspace; it never reached pub.dev. The whole shelf goes out on
  one number so that one number names one tree, and `^0.7.0` on any
  `flutter3d_*` package resolves against every other. `doc/boundary-0.7.0.md`
  lists the thirteen packages that begin at this release.
* **Two things the entry below leaves out, both here since the first commit.**
  `diffRuns` takes two `DigestTrace`s and a function per side that answers with
  the saved state at a step. `DigestTrace.divergenceFromHex` finds the first
  checkpoint that disagrees from the hex digests a `.f3drun` already carries,
  and `diffRuns` compares the two JSON trees at that one step and returns a
  `SnapshotDivergence`: the step, a dotted path such as `entities.7.health`,
  and the two values. It replays nothing itself, because only a genre's own
  package knows how to step its simulation. `WebSocketTransport` is the
  `NetTransport` over the relay for a platform or a NAT that a WebRTC data
  channel did not get through. It is built on `web_socket_channel` and not on
  `dart:io`, so the same class compiles for a browser, and while it is in use
  every game frame rides the relay.
* **The relay can be deployed from the package.** `deploy/Dockerfile` runs
  `bin/relay.dart` on port 8790 and is built from the repository root, since
  the package resolves `flutter3d_sim` inside the workspace.
  `deploy/flutter3d-net-relay.service` is a systemd unit for the same process.
* No code changed since 0.6.0 was written beyond what the formatter did. The
  floor on `flutter3d_sim` is `^0.7.0`.

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
