## 1.0.0-rc.1+1

- **The wire is a snapshot.** `api/flutter3d_net.wire` lists every message
  the engine and its relay send, by the keys that tell it apart and the keys
  it carries, and every address the relay answers at, with a golden JSON
  for each message under `test/fixtures/wire/v3/`. A test holds the
  messages the code sends to it in literals, not the constants the code
  names them by, and the structure check holds it to the base protocol 3
  was recorded with: within a major a message may gain a key, never lose
  one.
- **Breaking: results that were records are final classes.**
  `RollbackSession` answered or held a record, which can never gain a field.
  Each answers a final class now, with the record's field names (a
  positional `$1` has a name of its own), `==` and `hashCode`. A field read
  compiles as before; a destructuring pattern names the class, and
  `flutter3d_build:migrate` rewrites the `$1` reads.

- **Breaking: protocol 3.1, and the relay speaks under the reserved key.**
  `WireHello.currentProtocolMinor` is 1. The relay's welcome, `full` and
  `left` are `{"f3d": "relay", "event": …}` (`RelayMessages`, new) where
  they were a bare `{"relay": …}`, which a game's message with a `relay`
  field could be taken for. A message for one slot goes in the route
  envelope `{"f3d": "route", "to": n, "body": …}` (`PeerWire.routeFrame`,
  new): `PeerWire.party` puts an engine message with a `to` in it, as the
  observer's are, and a game's own `to` now reaches everybody instead of
  being routed by the relay. Protocol 3.0 never left a pre-release, so no
  released machine speaks the old shapes.
- **The relay signs what it forwards in a party.** Every message gets
  `from` set to the slot of the socket it came from, whatever the socket
  wrote there, so one machine cannot speak as another; a binary frame goes
  as the party wire's bytes frame inside a signed envelope, and a frame that
  is neither JSON nor bytes is dropped. A watcher's slot is the lowest one
  free, so two watchers never share one after somebody left.
- **`joinParty` reads the welcome's protocol.** A relay of another major,
  one whose welcome names no protocol, or one from before its messages
  carried the reserved key is refused with a sentence naming what to
  update, where the seat used to wait out its timeout or play on a relay it
  misread.
- **`WireHello.engineOnly`**: the hello of a game that names no
  simulation, for a default parameter.

## 1.0.0-rc.1

- **Breaking: a rollback step is handed a `RollbackStep`.**
  `RollbackSession.applyAndStep` and `EngineRollback.applyFrames` take one
  `RollbackStep` (new): the `step`, every slot's `frames`, `statusOf(slot)`
  as an `InputStatus` (new, an open class: `confirmed`, `predicted`,
  `disconnected`) and whether the step is `resimulated`, where they took
  the frames alone. A game can freeze a player who left, hold back a
  predicted hit's sound and show whom it waits for; `(frames) => …` is
  `(step) => …` reading `step.frames`.
- **Breaking: the rollback's and the observer's callbacks take one object
  each.** `RollbackSession.onSettled` and `EngineRollback`'s take a
  `SettledStep` (new: the step, the state it ended in, the frames), and
  their `onMessage` the wire's `PeerMessage`; `SimulationObserver.restore`
  takes an `ObserverRestore` (new: the start and its step). A field added
  to one breaks nobody, where a parameter added to the call broke every
  listener.
- **Breaking: `PartySeat` is a class** with the same fields, so a seat
  can later carry more of what the relay said.
- **A rollback says what it costs.** `RollbackSession.stats` reads a
  `RollbackStats` (new): the steps run, the rollbacks, the steps run again
  with the median, 99th percentile and worst time of each, the steps that
  settled on a guess, and `droppedCorrectionShare`; `toJson` and `fromJson`
  carry one machine's line of a party's report. The time is read off the
  new `elapsed` clock parameter, a monotonic stopwatch unless a test hands
  another. `tool/rollback_party.dart` plays a party of N machines over a
  loopback with a round trip and loss and writes the report
  `tool/rollback_report.dart` renders and holds to `--fail-on`.
- **`droppedCorrections` counts corrections lost, once each.** A late copy
  of a frame already had, which redundancy sends on purpose, used to count
  every time it came past the window, and a frame that agreed with the
  guess counted too; now only a frame that contradicts the guess its step
  settled on does. A frame past the window also becomes the slot's latest
  word, so a wire slower than the window no longer guesses the empty hand
  forever.
- **Breaking: a wire's hooks and listeners take one object each.**
  `PeerWire.send` takes a `PeerSend` (`message`, `reliable`), `sendBytes` a
  `PeerSendBytes`, `deliver` a `PeerDelivery` (`message`, `from`) and
  `deliverBytes` a `PeerBytesDelivery`; a `listenFrom` listener hears a
  `PeerMessage` (`from`, `message`) and a `listenBytes` one `PeerBytes` (all
  new). An adapter or a listener written against 1.0 then keeps compiling
  when a minor hands it more: a channel, a priority, when it arrived.
- **Observing an authoritative simulation.** `ObserverFeed` sends each
  `SimulationObserver` the run's tape (input frames with their telemetry)
  where its profile is bit-exact and the observer runs the same simulation,
  and each step's published state (poses, probe readings) otherwise, each
  observer its own `ObserverFilter`'s probes; `ObserverMode` and
  `ObserverSnapshot` (full, with delta named for a later minor) are open
  sets, and `ObserverMessages` the engine's message names. The relay's
  `/observe/<code>` path (`observeParty`) lets an observer in by the
  owner's token on any simulation, hears it only at the authority, and
  hands it what the authority addresses to its slot.
- **`LoopbackWire.pair()` returns a `LoopbackPair`**, `first` in slot
  nought and `second` in slot one, where it returned a record: take it apart
  as `final LoopbackPair(first: a, second: b) = LoopbackWire.pair()`.

- **Breaking: a party has an owner, and only who it invites watches.** The
  relay welcomes the machine that opens a party with an `owner` token,
  `PartySeat.owner`; `joinParty(watching: true, owner:)` presents it, and a
  watcher without it is closed. A party holds at most eight watchers, the
  relay at most 4096 rooms and parties, and each request is served on its
  own rather than after the one before.

- **A rollback session told another slot than its wire's hears the sender
  right.** Both ends of a `/room/<code>` WebSocket are slot nought; the
  joining machine, told slot one, took every frame for its own and dropped
  it. `RollbackSession.maxStepsAhead` (600) bounds the frames kept for later
  steps; the ones past it are counted in `droppedEarly`.

- **A hello without a body is answered.** `PeerRoom` reads its versions and
  says which to update to, rather than dropping it and leaving an older
  machine waiting. The relay's refusal for another simulation starts with
  what to update to, so the 123-byte close reason keeps it, and tells the
  newer machine's party when it is the party that is behind.

- **Breaking: `Registration`, `SimulationVersion` and `firstDifferingPath` are
  not re-exported.** They are `flutter3d_foundation`'s,
  `flutter3d_plugin_api`'s and `flutter3d_sim`'s.

- **A wire carries bytes**: `PeerWire.sendBytes`, `listenBytes` and
  `deliverBytes`. By default the bytes go as base64 inside a JSON frame
  (`{"f3d": "bytes", "b": …}`), so every wire carries them; `LoopbackWire`,
  `LoopbackParty` and `WebSocketTransport` (a binary frame) carry them as
  they are. A byte message never reaches `listen`, nor a message
  `listenBytes`. Still protocol 3.
- **Breaking: the network core lives here.** `PeerWire`, `WireState`,
  `LoopbackWire`, `LoopbackParty`, `PeerRoom`, `WireHello` and
  `RollbackSession` moved from `flame_multiplayer`, a 0.x package, to this
  one, on the 1.0 line; this package no longer depends on
  `flame_multiplayer`, which is built on it now. The names were already
  exported from here, so an import of `flutter3d_net` is unchanged, and
  `flame_multiplayer` re-exports them, so an import of it compiles too.
- **Breaking: a wire has several listeners.** `PeerWire.listen` and
  `listenFrom` add a listener and return the `Registration` that takes it
  away, where a second call replaced the first — so a `RollbackSession`
  silently took the wire over from the `PeerRoom` on it. An adapter no
  longer writes `listen`: it calls `deliver` with each message that
  arrives. `PeerWire`'s constructor is no longer `const`.
  `PeerRoom.channel` hands back the same channel for a tag every time.
- **Breaking: protocol 3, and the engine's messages carry a reserved key.**
  A rollback's frames are `{"f3d": "rollback", "frames": …}`
  (`PeerWire.engineKey`, `RollbackSession.messageKind`), where they were
  told apart by a bare `frames` field a game's own message could carry — a
  spectator's tape did. `WireHello.currentProtocolMajor` is 3, so a
  protocol-2 machine is refused with the version to update to.
  `RollbackSession.dispose` and `PeerRoom.leave` stop hearing the wire.
- **Breaking: one transport and one rollback.** `NetTransport`,
  `NetTransportWire`, `LoopbackTransport` and `NetSession` are gone: every
  transport is a `flame_multiplayer` `PeerWire` (`WebSocketTransport` is
  one), a test's is `LoopbackWire`, and the rollback is `RollbackSession`
  for two machines or a party. `EngineRollback` runs it over an
  `EngineLoop`'s snapshots and steps.
- **Breaking: `joinParty`, `findParty` and `relayRoom` take a
  `SimulationVersion simulation`**, not an `int`, and the relay holds its
  description.
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

- **The relay holds parties.** `/party/<code>?size=N` hands out the slots
  and says who left, and `/watch/<code>` admits spectators. `joinParty` is
  the client.

- **Strangers find each other.** `/match?size=N&game=<name>` seats a
  machine in the party still filling for that game and size, or opens a
  new one under a fresh code, and tells everyone `{"relay": "full"}` when
  the last player arrives; a full party is matched no further. `findParty`
  is the client, and a seat now carries the party's `code`, for a friend
  to join by, and `full`.

- **Machines that cannot agree are kept apart.** `terms=<text>` on a room,
  a party or a match is what every machine there has to share, the physics
  backend for one. The first machine sets them, and one asking with others
  is closed with a reason that names both. Matchmaking keys on them.
  `joinParty` and `findParty` take `terms`, and fail with the relay's
  reason as soon as it closes them, not at the timeout.
  `WebSocketTransport.closed` answers that reason.

- **A match forms only between builds on one simulation version.**
  `simulation=<n>` on a room, a party or a match is held like terms: the
  first machine sets it, one on another version is closed with a reason
  that names the version to update to, and matchmaking keys on it.
  `joinParty` and `findParty` take `simulationVersion`, and `relayRoom`
  builds a room's address with it for `WebSocketTransport.connect`. Each
  also sends `protocol=<major>.<minor>`: the relay turns away another
  major with the major to update to and lets any minor of its own in,
  since within a major the protocol only grows. A party's welcome names
  the relay's protocol.

- `firstDifferingPath` lives in `flutter3d_sim` now; this package exports
  it from there, so imports of it keep working.

Its `flutter3d_*` dependencies ask for `^1.0.0`, and it asks for `flame_multiplayer` `^0.2.0`.

## 0.8.1

**Any transport here carries `flame_multiplayer`.** `NetTransportWire` makes
a `NetTransport` — the relay's `WebSocketTransport`, a WebRTC channel, the
test loopback — into that package's `PeerWire`, so its room, rollback play,
turns and ghost run over the relay this package ships. The dependency goes
this way round: `flame_multiplayer` depends on nothing, and the adapter
lives with the transports it adapts.

**One rollback in the repository, not two.** `NetSession` runs on
`flame_multiplayer`'s `RollbackSession` now, with a `Snapshot` for its state.
Its constructor, its defaults and the messages on the wire are what they
were, so a peer on an older build still plays against a newer one.
`droppedCorrections` reads and writes through to the shared session, as it
did as a field.

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
