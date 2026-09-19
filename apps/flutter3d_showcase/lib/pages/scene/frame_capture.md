# Capturing a frame

A frame that comes back black could have failed in any of its passes. A
capture answers which one, by keeping the pixels every pass wrote rather than
only the finished picture.

## Step 1: Build a small scene to capture

A capture is expensive, so it stays off by default and is asked for one frame
at a time. This page uses a separate, tiny scene as the frame it captures,
away from the scene drawn in the viewport.

{{code probe}}

## Step 2: Ask for the next frame, then render one

`captureNextFrame` returns a future for the frame that follows it. It has to
be called before `render`, not after: there is one next frame, and asking late
misses it. Once the future completes, every pass the frame ran is there by
name, with what it read, what it wrote, and the pixels it produced.
`firstBlack` walks them in order and returns the first pass whose output was
already empty, which is normally the one to look at first.

{{code capture}}

## Step 3: The page you can see

The viewport itself draws an ordinary lit torus, unrelated to the captured
probe. The capture already happened during loading, before this scene existed.

{{code scene}}

## Step 4: Check the capture recorded something

The page looks up the scene pass by name, confirms it was active, and checks
that the colour image it kept is not entirely black.

{{code check}}
