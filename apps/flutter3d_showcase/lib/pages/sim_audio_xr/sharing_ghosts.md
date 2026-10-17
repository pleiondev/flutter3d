# Sharing runs and racing ghosts

A player finishes a level and wants a friend to try to beat the run. What
has to travel is the level, which version of it this is, and the run
itself as a `.f3drun`, the starting state plus a tape of what the player
did. `ShareBundle` holds those three. `RunService` files a bundle with a
sharing service and gets a short code back, and opens a bundle again from
its code. On the friend's side, the tape is played back through the same
simulation, and where the runner went becomes a pose track to race against
as a ghost.

On this page the translucent ball is the ghost of a shared run, weaving
down the strip. The orange ball is you, running straight and a little
slower. Switch on **Open it in the longer track** and the same run is
opened in an edited version of the level. It is refused there, and no
ghost appears.

## Step 1: A game with a level in it

The game is a runner on a strip, steered by the stick and stopped at the
far end of the track. The finish is read from the level's one brush, so
lengthening the track changes the level's hash and changes what a run
through it means.

{{code game}}

## Step 2: Record the run

A run is recorded the way a game records it. The input goes on the tape
before each step, a digest of the state is taken every ten steps after it,
and the level's hash is stored with them. The page also writes down where
the runner was after every step, to compare the ghost with later.

{{code record}}

## Step 3: A service in memory

`RunService` does no networking of its own. It is handed a function that
carries one request and answers with the response. A game passes the HTTP
client it already has, and a test passes the server's handler. This page
passes a map. Its two routes answer in the shapes the reference server in
`cloud/server` uses, and the POST route reads the bundle back with
`ShareBundle.fromJson` before filing it, as the server does.

{{code service}}

## Step 4: Share it, and open it by its code

The bundle is built from the level document and the run, filed, and opened
again by the code that comes back. Every call answers `ServiceDone` or
`ServiceRefused` with a sentence. None of them throw, so an unreachable
server is handled like any other refusal.

{{code share}}

## Step 5: The ghost is the run played again

The pose track is not sent. A bundle carries a tape and a starting state,
and the simulation is deterministic, so the friend's machine plays the tape
into a fresh run of the level and writes down where the runner was, thirty
times a second. A `Playback` of that track gives the ghost's place at any
moment, interpolated between samples.

{{code ghost}}

## Step 6: Another version of the level is refused

If the run was recorded in another version of the level, the ghost would
run through walls that are not there. `ShareBundle` refuses that run
before it leaves the machine and names both hashes, because the person
sharing it can record it again and the person opening it cannot. The ghost
maker refuses it a second time on the other side.

{{code refuse}}

## Step 7: What has to hold

The run has to come back from its code as a ghost. The edited level has to
be refused both ways. At every sample, the ghost has to be exactly where
the original runner was at that moment, compared bit for bit, and its last
sample has to be at the finish line.

{{code check}}

> **Note.** The real service files a bundle under the SHA-256 of its bytes
> and gives it a short Crockford code. The map here uses the engine's
> 32-bit content digest, which is enough to tell two documents apart on one
> machine and too short to name one among everybody's uploads. Moderation
> is left out: on a real server a share can wait in review before anyone
> can open it. Our own instance is not deployed yet, and there is no web
> viewer for a code. A run recorded on the other physics backend is refused
> as well. This toy has no physics, so the page does not show that case.
