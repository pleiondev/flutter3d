# Cutscenes

A cutscene is a few seconds where the game takes the camera, says something,
and changes the world: a door opens, a monster wakes. If any of that is done by
timers in the frame, a replay or a skipped cutscene ends somewhere else.
`Sequence.read` takes the cutscene as a document, and `SequencePlayer` plays it
in the fixed step, so skipping it, saving in the middle of it and replaying it
all end in the same place.

This page plays an eight-second scene in a dark hall. The camera comes in from
the door and round to the altar. Three seconds in, a lamp is lit on the altar,
and at five and a half the gate behind it rises. Then it starts over.

## Step 1: The document

Times are in seconds. `camera` is a list of keys, each with where the eye is,
what it looks at and, if it says, its vertical field of view in degrees,
forty-five otherwise. With `ease` the camera slows into and out of each key.
`subtitles` are lines with a start and an end, `fade` is how dark the picture
is at a few moments, and `signals` are names, with data, that the game is
told about on their step. A sequence can also have `actors` cues that walk an
actor to a mark over the navigation mesh, turn it, stand it, play a clip once
or hand it back to its brain. This page has none.

{{code document}}

## Step 2: Read it at the game's rate

Every moment is turned into the step it falls on, once, when the document is
read. A document with problems gives no sequence, and every problem comes back
with where it is.

{{code read}}

## Step 3: Step it, and answer the signals

`SequencePlayer` keeps a single integer, the step it is on. `advance` moves it
one step, and every signal that step reaches is published onto the player's
`events` bus as a `SequenceSignal`, once each and in order. The game answers
them the way it answers any other event, with a subscriber on that bus. Here
it lights the lamp and raises the gate by the height the signal carries.

In a game the bus is the engine's: a genre's simulation hands its cutscenes
its own, so a signal lands on the step channel among the step's other events.
This page steps the cutscene by hand, with no `EngineLoop`, so it hands a
`DirectBus`, which delivers each signal as it is published.

{{code bus}}

{{code step}}

{{code answer}}

## Step 4: The camera between steps

The picture is drawn between two steps, so the camera is asked for `alpha` of
the way from the last step to the next. The eye and the point it looks at each
run along a curve through their keys, and pass through each key on its step
exactly. The fade and the subtitles are read the same way.

{{code camera}}

## Step 5: The fade

`fade()` is nought for a clear picture and one for black. This page applies it
as exposure, so the whole picture darkens.

{{code fade}}

## Step 6: Skip

A skip is the remaining steps of the cutscene run straight away without being
drawn. Every signal on the way still fires, in order, so the lamp is lit and
the gate is up whether the scene was watched or skipped. In a game this goes
through `EngineLoop.runSteps`, which also records the skipped steps on the tape,
so a replay steps through them too.

{{code skip}}

## Step 7: What has to hold

A player stepped to the end and a player skipped after a second and a half
have to agree: the same step, the lamp lit, the gate at 2.5 m, and the signals
heard as `lamp` then `gate`, once each. A player restored at four seconds,
after the lamp, has to fire only the gate. The camera has to end on its last
key, at 38 degrees, and the fade has to end clear.

{{code check}}

> **Note.** This page has no text layer over its picture, so its subtitles are
> read but not shown. The dungeon draws them, with the fade, over the
> cutscene's camera. The fade here starts at 0.8 rather than black, because a
> page is also checked on its first frame and a black frame would look like
> one that drew nothing. A skip runs all the remaining steps in one frame,
> which costs whatever those steps cost. Actor cues need an `ActorSystem` and
> a navigation mesh, and are shown in the dungeon's sanctum rather than here.
