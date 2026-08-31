#version 460 core

// PROBE, not part of the pipeline: does Impeller honour more than one colour
// attachment?
//
// `RenderTarget.colorAttachments` is a list and `setColorBlendEnable` takes an
// attachment index, so MRT is there structurally — but structure in the Dart
// bindings has already proved to be a poor predictor of runtime behaviour
// twice in this project. Writing two distinct constants and reading both
// targets back settles it.
//
// Enabled with `--dart-define=FLUTTER3D_MRT_PROBE=true`; the entry stays in the
// bundle because the answer is tied to a Flutter version and the next SDK bump
// should re-run the check rather than re-derive it.
precision highp float;

in vec2 v_uv;

layout(location = 0) out vec4 out_first;
layout(location = 1) out vec4 out_second;

void main() {
  // Two values nothing else in the engine produces, so reading them back is
  // unambiguous evidence that each attachment received its own output.
  out_first = vec4(0.25, 0.5, 0.75, 1.0);
  out_second = vec4(0.75, 0.5, 0.25, 1.0);
}
