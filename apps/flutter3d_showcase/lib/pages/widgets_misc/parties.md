# Parties of more than two

Rollback works the same way with four players as with two. Every machine
runs every step at once on every player's input. Its own input is known.
The others are guessed from the last input that came from each of them.
When a real input arrives and the guess was wrong, the machine goes back to
the step the guess was made on and runs forward again. With more than two
machines, a correction about one player has to leave the guesses about the
others as they were. `RollbackSession` in `flutter3d_net` does this for
two to thirty-two players. `PeerWire.party` carries each message to every
other machine with the sender's slot. `PartyTape` and `PartyTapeWatcher` let
someone watch without playing.

On this page five lanes stand side by side. The first four are four
machines, each drawing the game as it currently believes it is, and the
fifth is a spectator. Messages arrive four steps late and a tenth are lost.
When a ball jumps, that machine has just corrected a wrong guess. **Steps
late** changes how late the messages are, and its label counts the steps
rerun so far.

## Step 1: A game worth guessing wrong about

The state is how far round the track each player is, in whole centimetres.
Each step moves every player by its own input. The first player is also
dragged by the last player's position, so a wrong guess about the last
player moves the first one as well. The inputs change nearly every step,
which means the guesses are often wrong.

{{code game}}

## Step 2: Four machines and a spectator on one wire

`LoopbackParty` is the wire a test uses for a party: one process, messages
delivered a set number of ticks late, unreliable ones dropped at a set rate,
and the same messages lost for the same seed. Over a network the same
objects sit on `PartyWire.over` a relay's party room. Each machine gets a
`PartyRollback` with its slot, two steps of input delay, and a window of
twelve steps it can roll back through. The host, slot 0, hands each step
that leaves the window to a `PartyTape`. The fifth slot takes no part in
the rollback. It is a `PartyTapeWatcher` that only plays what the host
sends.

{{code machines}}

## Step 3: One tick

A tick advances every machine one step: it captures this machine's input,
sends it with the last few inputs again in case some were lost, and runs
the step. After a while the spectator arrives and asks to watch. The host
sends it the last settled state, then every settled step after that. Then
the wire delivers whatever is due.

{{code tick}}

## Step 4: What has to hold

The test plays the same party for four seconds, then everybody lets go of
the controls and the wire gets forty more steps to catch up. Guesses have
to have been wrong at least once, or the test would prove nothing. The four
machines have to end on one state digest, and it has to be the digest of
the same game played on a wire that is never late and never loses
anything. Any step two machines both settled has to have been settled the
same. The spectator, who came in late, has to be exactly where the players
settled at the step it has reached.

{{code check}}

> **Note.** Rollback costs a full re-run of every step since the wrong
> guess, on every machine, and the cost grows with the number of players
> and how late their inputs are. At ten steps late this page reruns about
> twenty-four thousand steps in its first four seconds. Past what the window
> holds, a late input can no longer correct anything. For a party too large
> to roll back, `AuthorityServer` and `PredictingClient` use the other
> model, with one machine running the game for everybody. The relay hands
> out slots and matches strangers first come, first seated, with no skill
> rating and no region.
