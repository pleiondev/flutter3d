/*
 * Triangle meshes — P9, phase 6: level geometry, terrain and walls, held by
 * the world for fixed bodies to be shaped as.
 *
 * A mesh is its vertices and triangles as given, a byte of flags a triangle
 * saying which of its edges are internal, and a tree of its triangles. An
 * edge is internal when another triangle shares it by index and the fold
 * between them is flat or hollow: a body sliding across it is still on the
 * same surface, and a contact there takes the face's normal rather than
 * the edge's, so a crate sliding over a floor of a thousand triangles does
 * not trip on their seams. A ridge — a fold that sticks out — is a real
 * edge and keeps its own normal.
 *
 * The trees are built from the triangles in their order and are not in a
 * snapshot; the contacts do not depend on their shape, since the triangles
 * a query finds are taken in index order.
 */
#include "f3d_internal.h"

#define F3D_MESH_TRIANGLES (1u << 20)

/* One edge of one triangle, by its two vertex indices, lower first. */
typedef struct EdgeKey {
  uint64_t key;
  uint32_t triangle;
  uint32_t edge;
} EdgeKey;

static void sort_edges(EdgeKey *items, EdgeKey *spare, uint32_t count) {
  for (uint32_t width = 1; width < count; width *= 2u) {
    for (uint32_t lo = 0; lo < count; lo += 2u * width) {
      const uint32_t mid = lo + width < count ? lo + width : count;
      const uint32_t hi = lo + 2u * width < count ? lo + 2u * width : count;
      uint32_t i = lo, j = mid, k = lo;
      while (i < mid && j < hi) {
        spare[k++] = items[j].key < items[i].key ? items[j++] : items[i++];
      }
      while (i < mid) spare[k++] = items[i++];
      while (j < hi) spare[k++] = items[j++];
    }
    for (uint32_t k = 0; k < count; k++) items[k] = spare[k];
    if (width > UINT32_MAX / 2u) break;
  }
}

static F3dVec3 vertex(const f3d_real *v, uint32_t i) {
  return f3d_v3(v[i * 3u], v[i * 3u + 1u], v[i * 3u + 2u]);
}

uint32_t f3d_world_create_mesh(F3dWorld *world, const f3d_real *vertices,
                               uint32_t vertex_count, const uint32_t *indices,
                               uint32_t triangle_count) {
  if (vertices == NULL || indices == NULL || triangle_count == 0 ||
      triangle_count > F3D_MESH_TRIANGLES || vertex_count < 3u ||
      vertex_count > 3u * F3D_MESH_TRIANGLES) {
    return 0;
  }
  for (uint32_t i = 0; i < vertex_count * 3u; i++) {
    if (!f3d_finite(vertices[i])) return 0;
  }
  for (uint32_t i = 0; i < triangle_count * 3u; i++) {
    if (indices[i] >= vertex_count) return 0;
  }
  const uint32_t edge_count = triangle_count * 3u;
  EdgeKey *edges = (EdgeKey *)f3d_alloc((size_t)edge_count * sizeof(EdgeKey));
  EdgeKey *spare = (EdgeKey *)f3d_alloc((size_t)edge_count * sizeof(EdgeKey));
  uint8_t *flags = (uint8_t *)f3d_alloc(triangle_count);
  uint32_t result = 0;
  if (edges == NULL || spare == NULL || flags == NULL) goto done;
  f3d_zero(flags, triangle_count);
  for (uint32_t t = 0; t < triangle_count; t++) {
    for (uint32_t k = 0; k < 3u; k++) {
      const uint32_t a = indices[t * 3u + k];
      const uint32_t b = indices[t * 3u + (k + 1u) % 3u];
      EdgeKey *e = &edges[t * 3u + k];
      e->key = a < b ? ((uint64_t)a << 32) | b : ((uint64_t)b << 32) | a;
      e->triangle = t;
      e->edge = k;
    }
  }
  sort_edges(edges, spare, edge_count);
  /* The span, for what counts as flat. */
  F3dVec3 lo = vertex(vertices, indices[0]), hi = lo;
  for (uint32_t i = 0; i < triangle_count * 3u; i++) {
    const F3dVec3 v = vertex(vertices, indices[i]);
    lo = f3d_v3(f3d_min(lo.x, v.x), f3d_min(lo.y, v.y), f3d_min(lo.z, v.z));
    hi = f3d_v3(f3d_max(hi.x, v.x), f3d_max(hi.y, v.y), f3d_max(hi.z, v.z));
  }
  const F3dVec3 span = f3d_sub(hi, lo);
  const f3d_real flat = F3D_R(1e-5) * f3d_sqrt(f3d_dot(span, span));
  /* Each pair of triangles sharing an edge: internal unless the fold is a
   * ridge — the other triangle's far corner below this one's plane. Both
   * sides of an edge see the same fold, so both get the same flag. An edge
   * three triangles share is no surface's edge, and stays a real one. */
  for (uint32_t i = 0; i + 1u < edge_count;) {
    uint32_t j = i + 1u;
    while (j < edge_count && edges[j].key == edges[i].key) j++;
    if (j - i == 2u) {
      const EdgeKey *e0 = &edges[i], *e1 = &edges[i + 1u];
      const uint32_t *t0 = &indices[e0->triangle * 3u];
      const uint32_t *t1 = &indices[e1->triangle * 3u];
      const F3dVec3 a = vertex(vertices, t0[0]);
      const F3dVec3 n0 = f3d_cross(f3d_sub(vertex(vertices, t0[1]), a),
                                   f3d_sub(vertex(vertices, t0[2]), a));
      const f3d_real len = f3d_sqrt(f3d_dot(n0, n0));
      const F3dVec3 far = vertex(vertices, t1[(e1->edge + 2u) % 3u]);
      const f3d_real below =
          len > F3D_R(0.0) ? f3d_dot(n0, f3d_sub(far, a)) / len : F3D_R(0.0);
      if (below >= -flat) {
        flags[e0->triangle] |= (uint8_t)(1u << e0->edge);
        flags[e1->triangle] |= (uint8_t)(1u << e1->edge);
      }
    }
    i = j;
  }
  /* Into the world's arrays: every allocation before anything is kept. */
  const uint32_t first_vertex = world->s.mesh_vertex_count;
  const uint32_t first_triangle = world->s.mesh_triangle_count;
  f3d_real *wv = (f3d_real *)f3d_realloc(
      world->mesh_vertices,
      ((size_t)first_vertex + vertex_count) * 3u * sizeof(f3d_real));
  if (wv == NULL) goto done;
  world->mesh_vertices = wv;
  uint32_t *wt = (uint32_t *)f3d_realloc(
      world->mesh_triangles,
      ((size_t)first_triangle + triangle_count) * 3u * sizeof(uint32_t));
  if (wt == NULL) goto done;
  world->mesh_triangles = wt;
  uint8_t *we = (uint8_t *)f3d_realloc(
      world->mesh_edges, (size_t)first_triangle + triangle_count);
  if (we == NULL) goto done;
  world->mesh_edges = we;
  F3dMesh *meshes = (F3dMesh *)f3d_realloc(
      world->meshes, ((size_t)world->s.mesh_count + 1u) * sizeof(F3dMesh));
  if (meshes == NULL) goto done;
  world->meshes = meshes;
  f3d_copy(wv + (size_t)first_vertex * 3u, vertices,
           (size_t)vertex_count * 3u * sizeof(f3d_real));
  f3d_copy(wt + (size_t)first_triangle * 3u, indices,
           (size_t)triangle_count * 3u * sizeof(uint32_t));
  f3d_copy(we + first_triangle, flags, triangle_count);
  F3dMesh m;
  f3d_zero(&m, sizeof m);
  m.first_vertex = first_vertex;
  m.vertex_count = vertex_count;
  m.first_triangle = first_triangle;
  m.triangle_count = triangle_count;
  m.lo = lo;
  m.hi = hi;
  for (uint32_t t = 0; t < triangle_count; t++) {
    const F3dVec3 a = vertex(vertices, indices[t * 3u]);
    const F3dVec3 n = f3d_cross(f3d_sub(vertex(vertices, indices[t * 3u + 1u]), a),
                                f3d_sub(vertex(vertices, indices[t * 3u + 2u]), a));
    m.surface += F3D_R(0.5) * f3d_sqrt(f3d_dot(n, n));
  }
  f3d_copy(&meshes[world->s.mesh_count], &m, sizeof m);
  world->s.mesh_count++;
  world->s.mesh_vertex_count += vertex_count;
  world->s.mesh_triangle_count += triangle_count;
  result = world->s.mesh_count;
  f3d_build_mesh_trees(world);
done:
  f3d_free(edges);
  f3d_free(spare);
  f3d_free(flags);
  return result;
}

void f3d_build_mesh_trees(F3dWorld *world) {
  if (world->mesh_tree_count >= world->s.mesh_count) return;
  F3dTree *trees = (F3dTree *)f3d_realloc(
      world->mesh_trees, (size_t)world->s.mesh_count * sizeof(F3dTree));
  if (trees == NULL) return;
  world->mesh_trees = trees;
  for (uint32_t i = world->mesh_tree_count; i < world->s.mesh_count; i++) {
    F3dTree *tree = &trees[i];
    f3d_zero(tree, sizeof *tree);
    tree->root = -1;
    tree->free_list = -1;
    const F3dMesh *m = &world->meshes[i];
    const f3d_real *v = world->mesh_vertices + (size_t)m->first_vertex * 3u;
    const uint32_t *t = world->mesh_triangles + (size_t)m->first_triangle * 3u;
    for (uint32_t k = 0; k < m->triangle_count; k++) {
      const F3dVec3 a = vertex(v, t[k * 3u]), b = vertex(v, t[k * 3u + 1u]);
      const F3dVec3 c = vertex(v, t[k * 3u + 2u]);
      F3dBox box;
      box.lo = f3d_v3(f3d_min(a.x, f3d_min(b.x, c.x)),
                      f3d_min(a.y, f3d_min(b.y, c.y)),
                      f3d_min(a.z, f3d_min(b.z, c.z)));
      box.hi = f3d_v3(f3d_max(a.x, f3d_max(b.x, c.x)),
                      f3d_max(a.y, f3d_max(b.y, c.y)),
                      f3d_max(a.z, f3d_max(b.z, c.z)));
      f3d_tree_insert(tree, box, k);
    }
  }
  world->mesh_tree_count = world->s.mesh_count;
}

void f3d_clear_mesh_trees(F3dWorld *world) {
  for (uint32_t i = 0; i < world->mesh_tree_count; i++) {
    f3d_tree_clear(&world->mesh_trees[i]);
  }
  f3d_free(world->mesh_trees);
  world->mesh_trees = NULL;
  world->mesh_tree_count = 0;
}

uint32_t f3d_world_mesh_triangle_count(const F3dWorld *world, uint32_t mesh) {
  if (mesh == 0 || mesh > world->s.mesh_count) return 0;
  return world->meshes[mesh - 1u].triangle_count;
}

uint32_t f3d_world_mesh_internal_edges(const F3dWorld *world, uint32_t mesh) {
  if (mesh == 0 || mesh > world->s.mesh_count) return 0;
  const F3dMesh *m = &world->meshes[mesh - 1u];
  uint32_t count = 0;
  for (uint32_t t = 0; t < m->triangle_count; t++) {
    const uint8_t f = world->mesh_edges[m->first_triangle + t];
    count += (f & 1u) + ((f >> 1) & 1u) + ((f >> 2) & 1u);
  }
  /* Each internal edge is counted from both its triangles. */
  return count / 2u;
}

int f3d_body_set_mesh(F3dWorld *world, F3dBody body, uint32_t mesh) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || mesh == 0 || mesh > world->s.mesh_count) return 0;
  if (s->type != F3D_BODY_FIXED) return 0;
  s->shape = F3D_SHAPE_MESH;
  s->hull = mesh;
  s->rounding = F3D_R(0.0);
  s->size = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  f3d_refresh_mass(world, s);
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}
