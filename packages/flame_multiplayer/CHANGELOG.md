## 0.2.0

- **Parties of more than two.**
  - `PartyWire` and `LoopbackParty`.
  - `PartyRollback` rolls back for two to thirty-two.
  - `PartyTape` and `PartyTapeWatcher` serve spectators from the settled
    tape.
  - `AuthorityServer` and `PredictingClient` are the authoritative model.

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
