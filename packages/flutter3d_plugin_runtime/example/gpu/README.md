# The sample plugin's render checks on the GPU backends

The plugin example's own suite (`../test/render_conformance_test.dart`)
draws the sample plugin's points in the frame on the software rasteriser
and holds them to their structure on a recording fake. This application
runs the same `checkPluginRender` on the three GPU backends:

- **WebGL2 and WebGPU** in a browser test,
  `test/render_conformance_web_test.dart`;
- **Impeller** in a macOS application, `lib/main.dart`, because Flutter GPU
  needs Impeller and a headless test does not enable it. It prints a line a
  check and exits with 1 when one failed.

The plugin ships its lit model as material source. `tool/build_bundle.dart`
compiles it the way a game's build hook compiles a material: `impellerc`
for Impeller, GLSL ES 3.00 for WebGL2, glslang and naga for WebGPU's WGSL.
The bundle is written for the SDK on this machine and not committed, since
Impeller refuses a bundle from another SDK. The plugin's decal stage has
the engine's decal interface, so each device answers it with its own
`Decal`, as the software rasteriser's suite does.

```bash
tool/render_conformance.sh             # all three
tool/render_conformance.sh --web       # WebGL2 and WebGPU
tool/render_conformance.sh --impeller  # Impeller
```

It needs `glslangValidator` and `naga` on `PATH`, Chrome with WebGPU, and
a Mac for Impeller.
