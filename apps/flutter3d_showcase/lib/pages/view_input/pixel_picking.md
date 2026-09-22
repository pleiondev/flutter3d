# Picking by pixel

`Raycaster` answers against bounds, and a bounding box is not the thing: a
monster's box is a metre wider than the monster, and a torch's box overlaps
the wall it hangs on. `Renderer.pickPixel` answers exactly instead, by
drawing the scene once more with a stage that writes each draw's number
instead of its colour, and reading the one pixel the question asked about.

## Step 1: Ask a point

`pickPixel` takes fractions of the frame from the top left, the same shape a
widget's local position divides down to. It returns a future: the answer
does not exist yet, because the frame that finds it has not been drawn.

{{code pick}}

> **Note.** The question is only answered on the next frame that runs after
> it is asked. A pick made from inside a frame callback waits for the frame
> after that one.

## Step 2: The answer arrives later

On a hardware backend the future completes a frame or two after this call;
on the software backend used to test every page here it still completes
asynchronously, once the event loop gets back to it. A page that needs the
answer this same frame is asking the wrong tool, and wants `Raycaster`
instead.

{{code pick}}

## Step 3: Only on a frame that asked

The id pass only runs on a frame something asked a question of; otherwise
the node is inactive and the frame graph culls it before it costs a texture.
Asking every frame, as this page does, means the id pass runs every frame,
which is fine for a demo and wasteful for a game that only needs an answer
on a click.

{{code pick}}
