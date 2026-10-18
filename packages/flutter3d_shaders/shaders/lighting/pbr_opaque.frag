#version 460 core

// Metal-rough with no reachable `discard` — `A1.2`.
//
// **What a tiler loses to a `discard` it can see.** A stage that may throw a
// fragment away cannot have its depth written before it runs, so a GPU that
// hides surfaces before shading them — every phone's, and Apple's — turns
// that off for the whole draw, and early depth with it on the others. It
// does so for what the compiled stage *contains*, not for what a uniform
// lets it reach: the alpha cut in `ReadSurface` is behind a cutoff only a
// masked material sets, and every opaque wall paid for it all the same.
//
// So the lit models come twice. This one is `pbr.frag` with `F3D_OPAQUE`
// defined, which leaves the cut out; the renderer draws an opaque material
// through it, and a masked or a cross-fading one after a depth pre-draw that
// makes the cut instead (`depth_predraw.frag`), tested `equal` against what
// that wrote.
// `A1.1`: a material stage — its colour arithmetic may run at mediump
// where `shaders/PRECISION.md` says it can.
#define F3D_MEDIUMP
#define F3D_OPAQUE
#include <lib/pbr.glsl>
