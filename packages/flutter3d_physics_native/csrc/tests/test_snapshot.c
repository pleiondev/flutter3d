/*
 * Snapshots, tested in C — P9: a world restored from one steps to the same
 * bits as the world it was taken from, the same world is the same bytes,
 * and every subsystem the world holds comes back field for field. The
 * format is read across versions: a section it does not know is skipped,
 * a later version's extra fields are passed over, an earlier version of a
 * section is migrated, and what it cannot read — a snapshot from before
 * 1.0.0, a later major, damage — is refused with the world left as it was.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

/* A world with something of everything in it: bodies turning, falling
 * through a wind grid, one burning, one wet, a fixed one in a freed slot,
 * and events waiting. */
static F3dWorld *busy_world(F3dBody *keep) {
  F3dWorld *w = f3d_world_create();
  f3d_world_shift_origin(w, 1234.5, -6.25, 1e5);
  const f3d_real grid[12] = {1, 0, 0, 0, 0, 2, -1, 0, 0, 0, 3, 0};
  f3d_world_set_wind_grid(w, -5, 0, -5, 5, 2, 1, 2, grid);
  F3dMaterial wood;
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);
  for (int i = 0; i < 6; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, (f3d_real)i,
                                      (f3d_real)(i * 2), 0, F3D_R(0.5) + i);
    f3d_body_set_shape(w, b, (F3dShapeKind)(1 + i % 3), F3D_R(0.2),
                       F3D_R(0.3), F3D_R(0.1));
    f3d_body_set_angular_velocity(w, b, F3D_R(0.3) * i, 1, F3D_R(-0.7));
    f3d_body_set_material(w, b, &wood);
    keep[i] = b;
  }
  f3d_body_set_temperature(w, keep[1], 690);
  f3d_body_add_water(w, keep[2], F3D_R(0.02));
  f3d_body_destroy(w, keep[3]);
  const F3dBody sleeper = f3d_body_create(w, F3D_BODY_FIXED, 9, 9, 9, 1);
  keep[3] = sleeper;
  for (int i = 0; i < 30; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
  return w;
}

/* A stream off a cliff into a pond, [nx] × 24 cells of a quarter metre
 * from (ox, 0, 0): spray in the air and bubbles under the falls. */
static F3dShallow falls(F3dWorld *w, f3d_real ox, int nx) {
  f3d_real *ground = (f3d_real *)malloc((size_t)nx * 24 * sizeof(f3d_real));
  for (int j = 0; j < 24; j++) {
    for (int i = 0; i < nx; i++) {
      const double x = i * 0.25;
      const double channel = 0.4 * fabs((j - 12) * 0.25);
      ground[i + j * nx] = (f3d_real)(x < 6 ? 4.0 - 0.1 * x + channel
                                            : 0.02 * fabs(x - 9) + 0.2 * channel);
    }
  }
  const F3dShallow water =
      f3d_shallow_create(w, (uint32_t)nx, 24, F3D_R(0.25), ox, 0, 0, ground);
  free(ground);
  f3d_shallow_fill(w, water, ox + F3D_R(6.2), 0, ox + 12, 6, F3D_R(0.8));
  f3d_shallow_set_source(w, water, 0, ox + 1, 3, F3D_R(0.5), F3D_R(0.05));
  f3d_shallow_set_outlet(w, water, 0, ox + F3D_R(11.5), 3, F3D_R(0.75), 1, 0);
  return water;
}

/* Every subsystem the world holds at once: shapes of every kind on a
 * floor, a hull, a mesh and a compound, joints, a car, a chain of links,
 * fire and a burner, a stream with its spray and bubbles, and the water's
 * rest set. Stepped until each has something to say. */
static F3dWorld *full_world(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_shift_origin(w, -77.25, 3.5, 2e4);
  const f3d_real grid[12] = {1, 0, 0, 0, 0, 2, -1, 0, 0, 0, 3, 0};
  f3d_world_set_wind_grid(w, -20, 0, -5, 20, 2, 1, 2, grid);
  f3d_world_set_water_rest(w, F3D_R(1e-3), F3D_R(2.0));
  F3dMaterial wood;
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);

  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, -10, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 15, F3D_R(0.5), 15);
  for (int i = 0; i < 6; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(-6.0) + i,
                                      F3D_R(0.5) + F3D_R(0.3) * i, 4, 1);
    f3d_body_set_shape(w, b, (F3dShapeKind)(1 + i % 3), F3D_R(0.2),
                       F3D_R(0.3), F3D_R(0.1));
    f3d_body_set_angular_velocity(w, b, F3D_R(0.3) * i, 1, F3D_R(-0.7));
    f3d_body_set_material(w, b, &wood);
    if (i == 1) f3d_body_set_temperature(w, b, 700);
    if (i == 2) f3d_body_add_water(w, b, F3D_R(0.02));
    if (i == 3) f3d_body_set_burner(w, b, F3D_R(0.001), NULL);
  }

  const f3d_real corners[18] = {F3D_R(0.3), 0, 0, F3D_R(-0.3), 0, 0,
                                0, F3D_R(0.4), 0, 0, F3D_R(-0.2), 0,
                                0, 0, F3D_R(0.3), 0, 0, F3D_R(-0.3)};
  const uint32_t hull = f3d_world_create_hull(w, corners, 6);
  CHECK(hull != 0);
  const F3dBody gem = f3d_body_create(w, F3D_BODY_DYNAMIC, -2, 1, -2, 2);
  f3d_body_set_hull(w, gem, hull);

  const f3d_real ramp[12] = {-24, 0, -4, -18, 1, -4, -18, 1, 4, -24, 0, 4};
  const uint32_t tris[6] = {0, 2, 1, 0, 3, 2};
  const uint32_t mesh = f3d_world_create_mesh(w, ramp, 4, tris, 2);
  CHECK(mesh != 0);
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(0.1), 0, 0);
  f3d_body_set_mesh(w, ground, mesh);
  const F3dBody slider = f3d_body_create(w, F3D_BODY_DYNAMIC, -20, 2, 0, 1);
  f3d_body_set_shape(w, slider, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.2), F3D_R(0.2));

  const uint32_t kinds[2] = {F3D_SHAPE_BOX, F3D_SHAPE_HULL};
  const uint32_t hulls[2] = {0, hull};
  const f3d_real parts[22] = {F3D_R(0.3), F3D_R(0.1), F3D_R(0.1), 0, 0, 0, 0, 0, 0, 0, 1,
                              0, 0, 0, 0, F3D_R(0.4), 0, 0, 0, 0, 0, 1};
  const uint32_t compound = f3d_world_create_compound(w, kinds, hulls, parts, 2);
  CHECK(compound != 0);
  const F3dBody beam = f3d_body_create(w, F3D_BODY_DYNAMIC, -3, 2, 2, 3);
  f3d_body_set_compound(w, beam, compound);
  f3d_body_set_material(w, beam, &wood);
  f3d_body_set_temperature(w, beam, 650);

  const F3dBody pa = f3d_body_create(w, F3D_BODY_DYNAMIC, -8, 2, -3, 1);
  const F3dBody pb = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(-7.5), 2, -3, 1);
  f3d_body_set_shape(w, pa, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.1), F3D_R(0.1));
  f3d_body_set_shape(w, pb, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.1), F3D_R(0.1));
  CHECK(f3d_joint_create(w, F3D_JOINT_REVOLUTE, pa, pb, F3D_R(-7.75), 2, -3, 0, 0, 1) != 0);
  CHECK(f3d_joint_create_distance(w, pa, floor, -8, 2, -3, -8, 3, -3) != 0);

  const F3dBody chassis = f3d_body_create(w, F3D_BODY_DYNAMIC, -12, 1, 6, 1200);
  f3d_body_set_shape(w, chassis, F3D_SHAPE_BOX, F3D_R(0.9), F3D_R(0.3), F3D_R(2.0));
  const F3dVehicle car = f3d_vehicle_create(w, chassis, 0, 1, 0, 0, 0, 1);
  CHECK(car != 0);
  for (int i = 0; i < 4; i++) {
    const f3d_real wheel[F3D_WHEEL_FLOATS] = {
        i % 2 ? F3D_R(0.8) : F3D_R(-0.8), F3D_R(-0.2), i < 2 ? F3D_R(1.3) : F3D_R(-1.3),
        F3D_R(0.4), F3D_R(0.35), F3D_R(40000.0), F3D_R(3000.0), 1};
    CHECK(f3d_vehicle_add_wheel(w, car, wheel) == i);
  }
  f3d_vehicle_set_wheel(w, car, 0, F3D_R(0.2), 800, 0);

  const F3dBody top = f3d_body_create(w, F3D_BODY_FIXED, -14, 5, -6, 0);
  const F3dMultibody chain = f3d_multibody_create(w, top);
  CHECK(chain != 0);
  for (int k = 1; k <= 3; k++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC,
                                      F3D_R(-14.0) + (f3d_real)k * F3D_R(0.4), 5, -6, 1);
    f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
    CHECK(f3d_multibody_add_link(w, chain, (uint32_t)(k - 1), b,
                                 k % 2 ? F3D_JOINT_REVOLUTE : F3D_JOINT_SPHERICAL,
                                 F3D_R(-14.0) + (f3d_real)(k - 1) * F3D_R(0.4), 5,
                                 -6, 0, 0, 1) == k);
  }

  falls(w, 10, 48);
  const F3dBody cork = f3d_body_create(w, F3D_BODY_DYNAMIC, 19, 2, 3, F3D_R(0.5));
  f3d_body_set_shape(w, cork, F3D_SHAPE_SPHERE, F3D_R(0.08), 0, 0);

  for (int i = 0; i < 600; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    if (i > 120 && w->s.spray_count > 0 && w->s.bubble_count > 0) break;
  }
  return w;
}

static uint8_t *snapshot_of(const F3dWorld *w, uint32_t *size) {
  *size = f3d_world_snapshot_size(w);
  uint8_t *buffer = (uint8_t *)malloc(*size);
  CHECK(f3d_world_snapshot_write(w, buffer, *size) == *size);
  return buffer;
}

static void run(F3dWorld *w, int steps) {
  for (int i = 0; i < steps; i++) f3d_world_step(w, F3D_R(1.0 / 60.0));
}

/* Whether two worlds step on to the same snapshot, and say the same. */
static int step_alike(F3dWorld *a, F3dWorld *b, int steps) {
  run(a, steps);
  run(b, steps);
  uint32_t sa, sb;
  uint8_t *after_a = snapshot_of(a, &sa);
  uint8_t *after_b = snapshot_of(b, &sb);
  const int same = sa == sb && memcmp(after_a, after_b, sa) == 0;
  free(after_a);
  free(after_b);
  return same;
}

static int same_bytes(const void *a, const void *b, size_t bytes) {
  if (bytes == 0) return 1;
  if (a == NULL || b == NULL) return 0;
  return memcmp(a, b, bytes) == 0;
}

/* Whether [b] holds everything [a] does, byte for byte: the world's own
 * state, every arena slot, every table — what makes a field left out of the
 * format show, even one the next steps would not reach. */
static int same_world(const F3dWorld *a, const F3dWorld *b) {
  F3dWorldState sa, sb;
  memcpy(&sa, &a->s, sizeof sa);
  memcpy(&sb, &b->s, sizeof sb);
  sa.events_head = sb.events_head = 0;
  int same = memcmp(&sa, &sb, sizeof sa) == 0;
  const F3dWorldState *s = &a->s;
  same &= same_bytes(a->slots, b->slots, (size_t)s->used * sizeof(F3dSlot));
  same &= same_bytes(a->grid, b->grid, (size_t)s->grid_n[0] * s->grid_n[1] *
                                           s->grid_n[2] * 3 * sizeof(f3d_real));
  for (uint32_t i = 0; i < s->events_count; i++) {
    same &= same_bytes(&a->events[(s->events_head + i) % F3D_EVENT_CAPACITY],
                       &b->events[(b->s.events_head + i) % F3D_EVENT_CAPACITY],
                       sizeof(F3dEventRecord));
  }
  same &= same_bytes(a->manifolds, b->manifolds, (size_t)s->manifold_count * sizeof(F3dManifold));
  same &= same_bytes(a->hulls, b->hulls, (size_t)s->hull_count * sizeof(F3dHull));
  same &= same_bytes(a->hull_vertices, b->hull_vertices,
                     (size_t)s->hull_vertex_count * 3 * sizeof(f3d_real));
  same &= same_bytes(a->hull_triangles, b->hull_triangles,
                     (size_t)s->hull_triangle_count * 3 * sizeof(uint32_t));
  same &= same_bytes(a->meshes, b->meshes, (size_t)s->mesh_count * sizeof(F3dMesh));
  same &= same_bytes(a->mesh_vertices, b->mesh_vertices,
                     (size_t)s->mesh_vertex_count * 3 * sizeof(f3d_real));
  same &= same_bytes(a->mesh_triangles, b->mesh_triangles,
                     (size_t)s->mesh_triangle_count * 3 * sizeof(uint32_t));
  same &= same_bytes(a->mesh_edges, b->mesh_edges, s->mesh_triangle_count);
  same &= same_bytes(a->joints, b->joints, (size_t)s->joint_used * sizeof(F3dJointSlot));
  same &= same_bytes(a->compounds, b->compounds, (size_t)s->compound_count * sizeof(F3dCompound));
  same &= same_bytes(a->compound_parts, b->compound_parts,
                     (size_t)s->compound_part_count * sizeof(F3dCompoundPart));
  same &= same_bytes(a->vehicles, b->vehicles, (size_t)s->vehicle_count * sizeof(F3dVehicleSlot));
  same &= same_bytes(a->multibodies, b->multibodies,
                     (size_t)s->multibody_count * sizeof(F3dMultibodySlot));
  same &= same_bytes(a->lumps, b->lumps, (size_t)s->lump_count * sizeof(F3dLump));
  same &= same_bytes(a->shallows, b->shallows, (size_t)s->shallow_count * sizeof(F3dShallowSlot));
  same &= same_bytes(a->shallow_data, b->shallow_data, (size_t)s->shallow_reals * sizeof(f3d_real));
  same &= same_bytes(a->spray, b->spray, (size_t)s->spray_count * sizeof(F3dSpray));
  same &= same_bytes(a->bubbles, b->bubbles, (size_t)s->bubble_count * sizeof(F3dBubbles));
  return same;
}

/* ------------------------------------------------- the format, by hand */

static uint32_t u32_at(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static void set_u32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
  p[2] = (uint8_t)(v >> 16);
  p[3] = (uint8_t)(v >> 24);
}

#define ID(a, b, c, d) \
  ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24))

typedef struct Piece {
  uint32_t id, version, length;
  const uint8_t *data;
} Piece;

/* The sections of [snap], at most [most], into [out]; how many. */
static uint32_t pieces_of(const uint8_t *snap, uint32_t size, Piece *out, uint32_t most) {
  const uint32_t count = u32_at(snap + 16);
  const uint8_t *at = snap + 20;
  uint32_t n = 0;
  for (uint32_t i = 0; i < count && n < most && at + 12 <= snap + size; i++) {
    out[n].id = u32_at(at);
    out[n].version = u32_at(at + 4);
    out[n].length = u32_at(at + 8);
    out[n].data = at + 12;
    at += 12 + out[n].length;
    n++;
  }
  return n;
}

/* A snapshot of [snap]'s header and [pieces]. */
static uint8_t *blob_of(const uint8_t *snap, const Piece *pieces, uint32_t n, uint32_t *size) {
  uint32_t total = 20;
  for (uint32_t i = 0; i < n; i++) total += 12 + pieces[i].length;
  uint8_t *blob = (uint8_t *)malloc(total);
  memcpy(blob, snap, 20);
  set_u32(blob + 16, n);
  uint8_t *at = blob + 20;
  for (uint32_t i = 0; i < n; i++) {
    set_u32(at, pieces[i].id);
    set_u32(at + 4, pieces[i].version);
    set_u32(at + 8, pieces[i].length);
    if (pieces[i].length > 0) memcpy(at + 12, pieces[i].data, pieces[i].length);
    at += 12 + pieces[i].length;
  }
  *size = total;
  return blob;
}

static int find(const Piece *pieces, uint32_t n, uint32_t id) {
  for (uint32_t i = 0; i < n; i++) {
    if (pieces[i].id == id) return (int)i;
  }
  return -1;
}

/* ---------------------------------------------------------------- tests */

static void test_header(void) {
  /* Little-endian and explicit: "F3DS", format 1.0, this build's ABI and
   * real, and the sections every 1.0.0 snapshot has. */
  F3dWorld *w = f3d_world_create();
  uint32_t size;
  uint8_t *snap = snapshot_of(w, &size);
  CHECK(snap[0] == 'F' && snap[1] == '3' && snap[2] == 'D' && snap[3] == 'S');
  CHECK(u32_at(snap + 4) == 0x00010000u);
  CHECK(u32_at(snap + 8) == F3D_ABI_VERSION);
  CHECK(u32_at(snap + 12) == sizeof(f3d_real));
  Piece pieces[32];
  const uint32_t n = pieces_of(snap, size, pieces, 32);
  CHECK(n == u32_at(snap + 16) && n == 17);
  const uint32_t ids[17] = {
      ID('W', 'R', 'L', 'D'), ID('B', 'O', 'D', 'Y'), ID('H', 'E', 'A', 'T'),
      ID('F', 'I', 'R', 'E'), ID('L', 'U', 'M', 'P'), ID('W', 'I', 'N', 'D'),
      ID('E', 'V', 'N', 'T'), ID('C', 'O', 'N', 'T'), ID('H', 'U', 'L', 'L'),
      ID('M', 'E', 'S', 'H'), ID('J', 'O', 'I', 'N'), ID('C', 'O', 'M', 'P'),
      ID('V', 'E', 'H', 'I'), ID('M', 'B', 'O', 'D'), ID('W', 'A', 'T', 'R'),
      ID('S', 'P', 'R', 'Y'), ID('B', 'U', 'B', 'L')};
  for (uint32_t i = 0; i < 17 && i < n; i++) CHECK(pieces[i].id == ids[i]);
  CHECK(pieces[0].version == 2);
  free(snap);
  f3d_world_destroy(w);
}

static void test_round_trip(void) {
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  /* The same world is the same bytes. */
  uint32_t again_size;
  uint8_t *again = snapshot_of(a, &again_size);
  CHECK(again_size == size && memcmp(snap, again, size) == 0);
  free(again);

  /* Restored into a world that held something else entirely, and both
   * stepped on: the same bits, all the way down. */
  F3dWorld *b = f3d_world_create();
  for (int i = 0; i < 100; i++) f3d_body_create(b, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_world_restore(b, snap, size) == 1);
  CHECK(same_world(a, b));
  CHECK(f3d_world_body_count(b) == f3d_world_body_count(a));
  for (int i = 0; i < 6; i++) CHECK(f3d_body_is_valid(b, keep[i]));
  CHECK(step_alike(a, b, 600));
  /* Including what they said happened. */
  F3dBody ba[64], bb[64];
  uint32_t ka[64], kb[64];
  const uint32_t na = f3d_world_read_events(a, ba, NULL, ka, 64);
  const uint32_t nb = f3d_world_read_events(b, bb, NULL, kb, 64);
  CHECK(na == nb && na > 0);
  CHECK(memcmp(ba, bb, na * sizeof(F3dBody)) == 0);
  CHECK(memcmp(ka, kb, na * sizeof(uint32_t)) == 0);

  /* A body made after the snapshot is gone once it is restored, and its
   * handle with it. */
  const F3dBody late = f3d_body_create(a, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_world_restore(a, snap, size) == 1);
  CHECK(!f3d_body_is_valid(a, late));
  /* And a world can go back to its own past and grow from there. */
  for (int i = 0; i < 200; i++) f3d_body_create(a, F3D_BODY_DYNAMIC, 0, 0, 0, 1);
  CHECK(f3d_world_body_count(a) == 206);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

static void test_every_subsystem(void) {
  /* Every table the world keeps has something in it, and each comes back
   * field for field, and steps on to the same bits. */
  F3dWorld *a = full_world();
  CHECK(a->s.hull_count > 0 && a->s.mesh_count > 0 && a->s.compound_count > 0);
  CHECK(a->s.joint_live == 2 && a->s.vehicle_count == 1 && a->s.multibody_count == 1);
  CHECK(a->s.lump_count > 0 && a->s.shallow_count == 1);
  CHECK(a->s.spray_count > 0 && a->s.bubble_count > 0);
  CHECK(a->s.manifold_count > 0 && a->s.events_count > 0);
  CHECK(a->s.water_rest_set == 1);
  int burning = 0;
  for (uint32_t i = 0; i < a->s.used; i++) burning |= a->slots[i].flags & F3D_FLAG_BURNING;
  CHECK(burning);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  F3dWorld *b = f3d_world_create();
  CHECK(f3d_world_restore(b, snap, size) == 1);
  CHECK(same_world(a, b));
  /* Its snapshot is the snapshot it came from. */
  uint32_t size_b;
  uint8_t *snap_b = snapshot_of(b, &size_b);
  CHECK(size_b == size && memcmp(snap, snap_b, size) == 0);
  free(snap_b);
  CHECK(step_alike(a, b, 120));
  CHECK(same_world(a, b));
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

static void test_unknown_sections(void) {
  /* A later minor's sections, before, between and after the ones this
   * build knows, are passed over: the world comes back as it was. */
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  Piece pieces[40];
  const uint32_t n = pieces_of(snap, size, pieces, 32);
  Piece more[40];
  const uint8_t junk[13] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13};
  uint32_t m = 0;
  more[m++] = (Piece){ID('N', 'E', 'W', '1'), 1, sizeof junk, junk};
  for (uint32_t i = 0; i < n; i++) {
    more[m++] = pieces[i];
    if (i == 4) more[m++] = (Piece){ID('N', 'E', 'W', '2'), 9, 0, junk};
  }
  more[m++] = (Piece){ID('N', 'E', 'W', '3'), 3, 5, junk};
  uint32_t blob_size;
  uint8_t *blob = blob_of(snap, more, m, &blob_size);
  set_u32(blob + 4, 0x00010007u); /* Format 1.7. */
  F3dWorld *b = f3d_world_create();
  CHECK(f3d_world_restore(b, blob, blob_size) == 1);
  CHECK(same_world(a, b));
  CHECK(step_alike(a, b, 120));
  free(blob);

  /* A later version of a known section, with fields this build does not
   * know at its end: they are passed over. */
  uint8_t *longer = (uint8_t *)malloc(pieces[0].length + 8);
  memcpy(longer, pieces[0].data, pieces[0].length);
  memset(longer + pieces[0].length, 0xab, 8);
  Piece later[32];
  memcpy(later, pieces, n * sizeof(Piece));
  later[0] = (Piece){ID('W', 'R', 'L', 'D'), 3, pieces[0].length + 8, longer};
  blob = blob_of(snap, later, n, &blob_size);
  F3dWorld *c = f3d_world_create();
  CHECK(f3d_world_restore(c, snap, size) == 1);
  F3dWorld *d = f3d_world_create();
  CHECK(f3d_world_restore(d, blob, blob_size) == 1);
  CHECK(same_world(c, d));
  free(blob);
  free(longer);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
  f3d_world_destroy(c);
  f3d_world_destroy(d);
}

static void test_migration(void) {
  /* Version 1 of the world's section, written by hand: the same fields
   * without the water's rest at its end. Read, the rest is the default, as
   * a world that never set it — and such a world steps on to the bits of
   * the one it was taken from. */
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  CHECK(a->s.water_rest_set == 0);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  Piece pieces[32];
  const uint32_t n = pieces_of(snap, size, pieces, 32);
  const int world = find(pieces, n, ID('W', 'R', 'L', 'D'));
  CHECK(world == 0 && pieces[world].version == 2);
  const uint32_t rest_bytes = 2 * (uint32_t)sizeof(f3d_real) + 4;
  Piece old[32];
  memcpy(old, pieces, n * sizeof(Piece));
  old[world].version = 1;
  old[world].length = pieces[world].length - rest_bytes;
  uint32_t blob_size;
  uint8_t *blob = blob_of(snap, old, n, &blob_size);
  F3dWorld *b = f3d_world_create();
  CHECK(f3d_world_restore(b, blob, blob_size) == 1);
  CHECK(same_world(a, b));
  CHECK(step_alike(a, b, 300));

  /* A world that did set its rest, read through version 1, has it as the
   * defaults again: version 1 had none to keep. */
  F3dWorld *c = f3d_world_create();
  f3d_world_set_water_rest(c, F3D_R(0.25), F3D_R(4.0));
  uint32_t c_size;
  uint8_t *c_snap = snapshot_of(c, &c_size);
  const uint32_t cn = pieces_of(c_snap, c_size, pieces, 32);
  pieces[0].version = 1;
  pieces[0].length -= rest_bytes;
  uint8_t *c_blob = blob_of(c_snap, pieces, cn, &blob_size);
  F3dWorld *d = f3d_world_create();
  CHECK(f3d_world_restore(d, c_blob, blob_size) == 1);
  CHECK(d->s.water_rest_set == 0 && d->s.water_rest_energy == 0 &&
        d->s.water_rest_time == 0);
  free(c_blob);
  free(c_snap);
  free(blob);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
  f3d_world_destroy(c);
  f3d_world_destroy(d);
}

/* Whether [world] refuses [blob] and keeps the one body it had. */
static int refused(F3dWorld *world, F3dBody mine, const uint8_t *blob, uint32_t size) {
  if (f3d_world_restore(world, blob, size) != 0) return 0;
  f3d_real p[3];
  return f3d_world_body_count(world) == 1 &&
         f3d_body_get_position(world, mine, p) == 1 && p[0] == 7;
}

static void test_refusals(void) {
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  /* Too small a buffer to write into. */
  CHECK(f3d_world_snapshot_write(a, snap, size - 1) == 0);
  CHECK(f3d_world_snapshot_write(a, NULL, size) == 0);

  F3dWorld *b = f3d_world_create();
  const F3dBody mine = f3d_body_create(b, F3D_BODY_DYNAMIC, 7, 7, 7, 1);
  CHECK(refused(b, mine, NULL, size));
  CHECK(refused(b, mine, snap, 3));
  CHECK(refused(b, mine, snap, 19));
  CHECK(refused(b, mine, snap, size - 1));
  uint8_t *bad = (uint8_t *)malloc(size + 4);
  /* Not a snapshot. */
  memcpy(bad, snap, size);
  bad[0] ^= 1;
  CHECK(refused(b, mine, bad, size));
  /* One from before 1.0.0: its version where the format is, 25, reads as
   * major nought, minor 25 — not migrated. */
  memcpy(bad, snap, size);
  set_u32(bad + 4, 25);
  CHECK(refused(b, mine, bad, size));
  /* A later major. */
  set_u32(bad + 4, 0x00020000u);
  CHECK(refused(b, mine, bad, size));
  /* A real neither four bytes nor eight. */
  memcpy(bad, snap, size);
  set_u32(bad + 12, 3);
  CHECK(refused(b, mine, bad, size));
  /* More sections claimed than there are, or fewer, or bytes after. */
  memcpy(bad, snap, size);
  set_u32(bad + 16, u32_at(snap + 16) + 1);
  CHECK(refused(b, mine, bad, size));
  set_u32(bad + 16, u32_at(snap + 16) - 1);
  CHECK(refused(b, mine, bad, size));
  memcpy(bad, snap, size);
  memset(bad + size, 0, 4);
  CHECK(refused(b, mine, bad, size + 4));
  /* A section longer than what is left. */
  memcpy(bad, snap, size);
  set_u32(bad + 28, size);
  CHECK(refused(b, mine, bad, size));
  /* A section of version nought. */
  memcpy(bad, snap, size);
  set_u32(bad + 24, 0);
  CHECK(refused(b, mine, bad, size));

  Piece pieces[32];
  const uint32_t n = pieces_of(snap, size, pieces, 32);
  uint32_t blob_size;
  uint8_t *blob;
  /* A section every 1.0 snapshot has, left out — the heat, say. */
  Piece fewer[32];
  uint32_t m = 0;
  for (uint32_t i = 0; i < n; i++) {
    if (pieces[i].id != ID('H', 'E', 'A', 'T')) fewer[m++] = pieces[i];
  }
  blob = blob_of(snap, fewer, m, &blob_size);
  CHECK(refused(b, mine, blob, blob_size));
  free(blob);
  /* A section twice. */
  Piece twice[33];
  memcpy(twice, pieces, n * sizeof(Piece));
  twice[n] = pieces[2];
  blob = blob_of(snap, twice, n + 1, &blob_size);
  CHECK(refused(b, mine, blob, blob_size));
  free(blob);
  /* The bodies' list not as long as the arena says. */
  const int body = find(pieces, n, ID('B', 'O', 'D', 'Y'));
  uint8_t *bodies = (uint8_t *)malloc(pieces[body].length);
  memcpy(bodies, pieces[body].data, pieces[body].length);
  set_u32(bodies, u32_at(bodies) + 1); /* used */
  Piece wrong[32];
  memcpy(wrong, pieces, n * sizeof(Piece));
  wrong[body].data = bodies;
  blob = blob_of(snap, wrong, n, &blob_size);
  CHECK(refused(b, mine, blob, blob_size));
  free(blob);
  /* A list claiming more records than its section holds. */
  memcpy(bodies, pieces[body].data, pieces[body].length);
  set_u32(bodies + 16, u32_at(bodies + 16) + 1000); /* the record's bytes */
  blob = blob_of(snap, wrong, n, &blob_size);
  CHECK(refused(b, mine, blob, blob_size));
  free(blob);
  /* An arena whose free list runs past it. */
  memcpy(bodies, pieces[body].data, pieces[body].length);
  set_u32(bodies + 8, u32_at(bodies) + 1); /* free_head */
  blob = blob_of(snap, wrong, n, &blob_size);
  CHECK(refused(b, mine, blob, blob_size));
  free(blob);
  free(bodies);
  free(bad);

  /* An empty world round-trips too. */
  F3dWorld *empty = f3d_world_create();
  uint32_t empty_size;
  uint8_t *nothing = snapshot_of(empty, &empty_size);
  CHECK(f3d_world_restore(b, nothing, empty_size) == 1);
  CHECK(f3d_world_body_count(b) == 0);
  CHECK(f3d_body_create(b, F3D_BODY_DYNAMIC, 0, 0, 0, 1) != 0);
  free(nothing);
  f3d_world_destroy(empty);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

int main(void) {
  test_header();
  test_round_trip();
  test_every_subsystem();
  test_unknown_sections();
  test_migration();
  test_refusals();
  return finish();
}
