# What a frame reports

Rendering returns more than a texture. `FrameResult` records how much work was
submitted, which passes ran, and whether requested features were skipped. These
numbers are useful in diagnostics, tests, and an in-game performance display.

## Step 1: Give the counters varied work

The scene mixes a floor, cube, and torus across two materials. Different mesh
sizes and material pipelines make draw, triangle, and pipeline counts distinct
enough to catch a broken counter.

{{code geometry}}

## Step 2: Add an optional shadow pass

The control changes `castsShadow` on the directional light. Switching it off
removes shadow work from later frame results while the colour scene remains.

{{code light}}

## Step 3: Find work by pass name

Each `FramePass` carries its graph-node name, CPU time, draws, triangles, and
pipeline switches. Looking up `scene` and `composite` separates geometry work
from the final full-screen draw. Summing pass draws reconstructs the frame
total.

{{code totals}}

## Step 4: Check the report

The page verifies scene and composite draws, the frame total, triangle and
pipeline counts, and the relationship between total CPU time and submission
time. A picture can look correct while one of these diagnostic numbers is
wrong, so they are checked directly.

{{code check}}
