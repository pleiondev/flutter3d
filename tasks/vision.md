# Where flutter3d is going

Set by Dmitrii on 2026-10-08: **to be the first renderer and engine on
Flutter for 3D games, industry and education.** Every release plan is drawn
from this aim. A plan item that serves none of the three has to say why it
is there.

## How "first" is measured

There are four measures, and each release says which of them it moves.

1. **A public benchmark.** An open set of scenes with frame times on the
   Galaxy A55, an iPhone and in a browser, that anyone can run, other
   engines included. `tool/pacing.sh` and `doc/pacing/` are its start.
2. **Shipped games and apps.** The demos in the stores, plus cases from
   industry and teaching.
3. **Adoption.** pub.dev likes, stars, packages that depend on ours, and
   contributors.
4. **Breadth and depth.** Features and platforms covered against the
   alternatives, each claim backed by a test.

## Directions

Ordered by how much is staked on each.

### What we invest in

- **The agent as a first-class user. This is the main difference.** Every
  editor action is an MCP tool. An agent builds a game or a lesson and
  checks itself with replays and reference frames. A benchmark of "an
  agent builds a game" runs in CI. New features arrive with their MCP
  tools.
- **From capture to scene.** Video from a phone becomes Gaussian splats
  that collide, take part in physics and take light. 4D splats are used
  for moving scenes. This serves digital twins, museums, lessons, and
  levels built from real places.
- **Inverse problems.** A differentiable simulation and renderer recover
  parameters from what was observed: friction from video, a material
  from a photo. The same machinery optimises a design or trains a robot.
  The core is designed with gradients in mind.
- **A simulation server.** The deterministic core runs on a Dart server,
  checked by replay, for multiplayer and anti-cheat. Streaming frames to
  thin clients comes later.
- **Validation in CI.** Each law of the core is compared with the
  measurements in `docs/articles`, and its error is written down. The
  report is generated in CI and published on the site.
- **Teaching on the engine.** Work is assessed from the student's
  replay, which is verifiable evidence of what they did in the
  simulation. A tutor reads the scene and the callbacks through MCP. LTI
  and the laboratories exist already.
- **OpenUSD in.** USDA and USDC are read with UsdPhysics, next to URDF,
  and layers and overrides work the way prefabs do. USDZ out exists
  already.
- **Generated content with provenance.** Generators plug into the
  editor: text or a picture becomes a model, a PBR material or an
  animation. Each asset records where it came from and under what
  licence, the way `LICENSES.md` does now. The model readiness checks
  apply to these assets too.

### What we research first

- **Neural rendering on the device.** Upscaling and frame
  reconstruction, neural texture compression and neural materials,
  through the phone's NPU and compute shaders. In 0.10, a network
  upscaler on WebGPU and wgpu is measured on the A55, and the numbers
  decide whether it ships.

### What we watch

- **Hardware ray tracing on phones** (ray queries on Adreno and Mali,
  Metal RT). It comes after the compute path tracer of 0.10, once wgpu has
  ray queries.

### What we stay out of

- **Native XR ports.** WebXR is the path. visionOS and Android XR are not
  planned.

## Release plans drawn from this

- `0.10-plan.md`: streams A to E.
- `0.10-explore-genre.md`: the fifth genre.
