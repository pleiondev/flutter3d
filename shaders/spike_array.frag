#version 460 core

// SPIKE, not part of the engine: does Impeller keep an array member of a uniform
// block, and does reflection report its offset?
//
// The whole multi-light design turns on the answer. If arrays survive, lights go
// into a uniform block with a count. If they do not, they go into a
// r32g32b32a32Float texture and get sampled — a longer path, but one with no
// unknowns left in it.
//
// Answer on Flutter 3.44.6: arrays work. The compiled Metal struct keeps
// `float4 lights[8]`, and reflection reports the block at 160 bytes with
// counts=0, lights=16, tail=144 — exactly the std140 layout, nothing repacked.
// Individual elements are not reflected (`lights[0]` returns null), so the Dart
// side writes the whole array from the base offset and relies on the vec4
// stride being a flat 16 bytes.
//
// Kept in the tree but NOT in the bundle manifest: the answer is tied to a
// Flutter version, and the next SDK bump should re-run the check rather than
// re-derive it. To re-run, add
//
//     "SpikeArray": {"type": "fragment", "file": "shaders/spike_array.frag"}
//
// to shaders/flutter3d.shaderbundle.json, rebuild, and print
// `library['SpikeArray'].getUniformSlot('SpikeInfo')` offsets at startup.
precision highp float;

in vec3 v_world_position;
in vec3 v_normal;
in vec2 v_texcoord;

out vec4 frag_color;

uniform SpikeInfo {
  vec4 counts;
  vec4 lights[8];
  vec4 tail;
}
spike_info;

void main() {
  int count = int(spike_info.counts.x);
  vec3 sum = vec3(0.0);
  for (int i = 0; i < 8; i++) {
    if (i >= count) break;
    sum += spike_info.lights[i].rgb;
  }
  frag_color = vec4(sum + spike_info.tail.rgb, 1.0);
}
