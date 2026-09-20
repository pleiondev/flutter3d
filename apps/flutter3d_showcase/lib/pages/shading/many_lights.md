# Thirty-two lights and the fade band

Eight is the cap on one draw, not on a scene. Past that, the renderer picks
the eight lights that matter most to each object and hands the rest, up to
twenty-four more, through a texture-backed light list. Eight slots plus a
twenty-four light tail is where "thirty-two lights on one draw" in the
CHANGELOG comes from, and only a torch past that thirty-second one is
actually left unlit.

## Step 1: A tiled floor and a ring of torches

Forty point lights arranged in a ring, over a floor built as a grid of
tiles rather than one giant plane. A single draw's bounding sphere wide
enough to reach every torch would score them all alike — a light *inside*
an object's sphere scores that object's ceiling no matter where inside it
sits, so nothing would tell one torch from another. A tile small enough
that a torch's own range can fall outside it makes "which torches reach
this one" a real question with a real answer, tile by tile.

{{code floor}}

{{code torches}}

## Step 2: The fade band

Every tile has more than thirty-two torches within reach, so every one of
them turns some away — the tile at the very centre of the floor turns away
the most, being the single farthest point from every torch on the ring at
once. `lightFadeBand` turns the cliff where a turned-away torch's
contribution ends into a ramp: drag it up and the centre tile — lit by
nothing but the weakest of its list — dims towards black, while the ring
itself, whose nearest torches sit nowhere near that cliff, stays exactly
as bright.

{{code settings}}

## Step 3: What the frame reports

`FrameResult.lightsDropped` is how many lights a scene actually loses: past
the eight direct slots and the twenty-four-light tail, not past the eight
alone. With forty torches and a cap of thirty-two, eight of them are
genuinely unlit, and this page's test reads that number back off the
frame.

{{code check}}
