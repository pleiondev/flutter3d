# Occlusion culling

Frustum culling leaves out what is outside the picture. It does nothing for a crate that
is inside the picture but behind a wall: the crate is drawn, every pixel of it loses the
depth test, and the work is thrown away. Occlusion culling asks, before the draw, whether
anything in front already covers the whole box, and skips the mesh if it does.

With the software test the picture does not change when it works. A frame only
reports how many meshes were left out, in `FrameResult.culled`. So this page puts a lookout in the yard, the small blue
ball, and paints the crates the lookout cannot see dark grey. The orange ones are the ones
it would still draw.

## Step 1: Mark the wall as an occluder

`RenderSettings.occlusion` is `OcclusionMode.none` by default. With
`OcclusionMode.software`, only meshes marked `occluder` hide anything, and nothing is
marked by default, so switching the setting on alone changes nothing. A marked mesh
still never occludes when its material is transparent or cut out, writes no depth, or
compares depth other than by less or less-or-equal, nor when it is an instanced batch.
A skinned or morphed mesh does not occlude with its own triangles, since they move;
give it an `occluderMesh` and it occludes with that.

A wall is a good occluder: a few triangles that cover a lot of the view. The software
test draws at most two thousand occluder triangles a frame, the largest on screen first,
so a detailed mesh can carry a cheaper stand-in in `occluderMesh` instead.

{{code wall}}

## Step 2: Put something behind it

Fifteen crates stand in three rows behind the wall. Two of the front row stick out past
its ends.

{{code crates}}

## Step 3: A camera to ask for

The lookout is a camera of its own, standing in front of the wall at eye height. It is
not in the scene and draws nothing. The blue ball only marks where it stands.

{{code lookout}}

## Step 4: Ask what the lookout can see

This is what the renderer does for every view when the setting is `software`, written
out so the page can colour the answer. `SoftwareOcclusion.prepare` draws the marked
occluders into a 256 by 128 depth buffer on the CPU and returns an `OcclusionTest`.
`mayBeVisible` then takes a crate's world box and answers false only when every pixel
the box covers already holds something nearer. Anything short of that, a box through the
near plane or a pixel nothing was drawn into, answers true.

Drag **Wall position** and watch the grey patch follow the wall. Switch off **Wall is an
occluder** and every crate turns orange: the wall is still drawn, but it no longer hides
anything from the test.

{{code probe}}

## Step 5: Turn it on for the view

The same setting culls the view you are looking through. From above the wall hides
little, so orbit round until the wall stands between you and the yard, and the crates
behind it are left out of the draw. The picture does not change. The frame reports fewer
draw calls and a larger `FrameResult.culled`.

`OcclusionMode.hiZ` needs nothing marked. It reads back last frame's depth and
reprojects it to this frame's camera, and answers "visible" until the first reading has
arrived, after a camera cut and with more than one view. Reading that depth back turns
multisampling off, so on a device that multisamples, `hiZ` does change the picture: its
edges lose their smoothing.

{{code settings}}

## Step 6: Check it

The page's test checks that the wall was the one occluder drawn, and that it hides some
of the crates from the lookout but not all of them.

{{code check}}
