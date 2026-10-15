## 0.9.0

- **On a 0.9 line of its own, outside the 1.0 promise.** Its signatures
  carry types of a package before 1.0 or of one that takes a major a year,
  so a release of that package would break a 1.0 API; on 0.x a minor may
  break, and says how here. SUPPORT.md names the four packages on this line.

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
