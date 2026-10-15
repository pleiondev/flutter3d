## 1.0.0-rc.1+1

- **The engine's number, outside the 1.0 promise.** Its signatures carry
  `WireConnection` from dashwire, which is before 1.0, so a dashwire
  release may break this API in a minor, and the break is labelled here.
  SUPPORT.md names the four packages outside the promise; the number says
  which engine release this one goes with, and every pin the engine writes
  on it is the engine's own.

## 1.0.0-rc.1

**The version jumps from 0.1.0 to 1.0.0-rc.1**, with `flame_multiplayer`,
which this adapter asks for as `^1.0.0-rc.1`. That package stands on
`flutter3d_net`'s 1.0 line now, and pub asks a package that depends on a
pre-release to be one itself. The 0.1.1 and 0.2.0 entries were never
published; everything below up to 0.1.0 ships in this release.

- **Breaking: `DashwireWire.send` and `sendBytes` take one context**, a
  `PeerSend` and a `PeerSendBytes`, as every `PeerWire` does now.
- **`DashwireWire` carries bytes as they are** (`sendBytes`): a payload
  tagged with a leading nought byte, which JSON never starts with.
- **Breaking: asks for `flame_multiplayer` `^1.0.0-rc.1`**, built on
  `flutter3d_net`'s wire. `DashwireWire` delivers through
  `PeerWire.deliver`, so any number of listeners hear it and each
  `listen` returns the `Registration` that takes it away; it speaks
  protocol 3.

## 0.1.1

**Asks for `flame_multiplayer` `^0.2.0`**, the release with parties of more
than two, one rollback and a hello that names its protocol and simulation.
`DashwireWire` `extends` `PeerWire` now, which is a base class, and says its
`state`; the versions travel as JSON like the rest of the hello, and a test
holds two builds on different simulations apart over dashwire.

## 0.1.0

**A dashwire connection carries `flame_multiplayer`.** `DashwireWire` makes a
`WireConnection` — dashwire's WebSocket, its loopback, its network simulator
— into a `PeerWire`. A reliable message goes on dashwire's reliable channel
and an unreliable one on its unreliable channel, so a rollback frame or a
ghost's position is never held up behind a lost packet on a transport that
has both. Messages travel as JSON in UTF-8.

dashwire's WebSocket speaks binary frames, which `flutter3d_net`'s relay
passes on as they are: two games connected to a room of that relay through
dashwire meet in it.
