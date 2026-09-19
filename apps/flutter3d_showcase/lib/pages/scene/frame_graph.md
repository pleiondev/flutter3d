# Plan a frame before drawing

The renderer decides which passes a frame needs by compiling a dependency
graph. `planFrame` runs that decision without encoding draws or touching the
renderer state used by the next real frame.

## Step 1: Build a scene with visible bloom

The emissive torus gives bloom something to spread beyond its edge. The scene
itself stays small so changes in the pass list are easy to attribute to the two
controls.

{{code scene}}

## Step 2: Describe the requested passes

Bloom and antialiasing are independent settings. Disabling either one removes
its node and any graph resources used only by that node.

{{code settings}}

## Step 3: Compile without drawing

`planFrame` receives the same scene, views, and settings as `render`. Its
`order` lists the passes that would run. `skipped` lists rejected passes and the
reason for each rejection.

{{code plan}}

## Step 4: Change the graph live

The controls let you remove bloom and antialiasing separately. Each change is
visible in the next plan before the frame is submitted.

{{code controls}}

## Step 5: Compare plan and frame

The page compares the ordered planned names with `FrameResult.passes`. It also
checks that no skipped pass appears among the drawn ones. This proves the dry
run and real frame used the same graph rules.

{{code check}}
