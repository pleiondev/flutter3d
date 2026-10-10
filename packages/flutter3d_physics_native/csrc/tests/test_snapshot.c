/*
 * Snapshots, tested in C — P9: a world restored from one steps to the same
 * bits as the world it was taken from, the same world is the same bytes,
 * and every subsystem the world holds comes back field for field. The
 * format is read across versions: a section it does not know is skipped,
 * a later version's extra fields are passed over, an earlier version of a
 * section is migrated, and what it cannot read — a snapshot from before
 * 1.0.0, a later major, damage — is refused with the world left as it was.
 * Damage inside the sections too: an index past what it indexes, a count
 * the bytes behind it cannot hold, and snapshots damaged at random, byte by
 * byte and field by field, under the sanitisers.
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"

/* Under the address sanitiser, an allocation of more than 256 MB stops the
 * test: a snapshot of a few hundred kilobytes that asks for gigabytes was
 * believed before it was checked. */
const char *__asan_default_options(void);
const char *__asan_default_options(void) { return "max_allocation_size_mb=256"; }

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

/* -------------------------------------------- damage the lists hold in */

/* The handle of slot [slot], generation one. */
static F3dBody handle_at(uint32_t slot) { return ((uint64_t)1u << 32) | slot; }

static int first_live_shaped(const F3dWorld *w, uint8_t shape) {
  for (uint32_t i = 0; i < w->s.used; i++) {
    if (w->slots[i].live && w->slots[i].shape == shape) return (int)i;
  }
  return -1;
}

static int first_hull_part(const F3dWorld *w) {
  for (uint32_t i = 0; i < w->s.compound_part_count; i++) {
    if (w->compound_parts[i].kind == F3D_SHAPE_HULL) return (int)i;
  }
  return -1;
}

/* Each a number the format reads well enough, put where it names
 * something past what the snapshot holds: refused, every one, before the
 * first step can read past an array. */
enum {
  PART_HULL_NOUGHT,
  PART_HULL_PAST,
  PART_KIND_NESTED,
  MESH_INDEX_PAST,
  HULL_INDEX_PAST,
  WATER_FIRST_PAST,
  WATER_EMPTY,
  WATER_TOO_WIDE,
  MANIFOLD_A_PAST,
  MANIFOLD_B_PAST,
  VEHICLE_CHASSIS_PAST,
  BODY_SHAPE_UNKNOWN,
  BODY_HULL_PAST,
  BODY_MESH_PAST,
  BODY_COMPOUND_PAST,
  BODY_LUMPS_PAST,
  BODY_LUMPS_NOT_COMPOUND,
  JOINT_BODY_PAST,
  LINK_PARENT_AHEAD,
  LINK_DOFS_PAST,
  MULTIBODY_DOFS_PAST,
  LINK_BODY_PAST,
  WIND_HALF_A_GRID,
  LIVE_MISCOUNTED,
  FREE_HEAD_LIVE,
  FREE_LIST_THROUGH_LIVE,
  JOINT_FREE_HEAD_LIVE,
  JOINT_FREE_LIST_THROUGH_LIVE,
  JOINTS_MISCOUNTED,
  LINKS_MISCOUNTED,
  ROOT_FREEDOMS_SHORT,
  BODY_LIQUID_PAST,
  BODY_LUMPS_TOO_MANY,
  DAMAGE_KINDS
};

/* [w] damaged as [kind] says, in place: what a snapshot of it then says. */
static void damage(F3dWorld *w, int kind) {
  const int part = first_hull_part(w);
  const F3dMesh *mesh = &w->meshes[0];
  const F3dHull *hull = &w->hulls[0];
  switch (kind) {
    case PART_HULL_NOUGHT:
      /* What f3d_compound.c reads as hulls[-1]. */
      w->compound_parts[part].hull = 0;
      break;
    case PART_HULL_PAST:
      w->compound_parts[part].hull = w->s.hull_count + 1u;
      break;
    case PART_KIND_NESTED:
      w->compound_parts[part].kind = F3D_SHAPE_COMPOUND;
      break;
    case MESH_INDEX_PAST:
      w->mesh_triangles[(size_t)mesh->first_triangle * 3u + 1u] = mesh->vertex_count;
      break;
    case HULL_INDEX_PAST:
      w->hull_triangles[(size_t)hull->first_triangle * 3u + 2u] = hull->vertex_count;
      break;
    case WATER_FIRST_PAST:
      /* Inside the reals, as the old check had it, but its grid is not. */
      w->shallows[0].first = 1;
      break;
    case WATER_EMPTY:
      w->shallows[0].nz = 0;
      break;
    case WATER_TOO_WIDE:
      w->shallows[0].nx = 0x10000u;
      w->shallows[0].nz = 0x10000u;
      break;
    case MANIFOLD_A_PAST:
      w->manifolds[0].a = handle_at(w->s.used);
      break;
    case MANIFOLD_B_PAST:
      w->manifolds[0].b = handle_at(w->s.used + 40u);
      break;
    case VEHICLE_CHASSIS_PAST:
      w->vehicles[0].chassis = handle_at(w->s.used + 3u);
      break;
    case BODY_SHAPE_UNKNOWN:
      w->slots[first_live_shaped(w, F3D_SHAPE_BOX)].shape = 200;
      break;
    case BODY_HULL_PAST:
      w->slots[first_live_shaped(w, F3D_SHAPE_HULL)].hull = w->s.hull_count + 1u;
      break;
    case BODY_MESH_PAST:
      w->slots[first_live_shaped(w, F3D_SHAPE_MESH)].hull = 0;
      break;
    case BODY_COMPOUND_PAST:
      w->slots[first_live_shaped(w, F3D_SHAPE_COMPOUND)].hull =
          w->s.compound_count + 1u;
      break;
    case BODY_LUMPS_PAST:
      w->slots[first_live_shaped(w, F3D_SHAPE_COMPOUND)].lumps = w->s.lump_count;
      break;
    case BODY_LUMPS_NOT_COMPOUND: {
      F3dSlot *s = &w->slots[first_live_shaped(w, F3D_SHAPE_BOX)];
      s->lumps = 1;
      s->lump_count = 1;
      break;
    }
    case JOINT_BODY_PAST:
      for (uint32_t i = 0; i < w->s.joint_used; i++) {
        if (w->joints[i].live) {
          w->joints[i].b = handle_at(w->s.used + 7u);
          break;
        }
      }
      break;
    case LINK_PARENT_AHEAD:
      w->multibodies[0].links[1].parent = 2;
      break;
    case LINK_DOFS_PAST:
      w->multibodies[0].links[2].first_dof = w->multibodies[0].dof_count;
      break;
    case MULTIBODY_DOFS_PAST:
      w->multibodies[0].dof_count = F3D_MULTIBODY_MOST_DOFS + 1u;
      break;
    case LINK_BODY_PAST:
      w->multibodies[0].links[3].body = handle_at(w->s.used);
      break;
    case WIND_HALF_A_GRID:
      /* A grid of no samples, two of its counts saying otherwise. */
      f3d_free(w->grid);
      w->grid = NULL;
      w->s.grid_n[0] = 0;
      break;
    case LIVE_MISCOUNTED:
      /* One fewer than there are: a buffer sized by the count, one short of
       * what is written into it. */
      w->s.live--;
      break;
    case FREE_HEAD_LIVE:
      w->s.free_head = (uint32_t)first_live_shaped(w, F3D_SHAPE_BOX) + 1u;
      break;
    case FREE_LIST_THROUGH_LIVE: {
      /* A slot freed, its next free one a body still there. */
      F3dSlot *freed = &w->slots[first_live_shaped(w, F3D_SHAPE_BOX)];
      freed->live = 0;
      w->s.live--;
      freed->next_free = (uint32_t)first_live_shaped(w, F3D_SHAPE_SPHERE) + 1u;
      break;
    }
    case JOINT_FREE_HEAD_LIVE:
    case JOINT_FREE_LIST_THROUGH_LIVE: {
      uint32_t live[2], n = 0;
      for (uint32_t i = 0; i < w->s.joint_used && n < 2; i++) {
        if (w->joints[i].live) live[n++] = i;
      }
      if (kind == JOINT_FREE_HEAD_LIVE) {
        w->s.joint_free_head = live[0] + 1u;
      } else {
        w->joints[live[0]].live = 0;
        w->s.joint_live--;
        w->joints[live[0]].next_free = live[1] + 1u;
      }
      break;
    }
    case JOINTS_MISCOUNTED:
      w->s.joint_live--;
      break;
    case LINKS_MISCOUNTED:
      /* What f3d_joint.c's filter makes room for, one short of the keys
       * it writes. */
      w->s.multibody_links--;
      break;
    case ROOT_FREEDOMS_SHORT:
      w->multibodies[0].floating = 1;
      w->multibodies[0].dof_count = 5;
      w->multibodies[0].links[1].first_dof = 0;
      w->multibodies[0].links[2].first_dof = 1;
      w->multibodies[0].links[3].first_dof = 4;
      break;
    case BODY_LIQUID_PAST:
      w->slots[first_live_shaped(w, F3D_SHAPE_BOX)].liquid = w->s.shallow_count + 1u;
      break;
    case BODY_LUMPS_TOO_MANY: {
      /* Its lumps where the world keeps them, but more than its parts:
       * f3d_world_read_fires reads a part a lump. */
      const F3dSlot *s = &w->slots[first_live_shaped(w, F3D_SHAPE_COMPOUND)];
      w->compounds[s->hull - 1u].part_count = s->lump_count - 1u;
      break;
    }
    default:
      break;
  }
}

static void test_damage_inside(void) {
  /* Mutation: drop any one of the checks consistent() makes in
   * f3d_snapshot.c — its case is taken, and the world it was restored over
   * replaced. Each check was dropped in turn and each failed here. */
  F3dWorld *full = full_world();
  CHECK(first_hull_part(full) >= 0);
  CHECK(full->s.multibody_count == 1 && full->multibodies[0].link_count == 4);
  uint32_t size;
  uint8_t *pristine = snapshot_of(full, &size);
  F3dBody keep[6];
  F3dWorld *target = busy_world(keep);
  F3dWorld *twin = f3d_world_create();
  uint32_t busy_size;
  uint8_t *busy = snapshot_of(target, &busy_size);
  CHECK(f3d_world_restore(twin, busy, busy_size) == 1);
  for (int kind = 0; kind < DAMAGE_KINDS; kind++) {
    F3dWorld *w = f3d_world_create();
    CHECK(f3d_world_restore(w, pristine, size) == 1);
    damage(w, kind);
    uint32_t bad_size;
    uint8_t *bad = snapshot_of(w, &bad_size);
    const int taken = f3d_world_restore(target, bad, bad_size);
    if (taken) {
      fprintf(stderr, "damage %d was taken\n", kind);
      CHECK(f3d_world_restore(target, busy, busy_size) == 1);
    }
    CHECK(!taken);
    CHECK(same_world(target, twin));
    free(bad);
    f3d_world_destroy(w);
  }
  free(busy);
  free(pristine);
  f3d_world_destroy(full);
  f3d_world_destroy(target);
  f3d_world_destroy(twin);
}

/* -------------------------------------------- damage that asks for more */

/* [snap] with the u32 at [offset] into section [id] set to [value]. */
static uint8_t *with_u32(const uint8_t *snap, uint32_t size, uint32_t id,
                         uint32_t offset, uint32_t value) {
  uint8_t *bad = (uint8_t *)malloc(size);
  memcpy(bad, snap, size);
  Piece pieces[32];
  const uint32_t n = pieces_of(snap, size, pieces, 32);
  const int at = find(pieces, n, id);
  CHECK(at >= 0 && offset + 4u <= pieces[at].length);
  set_u32(bad + (pieces[at].data - snap) + offset, value);
  return bad;
}

static void test_counts_before_memory(void) {
  /* A count no bigger than the format allows, in a section far too short
   * to hold what it counts: refused before the memory is asked for. The
   * sanitiser's 256 MB stops the test where the count is believed.
   * Mutation: drop make()'s check of the count against the bytes left —
   * the first case asks for gigabytes and the sanitiser stops the test;
   * drop sec_wind's bound on two counts' product — the wrapped grid is
   * taken. */
  F3dBody keep[6];
  F3dWorld *a = busy_world(keep);
  uint32_t size;
  uint8_t *snap = snapshot_of(a, &size);
  F3dWorld *b = f3d_world_create();
  const F3dBody mine = f3d_body_create(b, F3D_BODY_DYNAMIC, 7, 7, 7, 1);
  const uint32_t r = (uint32_t)sizeof(f3d_real);
  struct {
    uint32_t id, offset, value;
  } const cases[] = {
      /* Sixteen million bodies: gigabytes of slots. */
      {ID('B', 'O', 'D', 'Y'), 0, 0x01000000u},
      {ID('L', 'U', 'M', 'P'), 0, 0x01000000u},
      {ID('C', 'O', 'N', 'T'), 0, 0x01000000u},
      {ID('J', 'O', 'I', 'N'), 0, 0x01000000u},
      {ID('V', 'E', 'H', 'I'), 0, 0x00400000u},
      {ID('M', 'B', 'O', 'D'), 0, 0x00100000u},
      {ID('W', 'A', 'T', 'R'), 4, 0x10000000u},
      {ID('H', 'U', 'L', 'L'), 4, 0x08000000u},
      {ID('M', 'E', 'S', 'H'), 8, 0x08000000u},
      {ID('C', 'O', 'M', 'P'), 4, 0x04000000u},
      /* A wind grid of 1 × 1 × 2²⁸ samples: under the old 2³² reals, and
       * three gigabytes zeroed. */
      {ID('W', 'I', 'N', 'D'), 4 * r + 8, 0x10000000u},
  };
  for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
    uint8_t *bad = with_u32(snap, size, cases[i].id, cases[i].offset, cases[i].value);
    if (cases[i].id == ID('W', 'I', 'N', 'D')) {
      /* The other two counts one each. */
      Piece pieces[32];
      const uint32_t n = pieces_of(snap, size, pieces, 32);
      uint8_t *wind = bad + (pieces[find(pieces, n, cases[i].id)].data - snap);
      set_u32(wind + 4 * r, 1);
      set_u32(wind + 4 * r + 4, 1);
    }
    CHECK(refused(b, mine, bad, size));
    free(bad);
  }
  /* A grid of 2¹⁷ × 2¹⁶ × 2³¹ samples, whose 3·2⁶⁴ reals wrap to nought in
   * 64 bits, and a block of nought reals after it: no grid, its counts
   * saying otherwise, for the wind to be read from. */
  uint8_t *wrapped = with_u32(snap, size, ID('W', 'I', 'N', 'D'), 4 * r, 0x20000u);
  Piece pieces[32];
  const uint32_t n = pieces_of(snap, size, pieces, 32);
  uint8_t *wind = wrapped + (pieces[find(pieces, n, ID('W', 'I', 'N', 'D'))].data - snap);
  set_u32(wind + 4 * r + 4, 0x10000u);
  set_u32(wind + 4 * r + 8, 0x80000000u);
  set_u32(wind + 4 * r + 12, 0);
  CHECK(refused(b, mine, wrapped, size));
  free(wrapped);
  free(snap);
  f3d_world_destroy(a);
  f3d_world_destroy(b);
}

/* ------------------------------------------------------------- fuzzing */

/* How many damaged snapshots the fuzz tries, and from where; more, or
 * others, with -DFUZZ_ROUNDS=… and -DFUZZ_SEED=… for a longer run by hand. */
#ifndef FUZZ_ROUNDS
#define FUZZ_ROUNDS 1500
#endif
#ifndef FUZZ_SEED
#define FUZZ_SEED 0x9e3779b97f4a7c15u
#endif

static uint64_t g_seed = FUZZ_SEED;

static uint32_t next_random(void) {
  g_seed ^= g_seed << 13;
  g_seed ^= g_seed >> 7;
  g_seed ^= g_seed << 17;
  return (uint32_t)(g_seed >> 16);
}

static void test_fuzz_bytes(void) {
  /* Snapshots of the world with everything in it, damaged at random —
   * bits flipped, words set to the numbers that break counts and indices,
   * bytes cut off — and restored over another world: refused with that
   * world as it was, or taken, and then what was taken is a world whose own
   * snapshot reads back to it. A read past the buffer or an array is the
   * sanitisers' to report.
   *
   * Not stepped: a real damaged into another real — a spray's volume of
   * −2·10³² — reads as well as the one written, and what a step makes of
   * absurd numbers is not the reader's question. The indices a step
   * follows are test_fuzz_indices'. */
  F3dWorld *full = full_world();
  uint32_t size;
  uint8_t *pristine = snapshot_of(full, &size);
  F3dBody keep[6];
  F3dWorld *target = busy_world(keep);
  uint32_t busy_size;
  uint8_t *busy = snapshot_of(target, &busy_size);
  F3dWorld *twin = f3d_world_create();
  CHECK(f3d_world_restore(twin, busy, busy_size) == 1);
  uint8_t *bad = (uint8_t *)malloc(size);
  const uint32_t words[] = {0u, 1u, 2u, 3u, 0x7fffffffu, 0x80000000u, 0xffffffffu,
                            0x10000u, 0xffffu, 4097u};
  int taken = 0, refusals = 0, unchanged = 1;
  for (int round = 0; round < FUZZ_ROUNDS; round++) {
    memcpy(bad, pristine, size);
    uint32_t bad_size = size;
    const uint32_t edits = 1u + next_random() % 4u;
    for (uint32_t e = 0; e < edits; e++) {
      /* Past the header, mostly: damage the header is refused for is
       * test_refusals'. */
      const uint32_t at = 20u + next_random() % (size - 24u);
      switch (next_random() % 4u) {
        case 0:
          bad[at] ^= (uint8_t)(1u << (next_random() % 8u));
          break;
        case 1:
          set_u32(bad + (at & ~3u), words[next_random() % (sizeof words / sizeof words[0])]);
          break;
        case 2:
          set_u32(bad + at, u32_at(bad + at) + (next_random() % 2u ? 1u : 0xffffffffu));
          break;
        default:
          set_u32(bad + at, next_random());
          break;
      }
    }
    if (next_random() % 16u == 0) bad_size = 20u + next_random() % (size - 20u);
    if (f3d_world_restore(target, bad, bad_size)) {
      taken++;
      uint32_t again_size;
      uint8_t *again = snapshot_of(target, &again_size);
      F3dWorld *echo = f3d_world_create();
      CHECK(f3d_world_restore(echo, again, again_size) == 1);
      CHECK(same_world(target, echo));
      f3d_world_destroy(echo);
      free(again);
      CHECK(f3d_world_restore(target, busy, busy_size) == 1);
    } else {
      refusals++;
      unchanged &= same_world(target, twin);
    }
  }
  CHECK(unchanged);
  /* Both ways taken often: a fuzz that only ever refuses tests the
   * header. */
  CHECK(taken > 100 && refusals > 100);
  free(bad);
  free(busy);
  free(pristine);
  f3d_world_destroy(full);
  f3d_world_destroy(target);
  f3d_world_destroy(twin);
}

/* A whole number of a world's tables, of [bytes] bytes, that a snapshot
 * carries and the writer does not itself count by. */
typedef struct Field {
  void *at;
  uint32_t bytes;
} Field;

#define MOST_FIELDS 40000

static uint32_t g_field_count;
static Field g_fields[MOST_FIELDS];

static void field(void *at, uint32_t bytes) {
  if (g_field_count < MOST_FIELDS) g_fields[g_field_count++] = (Field){at, bytes};
}

#define U8(x) field(&(x), 1)
#define U32(x) field(&(x), 4)
#define U64(x) field(&(x), 8)

/* Every whole number in [w]'s tables: indices, handles, kinds, flags and
 * the counts of what a slot holds. Not the world's own counts of its
 * tables, which the writer writes by. */
static void fields_of(F3dWorld *w) {
  g_field_count = 0;
  const F3dWorldState *s = &w->s;
  for (uint32_t i = 0; i < s->used; i++) {
    F3dSlot *b = &w->slots[i];
    U32(b->generation), U32(b->next_free), U8(b->live), U8(b->type), U8(b->shape);
    U8(b->flags), U32(b->hull), U32(b->liquid), U32(b->was_wet), U32(b->layer);
    U32(b->mask), U32(b->lumps), U32(b->lump_count);
  }
  for (uint32_t i = 0; i < s->manifold_count; i++) {
    F3dManifold *m = &w->manifolds[i];
    U64(m->a), U64(m->b), U32(m->count), U32(m->touching), U32(m->part);
    for (uint32_t k = 0; k < F3D_MANIFOLD_POINTS; k++) U32(m->points[k].id);
  }
  for (uint32_t i = 0; i < s->hull_count; i++) {
    F3dHull *h = &w->hulls[i];
    U32(h->first_vertex), U32(h->vertex_count), U32(h->first_triangle);
    U32(h->triangle_count);
  }
  for (uint32_t i = 0; i < s->hull_triangle_count * 3u; i++) U32(w->hull_triangles[i]);
  for (uint32_t i = 0; i < s->mesh_count; i++) {
    F3dMesh *m = &w->meshes[i];
    U32(m->first_vertex), U32(m->vertex_count), U32(m->first_triangle);
    U32(m->triangle_count);
  }
  for (uint32_t i = 0; i < s->mesh_triangle_count * 3u; i++) U32(w->mesh_triangles[i]);
  for (uint32_t i = 0; i < s->mesh_triangle_count; i++) U8(w->mesh_edges[i]);
  for (uint32_t i = 0; i < s->joint_used; i++) {
    F3dJointSlot *j = &w->joints[i];
    U32(j->generation), U32(j->next_free), U8(j->live), U8(j->type), U8(j->flags);
    U64(j->a), U64(j->b);
  }
  for (uint32_t i = 0; i < s->compound_count; i++) {
    U32(w->compounds[i].first_part), U32(w->compounds[i].part_count);
  }
  for (uint32_t i = 0; i < s->compound_part_count; i++) {
    U32(w->compound_parts[i].kind), U32(w->compound_parts[i].hull);
  }
  for (uint32_t i = 0; i < s->vehicle_count; i++) {
    F3dVehicleSlot *v = &w->vehicles[i];
    U32(v->live), U32(v->wheel_count), U64(v->chassis);
    for (uint32_t k = 0; k < F3D_VEHICLE_MOST_WHEELS; k++) U32(v->wheels[k].touching);
  }
  for (uint32_t i = 0; i < s->multibody_count; i++) {
    F3dMultibodySlot *m = &w->multibodies[i];
    U32(m->live), U32(m->link_count), U32(m->dof_count), U32(m->floating);
    for (uint32_t k = 0; k < F3D_MULTIBODY_MOST_LINKS; k++) {
      F3dLink *l = &m->links[k];
      U64(l->body), U32(l->parent), U32(l->type), U32(l->first_dof), U32(l->dofs);
      U32(l->flags);
    }
  }
  for (uint32_t i = 0; i < s->lump_count; i++) {
    U32(w->lumps[i].burning), U32(w->lumps[i].edge);
  }
  for (uint32_t i = 0; i < s->shallow_count; i++) {
    F3dShallowSlot *q = &w->shallows[i];
    U32(q->live), U32(q->nx), U32(q->nz), U32(q->first), U32(q->outlet_count);
    for (int k = 0; k < 4; k++) U32(q->edge_kind[k]);
    for (uint32_t k = 0; k < F3D_SHALLOW_MOST_OUTLETS; k++) U32(q->outlets[k].kind);
    U32(q->substeps), U32(q->overruns), U32(q->boils), U32(q->resting);
    U32(q->source_count);
  }
  for (uint32_t i = 0; i < s->spray_count; i++) {
    U32(w->spray[i].water), U32(w->spray[i].kind), U32(w->spray[i].face);
  }
  for (uint32_t i = 0; i < s->bubble_count; i++) U32(w->bubbles[i].water);
}

/* A number to damage a field of [bytes] holding [was] with: nought, one,
 * one either side of it, the edges of a word, small, or anything. */
static uint64_t damaged(uint64_t was, uint32_t bytes, uint32_t used) {
  uint64_t v;
  switch (next_random() % 8u) {
    case 0: v = 0; break;
    case 1: v = 1; break;
    case 2: v = was + 1u; break;
    case 3: v = was - 1u; break;
    case 4: v = next_random() % 64u; break;
    case 5: v = next_random() % 2u ? 0xffffffffu : 0x80000000u; break;
    case 6:
      /* A handle's slot past the arena, its generation kept. */
      v = (was & 0xffffffff00000000u) | (used + next_random() % 4u);
      break;
    default: v = ((uint64_t)next_random() << 32) | next_random(); break;
  }
  return bytes == 8 ? v : bytes == 4 ? (uint32_t)v : (uint8_t)v;
}

static void test_fuzz_indices(void) {
  /* The world with everything in it, a few of the whole numbers in its
   * tables damaged at random, written and restored over another world:
   * refused with that world as it was, or taken and stepped. Every index a
   * step follows is among them, so a read past an array that the reader
   * let through shows in the steps, to the sanitisers. */
  F3dWorld *full = full_world();
  uint32_t size;
  uint8_t *pristine = snapshot_of(full, &size);
  F3dBody keep[6];
  F3dWorld *target = busy_world(keep);
  uint32_t busy_size;
  uint8_t *busy = snapshot_of(target, &busy_size);
  F3dWorld *twin = f3d_world_create();
  CHECK(f3d_world_restore(twin, busy, busy_size) == 1);
  F3dWorld *w = f3d_world_create();
  int taken = 0, refusals = 0, unchanged = 1;
  for (int round = 0; round < FUZZ_ROUNDS; round++) {
    CHECK(f3d_world_restore(w, pristine, size) == 1);
    fields_of(w);
    const uint32_t edits = 1u + next_random() % 3u;
    for (uint32_t e = 0; e < edits; e++) {
      const Field *f = &g_fields[next_random() % g_field_count];
      uint64_t was = 0;
      memcpy(&was, f->at, f->bytes);
      const uint64_t now = damaged(was, f->bytes, w->s.used);
      memcpy(f->at, &now, f->bytes);
    }
    uint32_t bad_size;
    uint8_t *bad = snapshot_of(w, &bad_size);
    if (f3d_world_restore(target, bad, bad_size)) {
      taken++;
      run(target, 2);
      CHECK(f3d_world_restore(target, busy, busy_size) == 1);
    } else {
      refusals++;
      unchanged &= same_world(target, twin);
    }
    free(bad);
  }
  CHECK(unchanged);
  CHECK(taken > 100 && refusals > 100);
  free(busy);
  free(pristine);
  f3d_world_destroy(w);
  f3d_world_destroy(full);
  f3d_world_destroy(target);
  f3d_world_destroy(twin);
}

int main(void) {
  test_header();
  test_round_trip();
  test_every_subsystem();
  test_unknown_sections();
  test_migration();
  test_refusals();
  test_damage_inside();
  test_counts_before_memory();
  test_fuzz_bytes();
  test_fuzz_indices();
  return finish();
}
