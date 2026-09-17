---
title: Every mode, once
summary: A photograph of each of the editor's ten modes and the three screens it sends you to, with what each one is for and what it refuses.
---

# Every mode, once

The six cases after this one each walk one job end to end. This page is the
other thing: one picture of every mode the editor has, so that when a case
says "switch to Sculpt" you already know what you are switching into.

Every picture here is a photograph of the real editor, taken headlessly by
`tutorial_screenshots_test.dart` and held to a reference like any other
golden — if a panel moves, the test fails and the picture is retaken. None of
them is a mock-up.

**The switcher offers ten modes in the Full workspace and three in
Essential.** Essential is Object, Material and Scene: "open a model, paint
it, export it" is what most people who open a modeller are doing, and a
switcher with ten icons asks them to decide what Retopo mode is before they
have done anything. Settings turns the rest on.

## Object

![The editor as a launch opens it: the outliner, the transform grid, the tool rail and one object in the viewport.](/assets/learn/modeler/modes/object-mode.png)

Where a launch opens. Objects are moved, turned, scaled, parented and
duplicated here, and this is the only mode that adds a new one. The
properties panel is the document: the outliner above, the selected object's
transform, modifiers and material below.

## Mesh

![Mesh mode, with the element rail and the vertex/edge/face switch.](/assets/learn/modeler/modes/mesh-mode.png)

The topology itself — extrude, loop cut, bevel, inset, bridge, slide, and
the cleanup beside them. It has three sub-modes, and they are one workflow at
three grains rather than three workflows, which is why the rail does not
change between them.

![Vertex level.](/assets/learn/modeler/modes/mesh-vertex.png)

![Edge level.](/assets/learn/modeler/modes/mesh-edge.png)

![Face level.](/assets/learn/modeler/modes/mesh-face.png)

## Material

![Material mode: the slot list, the surface's own numbers and its texture slots.](/assets/learn/modeler/modes/material-mode.png)

What a surface looks like — base colour, metallic, roughness, the five
texture slots, and the node compositor that bakes into them.

## Sculpt

![Sculpt mode: no rail, no properties panel, a 48-wide brush palette on the left and a 250-wide card on the right.](/assets/learn/modeler/modes/sculpt-mode.png)

The one layout in the application with nothing docked beside the picture.
Every other mode is about a document — a list of objects, a stack of
modifiers, a table of bones — and a panel down the side is where those live;
sculpting is one surface and one brush.

Eight brushes, a stroke is one ⌘Z however many pointer samples it was made
of, and **a finger orbits the camera rather than sculpting** — you cannot aim
a brush while the thing it is aimed at slides under it. A stylus and a mouse
reach the surface; a stylus's pressure scales the stroke and flipping it over
cuts in where the pen would build up.

Subdivide adds a real subdivision level to the mesh. It refuses on an object
with shape keys or a bound skeleton: a subdivision carries neither with it.

## Retopo

![Retopo mode: the bake panel's two blocks — the retopology above, the maps below.](/assets/learn/modeler/modes/retopo-mode.png)

Making the low mesh, and baking the high one's detail onto it. Two blocks
because they are two decisions: how many quads the retopology comes out at,
done once, and which maps are baked onto it, done many times.

Draw a quad by clicking four points; each corner snaps to a vertex the new
mesh already has or is pulled onto the high surface. **The snap is the whole
reason the tool is a tool** — four fresh vertices per quad is a mesh that
looks right in the viewport and exports as a shell full of holes.

While a bake runs, the progress takes the button's own place. The button that
starts it is exactly the wrong thing to leave pressable.

## Paint

![Paint mode: the flattened canvas, the layers, the palette and the mask.](/assets/learn/modeler/modes/paint-mode.png)

Painting onto the object's own texture through its UVs. The brush is a ball
in space rather than a circle in the layout, so **a stroke across a seam
paints both islands** — which is the defect every texture painter is judged
by.

The canvas is on the panel because a stroke lands on the surface and on the
texture at once, and only one of those shows whether it went where the UVs
put it. A mask — an occlusion or curvature map baked in Retopo mode — gates
the stroke, which is how paint settles into crevices instead of being painted
into them by hand.

## Simulate

![Simulate mode: the kind chips, the parameters, what it collides with, and the transport strip under the viewport.](/assets/learn/modeler/modes/simulation-mode.png)

Cloth, rigid bodies and particles. A chip per kind rather than a dropdown,
because the parameters change wholesale with the choice.

**Pinning is a selection, not a list of numbers**: pick the vertices that
hold the cloth up in the viewport and press Pin. Nobody knows a vertex by its
number.

The strip under the picture scrubs the baked cache and draws how much of it
exists — a simulation half baked is a scrub bar that runs out halfway, and
saying so first is cheaper than explaining it after.

## Animation

![Animation mode, in the pose sub-mode: the skeleton tree, the timeline and the transport.](/assets/learn/modeler/modes/animation-mode.png)

Four workflows that share a mode button, and unlike the mesh sub-modes these
really are four different things — posing a joint and mapping a bone name are
not one operation at two grains — so the rail and the panel change wholesale
between them.

![Pose: the skeleton, the timeline, and keys on it.](/assets/learn/modeler/modes/animation-pose.png)

![Weights: the brush, the bone list, and the bend slider under the picture.](/assets/learn/modeler/modes/animation-weights.png)

![Retarget: the clip library, the bone map, and the source and target side by side.](/assets/learn/modeler/modes/animation-retarget.png)

![Morphs: the shape list and the sliders that drive them.](/assets/learn/modeler/modes/animation-morphs.png)

## Render

![Render mode: the pass list, and the result in the viewport's place.](/assets/learn/modeler/modes/render-mode.png)

The composite chain is fixed — scene, ambient occlusion, reflections, bloom,
tonemap, look, output — so what there is to decide is which of the middle
ones run. A node editor for a chain that cannot be rewired would be a lie
about what the renderer does, so it is a list with switches, in the order it
runs, and the two ends are drawn without a switch rather than with one that
is always on.

The result takes the viewport's own place, and the tiles fill in as they
land. A render is the one operation here long enough for "is it working" to
be a real question, and a bar somewhere else on the screen answers it worse
than the picture filling in does.

## Scene

![Scene mode: the lights on the rail, the environment, the shadows and the post.](/assets/learn/modeler/modes/scene-mode.png)

The lights, the environment, the shadows and the post — everything about how
the document is lit rather than what is in it. The lights are on the rail as
well as in the panel: a mode whose rail is empty reads as a mode with nothing
in it.

## The three screens

These are not modes — they are places the editor sends you, from any mode.

![The start screen: open a file, start a project, the four Start-from cards, the recents.](/assets/learn/modeler/modes/start-screen.png)

![Settings: the camera scheme, the keymap, the workspace and the language.](/assets/learn/modeler/modes/settings-screen.png)

![Every keyboard shortcut, by the mode it belongs to.](/assets/learn/modeler/modes/shortcuts-screen.png)
