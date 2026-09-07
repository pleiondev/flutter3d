#version 460 core

// **A probe, not a feature.** It answers one question that decides how morph
// targets are drawn: can a *vertex* stage sample a texture on this backend?
//
// Nothing else in this engine samples anything in a vertex stage. The two
// routes for morphing on the GPU are a second vertex layout — and with it a
// second vertex shader per lighting model, because the layout here is
// structural — or the deltas in a texture read by vertex id, which needs
// exactly this. WebGL2 guarantees it by specification (GLES 3.0 requires at
// least sixteen vertex texture units) and the software rasteriser is our own
// code; flutter_gpu is the unknown, and an unknown that a comment cannot
// settle.
//
// So the answer is measured on every backend rather than assumed on two and
// hoped for on the third. `checkVertexTextureSampling` in
// flutter3d_conformance is what reads it: this stage passes what it sampled
// through to the fragment stage unchanged, so a frame read back holds the
// texture's own colour when the sample worked and the clear colour when the
// draw never landed.

in vec3 position;

/// The texture the vertex stage reads. One texel is enough: what is being
/// asked is whether the read happens at all, not whether it filters.
uniform sampler2D probe_texture;

uniform ProbeInfo {
  /// xy: where to sample. zw unused.
  vec4 at;
}
probe_info;

out vec4 v_sampled;

void main() {
  // `textureLod` and not `texture`: a vertex stage has no derivatives, so the
  // level has to be named. Asking for an implicit one is undefined and is the
  // shape of a probe that reports a driver's opinion rather than a fact.
  v_sampled = textureLod(probe_texture, probe_info.at.xy, 0.0);
  gl_Position = vec4(position, 1.0);
}
