# Variants and animation pointers

A shop that sells one chair in three colours does not want three chairs in its
files. glTF's `KHR_materials_variants` lets one model carry every look it comes in,
each under a name, and says which material each part wears in each of them.

`KHR_animation_pointer` is the other half of this page. An ordinary glTF clip can
only move nodes: translate, rotate, scale, and morph weights. A pointer channel names
a property of a material or a light instead, so a clip can warm a colour or dim a
lamp.

This page builds a small model with both, writes it into a GLB, reads the file back
and draws what came out of it.

## Step 1: Five materials

The body wears red paint and the ball wears cream. The other three are there only for
the variants to use. On a `SurfaceMaterial` the base colour is the tint as authored,
not linear.

{{code materials}}

## Step 2: Which part wears what, by name

A document's `variants` is the list of names. Each surface's `variantMaterials` maps a
variant, by its index in that list, to the material the surface wears in it. The body
turns teal in "teal" and graphite in "graphite". The ball's map names only
"graphite", where it turns to chalk.

A part a variant does not mention keeps its default material. That is what the
extension says, so the ball stays cream in "teal".

{{code variants}}

## Step 3: A clip with no node in it

A pointer track has `path: AnimationPath.pointer` and a node index of -1, because it
moves no node. What it moves is its `AnimationPointer`: which kind of object, which one
by its index in the file, and which property. In a file the target is a JSON pointer
string such as `/materials/1/pbrMetallicRoughness/baseColorFactor`. The loader parses it
once, so the player never reads the string. `AnimationPointer.of` builds the pointer
the writer should use for a track made by hand, as this one is.

The list of properties is closed: a material's base colour, emissive strength,
roughness, metallic and texture offset, and a light's colour and intensity. A file that
points at anything else loads with a warning, and that channel is left out rather than
kept as a track that changes nothing.

This clip has two tracks over three seconds. One takes the ball's material from cream
to amber and back. The other takes the file's light from 110 lux down to 45 and back up.
The colour keys are linear, which is how glTF stores its colour factors.

{{code clip}}

## Step 4: Write it, read it back, upload it

The document gets the materials, the surfaces, the variant names, one directional light
and the clip. `GltfWriter` writes both extensions into the GLB. It lists them as used but
not as required, so a reader that knows neither still draws the default look.

Everything below this point uses what `GltfLoader` read back, never the document this
page wrote. `ModelAsset.fromDocument` binds every material a variant can use at upload,
so switching later is an assignment and never an upload.

{{code roundtrip}}

## Step 5: A light for the track to land on

A pointer names a light by its index in the file, but instantiating a model creates no
lights at all. The page makes its own sun, starting from the colour and intensity the
file gave its light, and `bindLight(0, ...)` tells the instance that this node is light
0.

Each instance has `pointerTargets`, where its player sends every pointer track. The
materials are in there by their index in the file, filled in by `instantiate`. The
lights are whatever the application has bound. The intensity arrives in lux, as glTF
writes it, and `PointerTargets` converts it to the engine's own unit on the way in. The
colour arrives linear and is converted to the tint `Material.baseColor` holds.

{{code bind}}

## Step 6: Pick a variant

`selectVariant` takes a name, or null for the default look. It points every mesh node
at the material its part wears in that variant, and `variant` says which one is worn
now. A name the file does not have returns false and changes nothing.

It never changes a material, only which material each node draws with. Two instances of
one asset can therefore wear two different variants even though they share materials.

{{code select}}

The page opens in "teal". Switch **Variant** to "graphite" and the ball stops changing
colour. The clip still writes material 1, but the ball is wearing chalk, material 4, and
the clip has no track for that one. The sun keeps dimming whatever the variant.

## Step 7: Play it, or scrub it

The page opens halfway through the clip, where both tracks are furthest from the file's
own values. From there the player advances by the frame's time and applies the clip's
values at the new time, pointer tracks included. The clip loops, which is the player's
default.

{{code play}}

{{code tick}}

Turn **Play clip** off to hold the moment. Dragging **Time** pauses the clip and seeks
to that time, and the colour and the light follow straight away.

> **Note.** With shared materials, which is what `instantiate` does unless told
> otherwise, a material track moves the asset's material, so every instance that wears
> it changes together. Pass `shareMaterials: false` for instances that animate on their
> own.

## Step 8: Check both halves

The page's claim is checked after one frame. For each surface it works out the material
the file gives it in the variant being worn, and checks that the mesh node is drawing
with exactly that material from the asset. Then it checks that the ball's material and
the sun have both moved away from what the file says, which only the clip could have
done.

{{code check}}
