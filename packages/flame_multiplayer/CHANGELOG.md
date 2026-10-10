## 0.3.0

- **A spectator presents the party owner's token.** See `flutter3d_net`:
  `joinParty(watching: true, owner: host.owner)`.

- **Breaking: `Registration` and `SimulationVersion` are not re-exported.**
  They are `flutter3d_foundation`'s and `flutter3d_plugin_api`'s; the wire,
  the room and the rollback still are, from `flutter3d_net`.

- **Breaking: the network core moved to `flutter3d_net`.** `PeerWire`,
  `WireState`, `LoopbackWire`, `LoopbackParty`, `PeerRoom`, `WireHello` and
  `RollbackSession` are `flutter3d_net`'s, on its 1.0 line, and this
  package depends on it. They are re-exported from here, so an import of
  `flame_multiplayer` keeps compiling; what stays is the turns
  (`BatonStream`), the feed (`PeerFeed`) and the party's spectator and
  authority (`PartyTape`, `AuthorityServer`, `PredictingClient`).
- **Breaking: a wire has several listeners, and the rollback's messages a
  reserved key** — `flutter3d_net` 1.0.0-rc.1 has the detail: `listen`
  returns a `Registration`, an adapter calls `deliver`, and the protocol is
  3. A spectator's tape is no longer taken for a rollback's frames.

## 0.2.0

- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `BatonStream.holding` is `isHolding`; `PeerRoom.met` is `hasMet`;
  `RollbackSession.connected` is `isConnected`;
  `RollbackSession.resimulating` is `isResimulating`. `dart fix` carries the
  renames.
- **Breaking: `BatonStream.take` is `claim`.**
- **Breaking: `BatonStream` takes `holding:` as a plain parameter**, in its
  signature only. It was declared as `this._holding`, a private named
  parameter, so the signature and the API snapshot spelled a private field.
  Calls are unchanged: they always passed `holding:`.

- **Breaking: one transport, `PeerWire`, and one rollback,
  `RollbackSession`.** `PeerWire` is an `abstract base class` an adapter
  `extends`, with `slot`, `state`, `listenFrom` and `close` beside `send`
  and `listen`; `PartyWire` folded into it (`PeerWire.party` over a relay's
  party room). `RollbackSession` rolls back for two to thirty-two machines,
  hands `applyAndStep` every slot's frame by slot, and keeps the agreed
  ending; `RollbackPlay` and `PartyRollback` are gone. `LoopbackWire`'s two
  ends are slots nought and one.
- **Breaking: the hello carries the whole `SimulationVersion`** (protocol
  2): the engine's number, the genre's and every simulation plugin's.
  `PeerRoom` takes `simulation:`. This package now depends on
  `flutter3d_plugin_api`, which depends on nothing, and exports
  `SimulationVersion`.
- **Parties of more than two.**
  - `PartyWire` and `LoopbackParty`.
  - `PartyRollback` rolls back for two to thirty-two.
  - `PartyTape` and `PartyTapeWatcher` serve spectators from the settled
    tape.
  - `AuthorityServer` and `PredictingClient` are the authoritative model.

- **The hello names its versions, and a mismatch is refused.** `WireHello`
  is the protocol, major and minor, and the game's simulation version.
  `PeerRoom` takes `simulationVersion` and says both in every hello. Two
  machines on different simulation versions, or protocol majors, do not
  meet: `refusal` says why and names the version to update to, the room
  answers once so the other side hears the same, and nothing on a channel
  passes from the refused machine. Within a major the protocol only grows,
  so a lower minor still plays, on `sharedMinor`. A 0.1.0 machine names
  no protocol, reads as 0.0, and is refused with a reason rather than met.

## 0.1.0

**Two players on two machines, in four ways a game can share itself.**
`PeerRoom` is the room over one wire: slot nought for whoever made it, a
hello repeated until the other machine answers with what it plays, and
channels that do not hear each other. `RollbackPlay` runs one simulation on
both in step over `NetSession`, each machine driving its own player, and
keeps the first settled ending so both go on from the same state.
`BatonStream` is turns: the machine playing tells frames and events, the
other replays them at the pace they were played and catches up when far
behind, and the turn goes across with the state it starts from. `PeerFeed`
is two games side by side, each telling the other where it is.
