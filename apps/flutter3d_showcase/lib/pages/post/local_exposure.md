# Local exposure

Stand in a dark room and look at a bright window, and a camera has to choose.
Expose for the room and the window turns white. Expose for the window and the
room turns black. Auto exposure only moves that one choice around. Local
exposure gives each part of the frame its own exposure before the tone curve,
so the room and the window can both be seen at once.

## Step 1: A dark room

A room six metres square with a window in the back wall, and a crate in the
dark half of the room. The walls are thick slabs that overlap where they meet.

{{code room}}

## Step 2: A bright outside

Through the window you see a large emissive panel, many times brighter than
anything in the room. There is no lamp and no sun, only a weak ambient light,
so the room stays dark. `defaultLightWhenUnlit` is switched off, or the
engine would add a light of its own to a scene that has none.

{{code outside}}

## Step 3: Turn on local exposure

`RenderSettings.localExposure` takes a `LocalExposureSettings`, off by
default. With `enabled` on, the renderer looks at the frame three times over:
`shadowStops` brighter, as it is, and `highlightStops` darker, 2 stops each by
default. At each place it weighs how close each version comes to mid grey,
blurs those weights wide, and gives each place the exposure its weights
choose. The blur ignores edges, so the exposure changes gradually across the
frame instead of cutting a seam at every edge. The price is a soft glow
around the bright window, whose edge is pulled down less than its middle.
`strength` is how much of that shift applies. Nought is the one global
exposure and one is the full local answer. The default is 0.7. This page
uses 1.

{{code settings}}

Switch **Local exposure** off and you get one exposure for the whole frame:
the crate is lost in the dark. Switch it on and the dark half of the room
lifts while the window comes down. Raise **Shadow stops** to lift the dark
parts further, and **Highlight stops** to bring more back from the window.

## Step 4: Check that it ran

The weights are measured at an eighth of the frame's size, in three small
passes, and the composite applies them. The frame lists them as one pass
called `local exposure`.

{{code ran}}
