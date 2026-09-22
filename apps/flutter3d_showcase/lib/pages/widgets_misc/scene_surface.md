# The scene surface and its status screens

Every viewport in this application, including the one this page would use if
it did not override its own body, is built from the same two pieces:
`SceneSurface` renders a scene into a widget, and `DidNotStart` is what shows
instead when opening a renderer failed.

## Step 1: A scene to draw

{{code scene}}

## Step 2: Wrap it in a surface

`SceneSurface` calls `onBeforeFrame`, then `settings`, then renders, and
hands the result to `presentFrame` — the one function every backend can
answer, since a backend whose frame is composited elsewhere has no image of
its own to paint.

{{code surface}}

## Step 3: What failure looks like

Five applications each wrote their own screen for "the renderer never
opened"; `DidNotStart` is the one that is left, with room for an
application to add what the bare error does not say.

{{code failure}}

The explanation an application supplies is shown alongside the error,
verbatim.
