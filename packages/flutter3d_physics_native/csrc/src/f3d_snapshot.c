/*
 * The world's whole state in one buffer, and back — P9.
 *
 * A header, the world's plain state, the arena's slots up to its high-water
 * mark, the wind grid and the events waiting. Slots are copied whole: they
 * are zeroed when taken, so their padding is the same bytes every time, and
 * a snapshot of the same world is the same bytes. The header says which
 * build wrote it — the real's size and the layouts' — so a snapshot is
 * refused by a build that would read it wrongly, rather than misread.
 */
#include "f3d_internal.h"

#define F3D_SNAPSHOT_MAGIC 0x53443346u /* "F3DS", little-endian. */
#define F3D_SNAPSHOT_VERSION 19u

typedef struct F3dSnapshotHeader {
  uint32_t magic;
  uint32_t version;
  uint32_t real_bytes;
  uint32_t state_bytes;
  uint32_t slot_bytes;
  uint32_t event_bytes;
  uint32_t manifold_bytes;
  uint32_t hull_bytes;
  uint32_t mesh_bytes;
  uint32_t joint_bytes;
  uint32_t compound_bytes;
  uint32_t part_bytes;
  uint32_t vehicle_bytes;
  uint32_t multibody_bytes;
  uint32_t lump_bytes;
  uint32_t shallow_bytes;
  uint32_t spray_bytes;
  uint32_t bubble_bytes;
} F3dSnapshotHeader;

static uint64_t grid_reals(const F3dWorldState *s) {
  return (uint64_t)s->grid_n[0] * s->grid_n[1] * s->grid_n[2] * 3u;
}

static uint64_t size_of(const F3dWorldState *s) {
  return (uint64_t)sizeof(F3dSnapshotHeader) + sizeof(F3dWorldState) +
         (uint64_t)s->used * sizeof(F3dSlot) +
         grid_reals(s) * sizeof(f3d_real) +
         (uint64_t)s->events_count * sizeof(F3dEventRecord) +
         (uint64_t)s->manifold_count * sizeof(F3dManifold) +
         (uint64_t)s->hull_count * sizeof(F3dHull) +
         (uint64_t)s->hull_vertex_count * 3u * sizeof(f3d_real) +
         (uint64_t)s->hull_triangle_count * 3u * sizeof(uint32_t) +
         (uint64_t)s->mesh_count * sizeof(F3dMesh) +
         (uint64_t)s->mesh_vertex_count * 3u * sizeof(f3d_real) +
         (uint64_t)s->mesh_triangle_count * (3u * sizeof(uint32_t) + 1u) +
         (uint64_t)s->joint_used * sizeof(F3dJointSlot) +
         (uint64_t)s->compound_count * sizeof(F3dCompound) +
         (uint64_t)s->compound_part_count * sizeof(F3dCompoundPart) +
         (uint64_t)s->vehicle_count * sizeof(F3dVehicleSlot) +
         (uint64_t)s->multibody_count * sizeof(F3dMultibodySlot) +
         (uint64_t)s->lump_count * sizeof(F3dLump) +
         (uint64_t)s->shallow_count * sizeof(F3dShallowSlot) +
         (uint64_t)s->shallow_reals * sizeof(f3d_real) +
         (uint64_t)s->spray_count * sizeof(F3dSpray) +
         (uint64_t)s->bubble_count * sizeof(F3dBubbles);
}

uint32_t f3d_world_snapshot_size(const F3dWorld *world) {
  const uint64_t size = size_of(&world->s);
  return size > UINT32_MAX ? 0u : (uint32_t)size;
}

uint32_t f3d_world_snapshot_write(const F3dWorld *world, uint8_t *buffer,
                                  uint32_t size) {
  const uint32_t needed = f3d_world_snapshot_size(world);
  if (needed == 0 || size < needed || buffer == NULL) return 0;
  F3dSnapshotHeader header;
  f3d_zero(&header, sizeof header);
  header.magic = F3D_SNAPSHOT_MAGIC;
  header.version = F3D_SNAPSHOT_VERSION;
  header.real_bytes = (uint32_t)sizeof(f3d_real);
  header.state_bytes = (uint32_t)sizeof(F3dWorldState);
  header.slot_bytes = (uint32_t)sizeof(F3dSlot);
  header.event_bytes = (uint32_t)sizeof(F3dEventRecord);
  header.manifold_bytes = (uint32_t)sizeof(F3dManifold);
  header.hull_bytes = (uint32_t)sizeof(F3dHull);
  header.mesh_bytes = (uint32_t)sizeof(F3dMesh);
  header.joint_bytes = (uint32_t)sizeof(F3dJointSlot);
  header.compound_bytes = (uint32_t)sizeof(F3dCompound);
  header.part_bytes = (uint32_t)sizeof(F3dCompoundPart);
  header.vehicle_bytes = (uint32_t)sizeof(F3dVehicleSlot);
  header.multibody_bytes = (uint32_t)sizeof(F3dMultibodySlot);
  header.lump_bytes = (uint32_t)sizeof(F3dLump);
  header.shallow_bytes = (uint32_t)sizeof(F3dShallowSlot);
  header.spray_bytes = (uint32_t)sizeof(F3dSpray);
  header.bubble_bytes = (uint32_t)sizeof(F3dBubbles);
  uint8_t *at = buffer;
  f3d_copy(at, &header, sizeof header);
  at += sizeof header;
  /* The events go out oldest first from nought, so the same queue is the
   * same bytes wherever its ring happened to start. */
  /* Copied by bytes, not assigned: an assignment need not carry the
   * padding, and the padding is part of what makes two snapshots of one
   * world the same bytes. */
  F3dWorldState state;
  f3d_copy(&state, &world->s, sizeof state);
  state.events_head = 0;
  f3d_copy(at, &state, sizeof state);
  at += sizeof state;
  if (world->s.used > 0) {
    f3d_copy(at, world->slots, (size_t)world->s.used * sizeof(F3dSlot));
    at += (size_t)world->s.used * sizeof(F3dSlot);
  }
  const uint64_t reals = grid_reals(&world->s);
  if (reals > 0) {
    f3d_copy(at, world->grid, (size_t)reals * sizeof(f3d_real));
    at += (size_t)reals * sizeof(f3d_real);
  }
  for (uint32_t i = 0; i < world->s.events_count; i++) {
    const uint32_t from = (world->s.events_head + i) % F3D_EVENT_CAPACITY;
    f3d_copy(at, &world->events[from], sizeof(F3dEventRecord));
    at += sizeof(F3dEventRecord);
  }
  /* The contacts: what the next step compares against to say what began
   * and ended, and what two sleeping bodies keep. */
  if (world->s.manifold_count > 0) {
    f3d_copy(at, world->manifolds,
             (size_t)world->s.manifold_count * sizeof(F3dManifold));
    at += (size_t)world->s.manifold_count * sizeof(F3dManifold);
  }
  /* The hulls the bodies are shaped as. */
  if (world->s.hull_count > 0) {
    f3d_copy(at, world->hulls, (size_t)world->s.hull_count * sizeof(F3dHull));
    at += (size_t)world->s.hull_count * sizeof(F3dHull);
    f3d_copy(at, world->hull_vertices,
             (size_t)world->s.hull_vertex_count * 3u * sizeof(f3d_real));
    at += (size_t)world->s.hull_vertex_count * 3u * sizeof(f3d_real);
    f3d_copy(at, world->hull_triangles,
             (size_t)world->s.hull_triangle_count * 3u * sizeof(uint32_t));
    at += (size_t)world->s.hull_triangle_count * 3u * sizeof(uint32_t);
  }
  /* The meshes. */
  if (world->s.mesh_count > 0) {
    f3d_copy(at, world->meshes, (size_t)world->s.mesh_count * sizeof(F3dMesh));
    at += (size_t)world->s.mesh_count * sizeof(F3dMesh);
    f3d_copy(at, world->mesh_vertices,
             (size_t)world->s.mesh_vertex_count * 3u * sizeof(f3d_real));
    at += (size_t)world->s.mesh_vertex_count * 3u * sizeof(f3d_real);
    f3d_copy(at, world->mesh_triangles,
             (size_t)world->s.mesh_triangle_count * 3u * sizeof(uint32_t));
    at += (size_t)world->s.mesh_triangle_count * 3u * sizeof(uint32_t);
    f3d_copy(at, world->mesh_edges, world->s.mesh_triangle_count);
    at += world->s.mesh_triangle_count;
  }
  /* The joints, warm-start impulses and all. */
  if (world->s.joint_used > 0) {
    f3d_copy(at, world->joints,
             (size_t)world->s.joint_used * sizeof(F3dJointSlot));
    at += (size_t)world->s.joint_used * sizeof(F3dJointSlot);
  }
  /* The compounds the bodies are shaped as. */
  if (world->s.compound_count > 0) {
    f3d_copy(at, world->compounds,
             (size_t)world->s.compound_count * sizeof(F3dCompound));
    at += (size_t)world->s.compound_count * sizeof(F3dCompound);
    f3d_copy(at, world->compound_parts,
             (size_t)world->s.compound_part_count * sizeof(F3dCompoundPart));
    at += (size_t)world->s.compound_part_count * sizeof(F3dCompoundPart);
  }
  /* The vehicles, their wheels as the last step left them. */
  if (world->s.vehicle_count > 0) {
    f3d_copy(at, world->vehicles,
             (size_t)world->s.vehicle_count * sizeof(F3dVehicleSlot));
    at += (size_t)world->s.vehicle_count * sizeof(F3dVehicleSlot);
  }
  /* The multibodies, their joints as the last step left them. */
  if (world->s.multibody_count > 0) {
    f3d_copy(at, world->multibodies,
             (size_t)world->s.multibody_count * sizeof(F3dMultibodySlot));
    at += (size_t)world->s.multibody_count * sizeof(F3dMultibodySlot);
  }
  /* The compounds' parts' heat. */
  if (world->s.lump_count > 0) {
    f3d_copy(at, world->lumps, (size_t)world->s.lump_count * sizeof(F3dLump));
    at += (size_t)world->s.lump_count * sizeof(F3dLump);
  }
  /* The waters, their grids and their spray in flight. */
  if (world->s.shallow_count > 0) {
    f3d_copy(at, world->shallows, (size_t)world->s.shallow_count * sizeof(F3dShallowSlot));
    at += (size_t)world->s.shallow_count * sizeof(F3dShallowSlot);
  }
  if (world->s.shallow_reals > 0) {
    f3d_copy(at, world->shallow_data, (size_t)world->s.shallow_reals * sizeof(f3d_real));
    at += (size_t)world->s.shallow_reals * sizeof(f3d_real);
  }
  if (world->s.spray_count > 0) {
    f3d_copy(at, world->spray, (size_t)world->s.spray_count * sizeof(F3dSpray));
    at += (size_t)world->s.spray_count * sizeof(F3dSpray);
  }
  if (world->s.bubble_count > 0) {
    f3d_copy(at, world->bubbles, (size_t)world->s.bubble_count * sizeof(F3dBubbles));
  }
  return needed;
}

int f3d_world_restore(F3dWorld *world, const uint8_t *buffer, uint32_t size) {
  if (buffer == NULL || size < sizeof(F3dSnapshotHeader)) return 0;
  F3dSnapshotHeader header;
  f3d_copy(&header, buffer, sizeof header);
  if (header.magic != F3D_SNAPSHOT_MAGIC ||
      header.version != F3D_SNAPSHOT_VERSION ||
      header.real_bytes != sizeof(f3d_real) ||
      header.state_bytes != sizeof(F3dWorldState) ||
      header.slot_bytes != sizeof(F3dSlot) ||
      header.event_bytes != sizeof(F3dEventRecord) ||
      header.manifold_bytes != sizeof(F3dManifold) ||
      header.hull_bytes != sizeof(F3dHull) ||
      header.mesh_bytes != sizeof(F3dMesh) ||
      header.joint_bytes != sizeof(F3dJointSlot) ||
      header.compound_bytes != sizeof(F3dCompound) ||
      header.part_bytes != sizeof(F3dCompoundPart) ||
      header.vehicle_bytes != sizeof(F3dVehicleSlot) ||
      header.multibody_bytes != sizeof(F3dMultibodySlot) ||
      header.lump_bytes != sizeof(F3dLump) ||
      header.shallow_bytes != sizeof(F3dShallowSlot) ||
      header.spray_bytes != sizeof(F3dSpray) ||
      header.bubble_bytes != sizeof(F3dBubbles)) {
    return 0;
  }
  if (size < sizeof header + sizeof(F3dWorldState)) return 0;
  F3dWorldState state;
  f3d_copy(&state, buffer + sizeof header, sizeof state);
  if (size_of(&state) != size) return 0;
  if (state.events_count > F3D_EVENT_CAPACITY || state.live > state.used ||
      state.free_head > state.used || state.events_head != 0) {
    return 0;
  }
  const uint8_t *at = buffer + sizeof header + sizeof state;
  /* Everything allocated before anything is replaced, so a restore that
   * runs out of memory leaves the world as it was. */
  F3dSlot *slots = NULL;
  const uint32_t capacity = state.used;
  if (capacity > 0) {
    slots = (F3dSlot *)f3d_alloc((size_t)capacity * sizeof(F3dSlot));
    if (slots == NULL) return 0;
  }
  const uint64_t reals = grid_reals(&state);
  f3d_real *grid = NULL;
  if (reals > 0) {
    grid = (f3d_real *)f3d_alloc((size_t)reals * sizeof(f3d_real));
    if (grid == NULL) {
      f3d_free(slots);
      return 0;
    }
  }
  F3dEventRecord *events = NULL;
  if (state.events_count > 0) {
    events = (F3dEventRecord *)f3d_alloc((size_t)F3D_EVENT_CAPACITY *
                                         sizeof(F3dEventRecord));
    if (events == NULL) {
      f3d_free(slots);
      f3d_free(grid);
      return 0;
    }
    f3d_zero(events, (size_t)F3D_EVENT_CAPACITY * sizeof(F3dEventRecord));
  }
  if (capacity > 0) {
    f3d_copy(slots, at, (size_t)capacity * sizeof(F3dSlot));
    at += (size_t)capacity * sizeof(F3dSlot);
  }
  if (reals > 0) {
    f3d_copy(grid, at, (size_t)reals * sizeof(f3d_real));
    at += (size_t)reals * sizeof(f3d_real);
  }
  F3dManifold *manifolds = NULL;
  if (state.manifold_count > 0) {
    manifolds = (F3dManifold *)f3d_alloc((size_t)state.manifold_count *
                                         sizeof(F3dManifold));
    if (manifolds == NULL) {
      f3d_free(slots);
      f3d_free(grid);
      f3d_free(events);
      return 0;
    }
  }
  F3dHull *hulls = NULL;
  f3d_real *hull_vertices = NULL;
  uint32_t *hull_triangles = NULL;
  if (state.hull_count > 0) {
    hulls = (F3dHull *)f3d_alloc((size_t)state.hull_count * sizeof(F3dHull));
    hull_vertices = (f3d_real *)f3d_alloc(
        (size_t)state.hull_vertex_count * 3u * sizeof(f3d_real) + 1u);
    hull_triangles = (uint32_t *)f3d_alloc(
        (size_t)state.hull_triangle_count * 3u * sizeof(uint32_t) + 1u);
    if (hulls == NULL || hull_vertices == NULL || hull_triangles == NULL) {
      f3d_free(hulls);
      f3d_free(hull_vertices);
      f3d_free(hull_triangles);
      f3d_free(slots);
      f3d_free(grid);
      f3d_free(events);
      f3d_free(manifolds);
      return 0;
    }
  }
  F3dMesh *meshes = NULL;
  f3d_real *mesh_vertices = NULL;
  uint32_t *mesh_triangles = NULL;
  uint8_t *mesh_edges = NULL;
  if (state.mesh_count > 0) {
    meshes = (F3dMesh *)f3d_alloc((size_t)state.mesh_count * sizeof(F3dMesh));
    mesh_vertices = (f3d_real *)f3d_alloc(
        (size_t)state.mesh_vertex_count * 3u * sizeof(f3d_real) + 1u);
    mesh_triangles = (uint32_t *)f3d_alloc(
        (size_t)state.mesh_triangle_count * 3u * sizeof(uint32_t) + 1u);
    mesh_edges = (uint8_t *)f3d_alloc((size_t)state.mesh_triangle_count + 1u);
    if (meshes == NULL || mesh_vertices == NULL || mesh_triangles == NULL ||
        mesh_edges == NULL) {
      f3d_free(meshes);
      f3d_free(mesh_vertices);
      f3d_free(mesh_triangles);
      f3d_free(mesh_edges);
      f3d_free(hulls);
      f3d_free(hull_vertices);
      f3d_free(hull_triangles);
      f3d_free(slots);
      f3d_free(grid);
      f3d_free(events);
      f3d_free(manifolds);
      return 0;
    }
  }
  F3dJointSlot *joints = NULL;
  if (state.joint_used > 0) {
    joints = (F3dJointSlot *)f3d_alloc((size_t)state.joint_used *
                                       sizeof(F3dJointSlot));
    if (joints == NULL) {
      f3d_free(meshes);
      f3d_free(mesh_vertices);
      f3d_free(mesh_triangles);
      f3d_free(mesh_edges);
      f3d_free(hulls);
      f3d_free(hull_vertices);
      f3d_free(hull_triangles);
      f3d_free(slots);
      f3d_free(grid);
      f3d_free(events);
      f3d_free(manifolds);
      return 0;
    }
  }
  F3dCompound *compounds = NULL;
  F3dCompoundPart *compound_parts = NULL;
  if (state.compound_count > 0) {
    compounds = (F3dCompound *)f3d_alloc((size_t)state.compound_count *
                                         sizeof(F3dCompound));
    compound_parts = (F3dCompoundPart *)f3d_alloc(
        (size_t)state.compound_part_count * sizeof(F3dCompoundPart) + 1u);
    if (compounds == NULL || compound_parts == NULL) {
      f3d_free(compounds);
      f3d_free(compound_parts);
      f3d_free(joints);
      f3d_free(meshes);
      f3d_free(mesh_vertices);
      f3d_free(mesh_triangles);
      f3d_free(mesh_edges);
      f3d_free(hulls);
      f3d_free(hull_vertices);
      f3d_free(hull_triangles);
      f3d_free(slots);
      f3d_free(grid);
      f3d_free(events);
      f3d_free(manifolds);
      return 0;
    }
  }
  F3dVehicleSlot *vehicles = NULL;
  F3dMultibodySlot *multibodies = NULL;
  F3dLump *lumps = NULL;
  F3dShallowSlot *waters = NULL;
  f3d_real *shallow_data = NULL;
  F3dSpray *spray = NULL;
  F3dBubbles *bubbles = NULL;
  if (state.bubble_count > 0) {
    bubbles = (F3dBubbles *)f3d_alloc(F3D_SHALLOW_MOST_BUBBLES * sizeof(F3dBubbles));
  }
  if (state.shallow_count > 0) {
    waters = (F3dShallowSlot *)f3d_alloc((size_t)state.shallow_count * sizeof(F3dShallowSlot));
  }
  if (state.shallow_reals > 0) {
    shallow_data = (f3d_real *)f3d_alloc((size_t)state.shallow_reals * sizeof(f3d_real));
  }
  if (state.spray_count > 0) {
    spray = (F3dSpray *)f3d_alloc(F3D_SHALLOW_MOST_SPRAY * sizeof(F3dSpray));
  }
  if (state.lump_count > 0) {
    lumps = (F3dLump *)f3d_alloc((size_t)state.lump_count * sizeof(F3dLump));
  }
  if (state.multibody_count > 0) {
    multibodies = (F3dMultibodySlot *)f3d_alloc(
        (size_t)state.multibody_count * sizeof(F3dMultibodySlot));
  }
  if (state.vehicle_count > 0) {
    vehicles = (F3dVehicleSlot *)f3d_alloc((size_t)state.vehicle_count *
                                           sizeof(F3dVehicleSlot));
  }
  if ((state.vehicle_count > 0 && vehicles == NULL) ||
      (state.multibody_count > 0 && multibodies == NULL) ||
      (state.lump_count > 0 && lumps == NULL) ||
      (state.shallow_count > 0 && waters == NULL) ||
      (state.shallow_reals > 0 && shallow_data == NULL) ||
      (state.spray_count > 0 && spray == NULL) ||
      (state.bubble_count > 0 && bubbles == NULL) ||
      state.spray_count > F3D_SHALLOW_MOST_SPRAY ||
      state.bubble_count > F3D_SHALLOW_MOST_BUBBLES) {
    f3d_free(bubbles);
    f3d_free(waters);
    f3d_free(shallow_data);
    f3d_free(spray);
    f3d_free(lumps);
    f3d_free(vehicles);
    f3d_free(multibodies);
    f3d_free(compounds);
    f3d_free(compound_parts);
    f3d_free(joints);
    f3d_free(meshes);
    f3d_free(mesh_vertices);
    f3d_free(mesh_triangles);
    f3d_free(mesh_edges);
    f3d_free(hulls);
    f3d_free(hull_vertices);
    f3d_free(hull_triangles);
    f3d_free(slots);
    f3d_free(grid);
    f3d_free(events);
    f3d_free(manifolds);
    return 0;
  }
  if (events != NULL) {
    f3d_copy(events, at, (size_t)state.events_count * sizeof(F3dEventRecord));
    at += (size_t)state.events_count * sizeof(F3dEventRecord);
  }
  if (manifolds != NULL) {
    f3d_copy(manifolds, at,
             (size_t)state.manifold_count * sizeof(F3dManifold));
    at += (size_t)state.manifold_count * sizeof(F3dManifold);
  }
  if (hulls != NULL) {
    f3d_copy(hulls, at, (size_t)state.hull_count * sizeof(F3dHull));
    at += (size_t)state.hull_count * sizeof(F3dHull);
    f3d_copy(hull_vertices, at,
             (size_t)state.hull_vertex_count * 3u * sizeof(f3d_real));
    at += (size_t)state.hull_vertex_count * 3u * sizeof(f3d_real);
    f3d_copy(hull_triangles, at,
             (size_t)state.hull_triangle_count * 3u * sizeof(uint32_t));
    at += (size_t)state.hull_triangle_count * 3u * sizeof(uint32_t);
  }
  if (meshes != NULL) {
    f3d_copy(meshes, at, (size_t)state.mesh_count * sizeof(F3dMesh));
    at += (size_t)state.mesh_count * sizeof(F3dMesh);
    f3d_copy(mesh_vertices, at,
             (size_t)state.mesh_vertex_count * 3u * sizeof(f3d_real));
    at += (size_t)state.mesh_vertex_count * 3u * sizeof(f3d_real);
    f3d_copy(mesh_triangles, at,
             (size_t)state.mesh_triangle_count * 3u * sizeof(uint32_t));
    at += (size_t)state.mesh_triangle_count * 3u * sizeof(uint32_t);
    f3d_copy(mesh_edges, at, state.mesh_triangle_count);
    at += state.mesh_triangle_count;
  }
  if (joints != NULL) {
    f3d_copy(joints, at, (size_t)state.joint_used * sizeof(F3dJointSlot));
    at += (size_t)state.joint_used * sizeof(F3dJointSlot);
  }
  if (compounds != NULL) {
    f3d_copy(compounds, at, (size_t)state.compound_count * sizeof(F3dCompound));
    at += (size_t)state.compound_count * sizeof(F3dCompound);
    f3d_copy(compound_parts, at,
             (size_t)state.compound_part_count * sizeof(F3dCompoundPart));
    at += (size_t)state.compound_part_count * sizeof(F3dCompoundPart);
  }
  if (vehicles != NULL) {
    f3d_copy(vehicles, at,
             (size_t)state.vehicle_count * sizeof(F3dVehicleSlot));
    at += (size_t)state.vehicle_count * sizeof(F3dVehicleSlot);
  }
  if (multibodies != NULL) {
    f3d_copy(multibodies, at,
             (size_t)state.multibody_count * sizeof(F3dMultibodySlot));
    at += (size_t)state.multibody_count * sizeof(F3dMultibodySlot);
  }
  if (lumps != NULL) {
    f3d_copy(lumps, at, (size_t)state.lump_count * sizeof(F3dLump));
    at += (size_t)state.lump_count * sizeof(F3dLump);
  }
  if (waters != NULL) {
    f3d_copy(waters, at, (size_t)state.shallow_count * sizeof(F3dShallowSlot));
    at += (size_t)state.shallow_count * sizeof(F3dShallowSlot);
  }
  if (shallow_data != NULL) {
    f3d_copy(shallow_data, at, (size_t)state.shallow_reals * sizeof(f3d_real));
    at += (size_t)state.shallow_reals * sizeof(f3d_real);
  }
  if (spray != NULL) {
    f3d_copy(spray, at, (size_t)state.spray_count * sizeof(F3dSpray));
    at += (size_t)state.spray_count * sizeof(F3dSpray);
  }
  if (bubbles != NULL) {
    f3d_copy(bubbles, at, (size_t)state.bubble_count * sizeof(F3dBubbles));
  }
  f3d_free(world->vehicles);
  world->vehicles = vehicles;
  f3d_free(world->multibodies);
  world->multibodies = multibodies;
  f3d_free(world->lumps);
  world->lumps = lumps;
  f3d_free(world->shallows);
  world->shallows = waters;
  f3d_free(world->shallow_data);
  world->shallow_data = shallow_data;
  f3d_free(world->spray);
  world->spray = spray;
  f3d_free(world->bubbles);
  world->bubbles = bubbles;
  f3d_free(world->compounds);
  f3d_free(world->compound_parts);
  world->compounds = compounds;
  world->compound_parts = compound_parts;
  f3d_free(world->slots);
  f3d_free(world->manifolds);
  f3d_free(world->grid);
  f3d_free(world->events);
  f3d_free(world->hulls);
  f3d_free(world->hull_vertices);
  f3d_free(world->hull_triangles);
  f3d_copy(&world->s, &state, sizeof state);
  world->hulls = hulls;
  world->hull_vertices = hull_vertices;
  world->hull_triangles = hull_triangles;
  f3d_free(world->meshes);
  f3d_free(world->mesh_vertices);
  f3d_free(world->mesh_triangles);
  f3d_free(world->mesh_edges);
  world->meshes = meshes;
  world->mesh_vertices = mesh_vertices;
  world->mesh_triangles = mesh_triangles;
  world->mesh_edges = mesh_edges;
  /* The meshes' trees are built again from them by the next step. */
  f3d_clear_mesh_trees(world);
  f3d_free(world->joints);
  world->joints = joints;
  world->joint_capacity = state.joint_used;
  world->joined_stale = 1;
  world->slots = slots;
  world->capacity = capacity;
  world->grid = grid;
  world->events = events;
  world->manifolds = manifolds;
  world->manifold_capacity = state.manifold_count;
  /* The tree is not in a snapshot: built again by the next step. */
  f3d_tree_clear(&world->tree);
  f3d_free(world->proxies);
  world->proxies = NULL;
  world->proxy_capacity = 0;
  world->pairs_ready = 0;
  return 1;
}
