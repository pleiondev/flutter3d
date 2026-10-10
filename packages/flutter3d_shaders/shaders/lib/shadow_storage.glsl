// How the sun's shadow map keeps its depth — `A2.8`.
//
// One header for every stage that reads the map, because the reading is one
// decision and four stages make it: the lit models (`lib/shadow.glsl`), the
// light shafts, the volumetric fog and the moments filter. Each is handed the
// storage mode in a lane of its own block and turns what it reads into the
// depth along the light it has always compared with — nought at the light,
// one at the far end of the cascade.
//
// **Why the map would keep it any other way.** It is a colour target, since
// flutter_gpu cannot sample a depth one, and on most devices a half-float one.
// A half float keeps eleven significant bits, so its steps are finest near
// nought and 1/2048 apart between a half and one — and the far half of a
// cascade, where the ground the shadows fall on usually lies, is exactly
// where they were coarsest. Every surface comparing against its own stored
// depth needed a bias of that step, which in a near cascade a few hundred
// metres deep along the light is 0.18 m: a box a hand tall cast nothing.
// Stored the other way round — one at the light, nought at the far end — the
// ground sits where the steps are finest, and the bias a fragment needs is
// the step at its own depth rather than the coarsest one the map has.
//
// The modes, in the lane each block names:
//
//   0  as drawn: nought at the light. Every release before 1.0, and
//      `RenderSettings.reversedDepth` false.
//   1  turned round, in half floats: the bias's floor is [ShadowStoredStep]
//      at the fragment's own depth.
//   2  turned round, in 32-bit floats: finer than any bias, so no floor.
//
// The pass draws the map through a reversed matrix into a depth buffer
// cleared to nought, so `gl_FragCoord.z` is already what is stored and the
// stages that write it — `shadow_depth.frag` and its masked twin — need not
// know. "Nothing drawn here" is then nought, which [ShadowStored] turns back
// into the one every reader already treats as "nothing between here and the
// light".

#ifndef SHADOW_STORAGE_GLSL_
#define SHADOW_STORAGE_GLSL_

/// The depth along the light [stored] stands for, in the map's [mode].
float ShadowStored(float stored, float mode) {
  return mode > 0.5 ? 1.0 - stored : stored;
}

/// The step between two neighbouring half floats near what a depth of
/// [depth] is stored as in mode 1: the least a bias can be for a surface to
/// clear its own stored depth there.
///
/// The full step rather than half of it, as the renderer's floor for mode 0
/// always was. Below a half float's smallest normal the steps stop shrinking,
/// which is where the clamp holds the exponent.
float ShadowStoredStep(float depth) {
  float stored = max(1.0 - depth, 6.103515625e-05);
  return exp2(floor(log2(stored)) - 10.0);
}

#endif  // SHADOW_STORAGE_GLSL_
