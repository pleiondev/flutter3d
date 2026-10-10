## 1.0.0-rc.1

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
