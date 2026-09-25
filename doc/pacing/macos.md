# Frame pacing: macos

Written by `tool/pacing.sh` on 2026-09-24 at `34ee1f9c`. `shooter.f3drun` played through the renderer a step a frame, 3 times, each frame timed from the step to the GPU finishing its draw (see `replayPacing` in `flutter3d_testing`). A frame over 50.00 ms is a spike, and any spike fails the run.

| frames | p50 | p99 | worst | over 50 ms |
| ---: | ---: | ---: | ---: | ---: |
| 660 | 25.83 ms | 41.97 ms | 126.71 ms (pass 1, step 1) | 3 |

- device: GpuRenderBackend, macos Version 27.2 (Build 26B5091g)
- build: profile
- host load average when the run began: 19.74, 49.30, 96.24
- frame: 1280 x 720
- `RenderSettings.frameWorkBudget`: none

Spikes:

- pass 1, step 1: 126.71 ms
- pass 1, step 2: 114.50 ms
- pass 1, step 3: 104.07 ms
