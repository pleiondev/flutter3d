# Frame pacing: macos

Written by `tool/pacing.sh` on 2026-09-25 at `9c3a1ab3`. `shooter.f3drun` played through the renderer a step a frame, 3 times, each frame timed from the step to the GPU finishing its draw (see `replayPacing` in `flutter3d_testing`). A frame over 50.00 ms is a spike, and any spike fails the run.

| frames | p50 | p99 | worst | over 50 ms |
| ---: | ---: | ---: | ---: | ---: |
| 660 | 8.26 ms | 12.25 ms | 12.49 ms (pass 1, step 48) | 0 |

- device: GpuRenderBackend, macos Version 27.2 (Build 26B5091g)
- build: profile
- host load average when the run began: 5.86, 8.98, 9.41
- frame: 1280 x 720
- `RenderSettings.frameWorkBudget`: none
