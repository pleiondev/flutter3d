# Playtest heatmaps

Where do players go in a level, and where do they lose? A game could report
that itself, but a game can report anything. A tape can only say what was
pressed. Played back through the same simulation it shows where the player
went, and if the replay does not match the run that was recorded, it shows
nothing. `resimulate` replays a run against its level hash, its starting
state and its checkpoints. `Heatmap` bins the trails of many such runs into
cells and marks where runs were lost.

On this page sixteen recorded runs walk across a yard with a one-metre pit
in it. Each cell is coloured from blue to red by how often a run was
sampled there. The red balls are where runs were lost. **Tapes** sets how
many runs go in.

## Step 1: A game that can be played blind

`resimulate` starts a game through `HeadlessGame` and steps it through
`HeadlessRun`, the same interface a test or a server uses to play without a
window. The pit is a brush in the level. Moving it makes a different level
with a different hash. A walker that falls in stays where it fell until its
tape ends, as a player does on the "you died" screen.

{{code game}}

## Step 2: The tapes

Each run walks across the yard for six seconds and drifts to one side by an
amount its number gives, so that between them the runs cover the yard's
width. They are recorded the way a game records them: the tape before each
step, a checkpoint every thirty steps after it.

{{code record}}

## Step 3: Play every tape again, and bin what retraced

Each tape is played into a fresh run of the level. `resimulate` answers
with a sealed `Resimulation`. A run that retraced its checkpoints comes
back with its outcome and a trail of positions, one every ten steps. A run
that diverged, started somewhere else, or was recorded in another level
comes back with no trail, and is only counted. `Heatmap.bin` counts the
samples and the distinct runs in each cell. It keeps the place where each
lost run ended, and counts each outcome even when nobody had it.

{{code heatmap}}

## Step 4: Draw it over the level

One flat tile per cell, coloured against the hottest cell, and a ball at
each place a run was lost. The heatmap's JSON is the format the editor's
report screen and `Playtest.heatmap` already read, so the same map can be
written out and opened there.

{{code draw}}

## Step 5: What has to hold

Every tape has to retrace its checkpoints, and at least three runs have to
be lost. The hottest cell has to be the cell every lost run ended in: a
player who fell stays there, sample after sample, so that cell ends up with
more samples than any cell the runs only passed through. The same tape
replayed into the yard with the pit moved one metre has to be refused as a
run from another level.

{{code check}}

> **Note.** On a real server this is the end of a longer path. A run is sent
> only with the player's consent, which `TelemetryUploader` checks on every
> send. The server replays it in an isolate and keeps the trail and outcome,
> not the input. That server can only step a game with no Flutter in it,
> and none of the three demo games is split out that way yet, so it answers
> 503. Our instance is not deployed, uploads have no rate limit or retention
> period, and the editor draws the heatmap on its own screen rather than
> over the level in the viewport, as this page does.
