## 0.2.0

- **`DashwireWire` carries bytes as they are** (`sendBytes`): a payload
  tagged with a leading nought byte, which JSON never starts with.
- **Breaking: asks for `flame_multiplayer` `^0.3.0`**, built on
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
