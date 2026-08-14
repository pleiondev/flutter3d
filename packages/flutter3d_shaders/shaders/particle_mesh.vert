#version 460 core

// Vertex stage for mesh particles: one mesh, drawn once per particle.
//
// The billboard path (particle.vert) expands each particle into a quad on the
// CPU and sends four vertices per particle. That is the right trade for a
// sprite, where the quad *is* the particle and building it costs four writes.
// It is the wrong trade for a mesh: a hundred embers of forty vertices each
// would be four thousand vertices rewritten every frame, when the geometry
// never changes and only the placement does.
//
// So this reads two buffers. The mesh sits in slot 0 and is uploaded once; the
// placements sit in slot 1, are rebuilt each frame, and step once per instance.
// That split is the whole reason `VertexLayoutSpec` exists.
in vec3 position;
in vec3 normal;

/// Where this instance's copy of the mesh goes, in world space.
in vec3 i_position;

/// Linear RGB with alpha as brightness, matching Particle.color. These draw
/// additively, so alpha is not coverage.
in vec4 i_color;

/// Uniform scale. One number rather than three, because a particle's size is
/// one number everywhere else in this engine and a non-uniform scale would need
/// the normal transformed by an inverse transpose to stay a normal.
in float i_scale;

uniform ParticleMeshInfo {
  mat4 view_projection;
}
particle_mesh_info;

out vec4 v_color;
out vec3 v_world_position;
out vec3 v_normal;

void main() {
  // Scale and translate, and no rotation. A rotation per instance is four more
  // floats and a matrix build per vertex; it is worth having and it is not
  // worth guessing at before something asks. What is here is what an ember or a
  // shard needs: a size, a place, and a colour.
  vec3 world = i_position + position * i_scale;

  v_color = i_color;
  v_world_position = world;
  // Uniform scale leaves a normal a normal, which is the second reason the
  // scale is one number.
  v_normal = normal;

  gl_Position = particle_mesh_info.view_projection * vec4(world, 1.0);
}
