# The material expression language

A material written in this language reads like the GLSL it compiles down
to: `clamp`, `pow`, the swizzles and the broadcasting rules all mean what
they mean there, because the emitted shader has to read like the source it
came from. What a material may not do is declare a uniform block, sample a
texture the engine does not bind, or loop. Those are refusals with a
sentence attached, not omissions.

## Step 1: A material, as source

Rim lighting: a glow that grows at the edge of a surface as it turns away
from the eye. Two parameters, one input read from the surface, one
returned colour.

{{code source}}

## Step 2: Pick a variant, and emit GLSL

`specialiseMaterial` folds a variant's values into the parsed tree; a
parameter nobody set keeps its default. `emitMaterialFragment` turns the
result into the `.frag` source the shader build already compiles.

{{code specialise}}

## Step 3: Run it without a GPU

The same tree `emitMaterialFragment` reads from is also something
`evaluateMaterial` can run directly, one fragment at a time, in plain Dart.
This is what backends with no shading language read instead of GLSL.

{{code evaluate}}

## Step 4: The report

Which surface inputs the body actually reads, what it evaluates to at one
sample point, and the GLSL that came out of the same source.

{{code report}}

## Step 5: What this page checks

The evaluated colour has to match the rim-lighting formula worked out by
hand, and the emitted GLSL has to actually have an entry point.

{{code check}}
