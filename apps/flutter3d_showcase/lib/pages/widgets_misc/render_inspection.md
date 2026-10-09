# Inspecting a running frame

When a picture is wrong, the question is usually which pass drew it, which
draw put that pixel there, and with what. A game built on `flutter3d_app`
answers those questions about its own frame over the VM service, so a tool
attached to it, a person's or an agent's, reads the frame the game really
drew on its own GPU rather than a second picture drawn somewhere else.

The extensions are `ext.flutter3d.render.passes`, `draws`, `draw`,
`passOutput`, `readPixel`, `scanNan`, `stats` and `pick`. Each one is a thin
wrapper over a plain function of one captured frame: `renderPasses`,
`renderDraws`, `renderDraw`, `renderReadPixel`, `renderStats`,
`renderPicked`. This page calls the functions directly, which is also how
their tests call them.

## Step 1: Ask for the next frame, with its draws and a pick

`captureNextFrame(draws: true)` records the next frame pass by pass, with
the pixels each pass wrote and a journal of every draw: which node, which
material, how many triangles, the state and the uniforms bound for it.
Without `draws: true` the draws are counted but not described.
`pickPixel` asks which mesh the same frame draws at a point. Both are
asked before the frame and answered by it, so a draw index and a picked
node belong to one frame.

{{code look}}

## Step 2: Draw a frame to be asked about

The page draws its scene once through a small camera of its own before it
is shown, and keeps what came back. The viewport then asks again about its
own frame once a second; the line beside the viewport is that answer.
Click it to ask now.

{{code probe}}

## Step 3: Read it the way a tool does

Each function answers a JSON map, the same one the extension sends. The
passes come in the order they ran, with their inputs, outputs, time and
draw count. `renderPicked` names the node under the point and the indices of
the draws it made, and `renderStats` adds the frame up.

{{code report}}

## Step 4: What the page checks

The middle of the probe frame has to be the crate. Its draw, opened by
index as a tool opens one, has to name the crate, and the output of the
pass that draw ran in, read at the same pixel, has to be orange rather than
the barrel's blue. The journal has to describe all three meshes.

{{code check}}

A question these functions cannot answer comes back as
`{"refused": "..."}` with the reason and what would work, rather than as an
exception: a draw index past the end, a pixel outside the target, a capture
taken without the journal.

> **Note.** `scanNan` reads a float target's values only on the software
> backend. On the GPU backends a float target is read back as eight bits,
> where a NaN has already become an ordinary byte, so it is reported as
> unread rather than as clean. A full-screen pass's draws are counted per
> pass as `undetailed` and are not described one by one.
