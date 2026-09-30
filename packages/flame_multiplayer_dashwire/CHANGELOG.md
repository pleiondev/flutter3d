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
