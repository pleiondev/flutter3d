# Thirty-two lights and the fade band

Eight is the cap on one draw, not on a scene. Past that, the renderer picks
the eight lights that matter most to each object and hands the rest, up to
twenty-four more, through a texture-backed light list. Eight slots plus a
twenty-four light tail is where "thirty-two lights on one draw" in the
CHANGELOG comes from, and only a torch past that thirty-second one is
actually left unlit.

## Step 1: A floor and a ring of torches

One plane, one draw, lit by forty point lights arranged in a ring around
it. The floor's bounding sphere reaches every torch, which is exactly the
case a per-object selection has to solve, and forty is eight more than the
thirty-two the draw can carry.

{{code floor}}

{{code torches}}

## Step 2: The fade band

Walking past a corridor of lamps, the eighth slot changes hands every few
metres, and the lamp that just lost its slot goes instantly dark. `lightFadeBand`
turns that hard edge into a ramp: a light near the cutoff fades out instead
of disappearing.

{{code settings}}

## Step 3: What the frame reports

`FrameResult.lightsDropped` is how many lights a scene actually loses: past
the eight direct slots and the twenty-four-light tail, not past the eight
alone. With forty torches and a cap of thirty-two, eight of them are
genuinely unlit, and this page's test reads that number back off the
frame.

{{code check}}
