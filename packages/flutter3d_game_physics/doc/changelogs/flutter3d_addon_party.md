## 1.0.0-rc.1

- **Breaking: a boolean reads as a question, and no `bool` is positional.**
  `PartySession.full` is `isFull`. `dart fix` carries the renames.
- **Breaking: `RoomSession.create` is `host`**, beside `join`: `create` is
  the synchronous verb, and this one opens a session on the relay.
- **The relay is asked with the whole `SimulationVersion`**, and
  `SideRecording` takes the `physics` its side plays on.
- **Party sessions for any game.** `PartySession<G>` makes, joins or finds
  a party on the relay and hands the seat to the game's own `stage`; the
  relay settles the size and the slot. `seats` refuses a party bigger than
  the game can stage, before anything is staged.

- **The simulation's version always goes with the ask.** `PartySession`
  and `RoomSession` require a `SimulationVersion` and send it as
  `relayVersionOf` reads it, `engine × 1000 + game`. A party used to ask
  with none, which met only builds that named none; now a build on other
  rules is turned away with the relay's reason.

- **A room for two, and one side's run.** `RoomSession` seats the maker at
  0 and the one who joins at 1, and keeps why the relay closed it.
  `SideRecording` keeps a side's start, input tape and settled digests as a
  `Demo`, so the two sides' files can be compared.

- **No `dart:io`.** Writing the run to a file is left to the application,
  so the package runs on the web.
