/*
 * The world's whole state in one buffer, and back — P9.
 *
 * Written field by field, little-endian, every number at a width the format
 * names, so that a snapshot means the same to a later build of the core as
 * to the one that wrote it: a save made with 1.0.0 is read by every 1.x.
 *
 * The layout:
 *
 *   header   u32 magic "F3DS"; u16 format minor, u16 format major; u32 the
 *            writer's F3D_ABI_VERSION; u32 bytes a real is written in (4 or
 *            8); u32 the number of sections that follow.
 *   section  u32 id (four letters, "WRLD"…); u32 the section's version;
 *            u32 its length in bytes; then its fields.
 *
 * A section's fields are written one by one: u8, u32, u64, f64, and reals
 * at the header's width. A list of records goes out as u32 count, u32 bytes
 * a record, then the records; a record's own lists the same way, so a
 * material or a wheel can grow without moving what follows it.
 *
 * What a reader does with what it did not write:
 *   - a format major other than its own is refused: nought is everything
 *     before 1.0.0, whose snapshots were the structs' memory and are not
 *     migrated, and a higher one is a later break;
 *   - a section it does not know is skipped, so a later minor's additions
 *     cost an earlier reader nothing;
 *   - a field past the end of its section or record reads as nought, which
 *     is how an earlier version of either reads; where nought is not what
 *     that earlier version meant, the section's reader says what is, by the
 *     section's version (the world's section, version 1, below);
 *   - a field it does not know at the end of a section or a record, a later
 *     version's, is passed over.
 * Within a major a section and a record only grow at their end, and a
 * section every 1.0.0 snapshot has is never left out.
 *
 * Reals are written in the width the build steps in and read in either, so
 * a snapshot from the doubles build restores in the floats one, rounded;
 * restored in the build that wrote it, a world steps to the bits the world
 * it was taken from does. The same world is the same bytes: the events go
 * out oldest first whichever slot of their ring the oldest is in.
 *
 * What a snapshot does not hold is built again from what it does: the
 * broadphase tree, the meshes' trees, the joined pairs, the threads.
 */
#include "f3d_internal.h"

#define F3D_SNAPSHOT_MAGIC 0x53443346u /* "F3DS", little-endian. */
/* The format: the major a reader must share, and the minor that grows as
 * sections are added. */
#define F3D_SNAPSHOT_MAJOR 1u
#define F3D_SNAPSHOT_MINOR 0u

#define F3D_SECTION(a, b, c, d)                                     \
  ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) |   \
   ((uint32_t)(d) << 24))

#if (defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && \
     __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__) ||                  \
    defined(_MSC_VER)
#define F3D_HOST_LITTLE 1
#else
#define F3D_HOST_LITTLE 0
#endif

/* ------------------------------------------------------------ the stream
 *
 * One walk over the fields serves both ways: writing, each io_ call puts
 * the field into the buffer (or only counts its bytes, with no buffer);
 * reading, it takes the field out. So a section's fields are listed once,
 * and what is written is what is read.
 */
typedef struct Io {
  int reading;
  /* Writing: the buffer, null to count only, and the bytes so far. */
  uint8_t *base;
  uint64_t n;
  /* Reading: where, the end of the section or record being read, and the
   * width of the writer's reals. */
  const uint8_t *at;
  const uint8_t *end;
  uint32_t real_bytes;
  /* The version of the section being written or read. */
  uint32_t version;
  /* Set by a reader that found what it cannot take. */
  int bad;
} Io;

static void put_u32_at(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
  p[2] = (uint8_t)(v >> 16);
  p[3] = (uint8_t)(v >> 24);
}

static uint32_t get_u32_at(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static void put_bytes(Io *io, const uint8_t *bytes, uint32_t count) {
  if (io->base != NULL) f3d_copy(io->base + io->n, bytes, count);
  io->n += count;
}

/* [count] bytes of the field, or null past the end: a field an earlier
 * version did not have. */
static const uint8_t *take(Io *io, uint32_t count) {
  if ((size_t)(io->end - io->at) < count) {
    io->at = io->end;
    return NULL;
  }
  const uint8_t *p = io->at;
  io->at += count;
  return p;
}

static void io_u8(Io *io, uint8_t *v) {
  if (!io->reading) {
    put_bytes(io, v, 1);
    return;
  }
  const uint8_t *p = take(io, 1);
  *v = p == NULL ? 0u : p[0];
}

static void io_u32(Io *io, uint32_t *v) {
  if (!io->reading) {
    uint8_t b[4];
    put_u32_at(b, *v);
    put_bytes(io, b, 4);
    return;
  }
  const uint8_t *p = take(io, 4);
  *v = p == NULL ? 0u : get_u32_at(p);
}

static void io_u64(Io *io, uint64_t *v) {
  uint32_t lo = (uint32_t)*v, hi = (uint32_t)(*v >> 32);
  io_u32(io, &lo);
  io_u32(io, &hi);
  if (io->reading) *v = (uint64_t)lo | ((uint64_t)hi << 32);
}

static void io_f64(Io *io, double *v) {
  uint64_t bits;
  f3d_copy(&bits, v, 8);
  io_u64(io, &bits);
  if (io->reading) f3d_copy(v, &bits, 8);
}

static void io_real(Io *io, f3d_real *v) {
  if (!io->reading) {
#ifdef F3D_REAL_DOUBLE
    double d = *v;
    io_f64(io, &d);
#else
    uint32_t bits;
    f3d_copy(&bits, v, 4);
    io_u32(io, &bits);
#endif
    return;
  }
  if (io->real_bytes == 8) {
    double d = 0.0;
    io_f64(io, &d);
    *v = (f3d_real)d;
  } else {
    uint32_t bits = 0;
    float f;
    io_u32(io, &bits);
    f3d_copy(&f, &bits, 4);
    *v = (f3d_real)f;
  }
}

static void io_reals(Io *io, f3d_real *v, uint32_t count) {
  for (uint32_t i = 0; i < count; i++) io_real(io, &v[i]);
}

static void io_vec(Io *io, F3dVec3 *v) {
  io_real(io, &v->x);
  io_real(io, &v->y);
  io_real(io, &v->z);
}

static void io_quat(Io *io, F3dQuat *q) {
  io_real(io, &q->x);
  io_real(io, &q->y);
  io_real(io, &q->z);
  io_real(io, &q->w);
}

static void io_sym(Io *io, F3dSym3 *m) {
  io_real(io, &m->xx);
  io_real(io, &m->yy);
  io_real(io, &m->zz);
  io_real(io, &m->xy);
  io_real(io, &m->xz);
  io_real(io, &m->yz);
}

/* --------------------------------------------------------------- lists
 *
 * u32 count, u32 bytes a record, the records. Writing, the record's bytes
 * are known once they are written and put in after. Reading, each record is
 * read inside its own bytes: a shorter one, an earlier version's, reads its
 * missing fields as nought, and a longer one's extra fields are passed over.
 */
typedef struct List {
  uint32_t count, stride;
  /* Writing: where the stride goes, and where the records start. */
  uint64_t stride_at, start;
  /* Reading: the records, what follows them, and the end round them. */
  const uint8_t *data, *after, *outer_end;
} List;

/* Starts a list of [count] records — reading, of as many as it holds, in
 * [list->count]. */
static void list_begin(Io *io, List *list, uint32_t count) {
  if (!io->reading) {
    list->count = count;
    io_u32(io, &list->count);
    list->stride_at = io->n;
    list->stride = 0;
    io_u32(io, &list->stride);
    list->start = io->n;
    return;
  }
  list->count = 0;
  list->stride = 0;
  io_u32(io, &list->count);
  io_u32(io, &list->stride);
  const uint64_t bytes = (uint64_t)list->count * list->stride;
  /* A record has a byte at least, so a list cannot claim more than the
   * buffer could hold. */
  if ((list->count > 0 && list->stride == 0) ||
      bytes > (uint64_t)(io->end - io->at)) {
    io->bad = 1;
    list->count = 0;
    list->stride = 0;
  }
  list->data = io->at;
  list->outer_end = io->end;
  list->after = io->at + (size_t)(list->count * (uint64_t)list->stride);
}

/* Reading, puts the stream at record [i]; writing, nothing. */
static void list_record(Io *io, const List *list, uint32_t i) {
  if (!io->reading) return;
  io->at = list->data + (size_t)i * list->stride;
  io->end = io->at + list->stride;
}

static void list_end(Io *io, List *list) {
  if (!io->reading) {
    if (list->count > 0) {
      list->stride = (uint32_t)((io->n - list->start) / list->count);
      if (io->base != NULL) put_u32_at(io->base + list->stride_at, list->stride);
    }
    return;
  }
  io->at = list->after;
  io->end = list->outer_end;
}

/* A block of reals or of u32s: its count, then the numbers, all of them
 * there or the snapshot refused. On a little-endian host whose reals are
 * the writer's they are copied whole: the same bytes the fields would be. */
static void io_real_block(Io *io, f3d_real *v, uint64_t count) {
  uint32_t n = (uint32_t)count;
  io_u32(io, &n);
  if (io->reading && n != count) {
    io->bad = 1;
    return;
  }
  if (!io->reading) {
    if (F3D_HOST_LITTLE) {
      if (io->base != NULL && n > 0) {
        f3d_copy(io->base + io->n, v, (size_t)n * sizeof(f3d_real));
      }
      io->n += (uint64_t)n * sizeof(f3d_real);
    } else {
      io_reals(io, v, n);
    }
    return;
  }
  const uint64_t bytes = (uint64_t)n * io->real_bytes;
  if (bytes > (uint64_t)(io->end - io->at)) {
    io->bad = 1;
    return;
  }
  if (F3D_HOST_LITTLE && io->real_bytes == sizeof(f3d_real)) {
    if (n > 0) f3d_copy(v, io->at, (size_t)bytes);
    io->at += (size_t)bytes;
  } else {
    io_reals(io, v, n);
  }
}

static void io_u32_block(Io *io, uint32_t *v, uint64_t count) {
  uint32_t n = (uint32_t)count;
  io_u32(io, &n);
  if (io->reading && n != count) {
    io->bad = 1;
    return;
  }
  if (io->reading && (uint64_t)n * 4u > (uint64_t)(io->end - io->at)) {
    io->bad = 1;
    return;
  }
  if (F3D_HOST_LITTLE) {
    const size_t bytes = (size_t)n * 4u;
    if (!io->reading) {
      if (io->base != NULL && n > 0) f3d_copy(io->base + io->n, v, bytes);
      io->n += bytes;
    } else {
      if (n > 0) f3d_copy(v, io->at, bytes);
      io->at += bytes;
    }
    return;
  }
  for (uint32_t i = 0; i < n; i++) io_u32(io, &v[i]);
}

static void io_byte_block(Io *io, uint8_t *v, uint64_t count) {
  uint32_t n = (uint32_t)count;
  io_u32(io, &n);
  if (!io->reading) {
    if (n > 0) put_bytes(io, v, n);
    return;
  }
  if (n != count || n > (size_t)(io->end - io->at)) {
    io->bad = 1;
    return;
  }
  if (n > 0) f3d_copy(v, io->at, n);
  io->at += n;
}

/* ------------------------------------------------------------- records */

/* A material: a list of one, so it can gain a property without moving
 * what follows it in a body. */
static void io_material(Io *io, F3dMaterial *m) {
  List list;
  list_begin(io, &list, 1);
  if (list.count > 0) {
    list_record(io, &list, 0);
    io_real(io, &m->specific_heat);
    io_real(io, &m->emissivity);
    io_real(io, &m->ignition_temperature);
    io_real(io, &m->heat_of_combustion);
    io_real(io, &m->burn_rate);
    io_real(io, &m->fuel_fraction);
    io_real(io, &m->flame_feedback);
    io_real(io, &m->conductivity);
    io_real(io, &m->flame_temperature);
    io_real(io, &m->flame_convection);
    io_real(io, &m->flame_radiant);
    io_real(io, &m->flame_absorption);
    io_real(io, &m->heat_of_gasification);
    io_real(io, &m->critical_mass_flux);
    io_real(io, &m->flame_spread);
    io_real(io, &m->modulus);
    io_real(io, &m->poisson_ratio);
    io_real(io, &m->soot_temperature);
    io_real(io, &m->char_yield);
    io_real(io, &m->spread_minimum);
    io_real(io, &m->ignition_inertia);
    io_real(io, &m->element_surface);
    io_real(io, &m->element_density);
    io_real(io, &m->soot_yield);
  }
  list_end(io, &list);
}

/* A body: what moves it, its shape, what it meets. */
static void io_body(Io *io, F3dSlot *s) {
  io_u32(io, &s->generation);
  io_u32(io, &s->next_free);
  io_u8(io, &s->live);
  io_u8(io, &s->type);
  io_u8(io, &s->shape);
  io_u8(io, &s->flags);
  io_vec(io, &s->position);
  io_quat(io, &s->orientation);
  io_vec(io, &s->velocity);
  io_vec(io, &s->spin);
  io_vec(io, &s->force);
  io_vec(io, &s->torque);
  io_vec(io, &s->size);
  io_real(io, &s->mass);
  io_real(io, &s->inverse_mass);
  io_sym(io, &s->inertia);
  io_sym(io, &s->inverse_inertia);
  io_u32(io, &s->hull);
  io_real(io, &s->rounding);
  io_real(io, &s->linear_damping);
  io_real(io, &s->angular_damping);
  io_real(io, &s->drag);
  io_real(io, &s->surface);
  io_real(io, &s->shape_drag);
  io_real(io, &s->still);
  io_material(io, &s->material);
  io_real(io, &s->added_mass);
  io_real(io, &s->submerged);
  io_real(io, &s->liquid_speed);
  io_u32(io, &s->liquid);
  io_u32(io, &s->was_wet);
  io_real(io, &s->friction);
  io_real(io, &s->restitution);
  io_u32(io, &s->layer);
  io_u32(io, &s->mask);
  io_u32(io, &s->lumps);
  io_u32(io, &s->lump_count);
}

/* A body's heat: how hot, and how the heat lies in it. */
static void io_body_heat(Io *io, F3dSlot *s) {
  io_real(io, &s->temperature);
  io_real(io, &s->interior);
  io_real(io, &s->reached);
  io_real(io, &s->skin);
  io_real(io, &s->heat);
  io_real(io, &s->water);
}

/* A body's fire: its fuel, its burning patch and char, its burner and the
 * flame held to it. */
static void io_body_fire(Io *io, F3dSlot *s) {
  io_real(io, &s->fuel);
  io_real(io, &s->heat_release);
  io_real(io, &s->involved);
  io_real(io, &s->spread);
  io_real(io, &s->rise);
  io_real(io, &s->patch);
  io_real(io, &s->exposure);
  io_real(io, &s->char_depth);
  io_real(io, &s->char_skin);
  io_real(io, &s->charred);
  io_real(io, &s->feed);
  io_material(io, &s->burner);
  io_vec(io, &s->held_at);
  io_real(io, &s->held_flux);
  io_real(io, &s->held_area);
  io_real(io, &s->held_temperature);
}

static void io_lump(Io *io, F3dLump *l) {
  io_real(io, &l->temperature);
  io_real(io, &l->heat);
  io_real(io, &l->water);
  io_real(io, &l->fuel);
  io_real(io, &l->mass);
  io_real(io, &l->heat_release);
  io_real(io, &l->interior);
  io_real(io, &l->reached);
  io_real(io, &l->skin);
  io_real(io, &l->involved);
  io_real(io, &l->spread);
  io_real(io, &l->rise);
  io_real(io, &l->patch);
  io_real(io, &l->exposure);
  io_real(io, &l->char_depth);
  io_real(io, &l->char_skin);
  io_real(io, &l->charred);
  io_real(io, &l->joint);
  io_real(io, &l->immersed);
  io_u32(io, &l->burning);
  io_u32(io, &l->edge);
}

static void io_event(Io *io, F3dEventRecord *e) {
  io_u64(io, &e->body);
  io_u64(io, &e->other);
  io_u32(io, &e->kind);
}

static void io_manifold(Io *io, F3dManifold *m) {
  io_u64(io, &m->a);
  io_u64(io, &m->b);
  io_vec(io, &m->normal);
  io_u32(io, &m->count);
  io_u32(io, &m->touching);
  io_u32(io, &m->part);
  List points;
  list_begin(io, &points, F3D_MANIFOLD_POINTS);
  if (points.count > F3D_MANIFOLD_POINTS || points.count < m->count) io->bad = 1;
  for (uint32_t i = 0; i < points.count && i < F3D_MANIFOLD_POINTS; i++) {
    list_record(io, &points, i);
    F3dContactPoint *p = &m->points[i];
    io_vec(io, &p->point);
    io_real(io, &p->depth);
    io_u32(io, &p->id);
    io_real(io, &p->normal_impulse);
    io_real(io, &p->tangent_impulse[0]);
    io_real(io, &p->tangent_impulse[1]);
  }
  list_end(io, &points);
}

static void io_hull(Io *io, F3dHull *h) {
  io_u32(io, &h->first_vertex);
  io_u32(io, &h->vertex_count);
  io_u32(io, &h->first_triangle);
  io_u32(io, &h->triangle_count);
  io_vec(io, &h->offset);
  io_vec(io, &h->lo);
  io_vec(io, &h->hi);
  io_real(io, &h->volume);
  io_real(io, &h->surface);
  io_sym(io, &h->unit_inertia);
}

static void io_mesh(Io *io, F3dMesh *m) {
  io_u32(io, &m->first_vertex);
  io_u32(io, &m->vertex_count);
  io_u32(io, &m->first_triangle);
  io_u32(io, &m->triangle_count);
  io_vec(io, &m->lo);
  io_vec(io, &m->hi);
  io_real(io, &m->surface);
}

static void io_joint(Io *io, F3dJointSlot *j) {
  io_u32(io, &j->generation);
  io_u32(io, &j->next_free);
  io_u8(io, &j->live);
  io_u8(io, &j->type);
  io_u8(io, &j->flags);
  io_u64(io, &j->a);
  io_u64(io, &j->b);
  io_vec(io, &j->local_a);
  io_vec(io, &j->local_b);
  io_vec(io, &j->axis_a);
  io_vec(io, &j->axis_b);
  io_quat(io, &j->reference);
  io_real(io, &j->lower);
  io_real(io, &j->upper);
  io_real(io, &j->motor_speed);
  io_real(io, &j->motor_force);
  io_real(io, &j->spring_hertz);
  io_real(io, &j->spring_damping);
  io_real(io, &j->length);
  io_real(io, &j->least);
  io_real(io, &j->most);
  io_reals(io, j->impulse, 6);
  io_real(io, &j->lower_impulse);
  io_real(io, &j->upper_impulse);
  io_real(io, &j->motor_impulse);
  io_real(io, &j->spring_impulse);
  io_vec(io, &j->pushed);
  io_real(io, &j->cone);
  io_real(io, &j->cone_impulse);
  io_real(io, &j->friction);
  io_vec(io, &j->friction_impulse);
  io_real(io, &j->break_force);
  io_real(io, &j->break_torque);
  io_vec(io, &j->turned);
}

static void io_compound(Io *io, F3dCompound *c) {
  io_u32(io, &c->first_part);
  io_u32(io, &c->part_count);
  io_vec(io, &c->offset);
  io_vec(io, &c->lo);
  io_vec(io, &c->hi);
  io_real(io, &c->volume);
  io_real(io, &c->surface);
  io_sym(io, &c->unit_inertia);
}

static void io_part(Io *io, F3dCompoundPart *p) {
  io_u32(io, &p->kind);
  io_u32(io, &p->hull);
  io_vec(io, &p->size);
  io_real(io, &p->rounding);
  io_vec(io, &p->at);
  io_quat(io, &p->turn);
  io_real(io, &p->reach);
}

static void io_wheel(Io *io, F3dWheel *w) {
  io_vec(io, &w->attach);
  io_real(io, &w->rest);
  io_real(io, &w->radius);
  io_real(io, &w->stiffness);
  io_real(io, &w->damping);
  io_real(io, &w->grip);
  io_real(io, &w->steer);
  io_real(io, &w->drive);
  io_real(io, &w->brake);
  io_u32(io, &w->touching);
  io_real(io, &w->length);
  io_real(io, &w->rotation);
  io_real(io, &w->spin);
  io_real(io, &w->force);
  io_real(io, &w->lateral);
  io_real(io, &w->skid);
  io_vec(io, &w->centre);
  io_vec(io, &w->normal);
  io_real(io, &w->width);
  io_real(io, &w->rolling);
}

static void io_vehicle(Io *io, F3dVehicleSlot *v) {
  io_u32(io, &v->live);
  io_u32(io, &v->wheel_count);
  io_u64(io, &v->chassis);
  io_vec(io, &v->up);
  io_vec(io, &v->forward);
  if (v->wheel_count > F3D_VEHICLE_MOST_WHEELS) io->bad = 1;
  /* Every wheel the slot has room for, in use or not; reading, those past
   * this build's room are passed over, and too few to hold the ones in use
   * is damage. */
  List wheels;
  list_begin(io, &wheels, F3D_VEHICLE_MOST_WHEELS);
  if (wheels.count < v->wheel_count) io->bad = 1;
  for (uint32_t i = 0; i < wheels.count && i < F3D_VEHICLE_MOST_WHEELS; i++) {
    list_record(io, &wheels, i);
    io_wheel(io, &v->wheels[i]);
  }
  list_end(io, &wheels);
}

static void io_link(Io *io, F3dLink *l) {
  io_u64(io, &l->body);
  io_u32(io, &l->parent);
  io_u32(io, &l->type);
  io_u32(io, &l->first_dof);
  io_u32(io, &l->dofs);
  io_u32(io, &l->flags);
  io_vec(io, &l->parent_anchor);
  io_vec(io, &l->child_anchor);
  io_vec(io, &l->axis);
  io_quat(io, &l->reference);
  io_real(io, &l->q);
  io_real(io, &l->qd);
  io_quat(io, &l->turn);
  io_vec(io, &l->spin);
  io_real(io, &l->lower);
  io_real(io, &l->upper);
  io_real(io, &l->motor_speed);
  io_real(io, &l->motor_force);
  io_real(io, &l->motor_q);
  io_real(io, &l->servo_stiffness);
  io_real(io, &l->servo_damping);
  io_real(io, &l->left_q);
  io_real(io, &l->drift);
  io_real(io, &l->swing);
  io_real(io, &l->twist);
}

static void io_multibody(Io *io, F3dMultibodySlot *m) {
  io_u32(io, &m->live);
  io_u32(io, &m->link_count);
  io_u32(io, &m->dof_count);
  io_u32(io, &m->floating);
  if (m->link_count > F3D_MULTIBODY_MOST_LINKS) io->bad = 1;
  List links;
  list_begin(io, &links, F3D_MULTIBODY_MOST_LINKS);
  if (links.count < m->link_count) io->bad = 1;
  for (uint32_t i = 0; i < links.count && i < F3D_MULTIBODY_MOST_LINKS; i++) {
    list_record(io, &links, i);
    io_link(io, &m->links[i]);
  }
  list_end(io, &links);
}

static void io_water(Io *io, F3dShallowSlot *w) {
  io_u32(io, &w->live);
  io_u32(io, &w->nx);
  io_u32(io, &w->nz);
  io_u32(io, &w->first);
  io_real(io, &w->cell);
  io_vec(io, &w->origin);
  io_real(io, &w->roughness);
  for (int i = 0; i < 4; i++) io_u32(io, &w->edge_kind[i]);
  io_reals(io, w->edge_value, 4);
  io_u32(io, &w->outlet_count);
  if (w->outlet_count > F3D_SHALLOW_MOST_OUTLETS) io->bad = 1;
  List outlets;
  list_begin(io, &outlets, F3D_SHALLOW_MOST_OUTLETS);
  for (uint32_t i = 0; i < outlets.count && i < F3D_SHALLOW_MOST_OUTLETS; i++) {
    list_record(io, &outlets, i);
    F3dShallowOutlet *o = &w->outlets[i];
    io_real(io, &o->x);
    io_real(io, &o->z);
    io_real(io, &o->crest);
    io_real(io, &o->width);
    io_real(io, &o->coefficient);
    io_u32(io, &o->kind);
  }
  list_end(io, &outlets);
  io_u32(io, &w->substeps);
  io_u32(io, &w->overruns);
  io_real(io, &w->energy);
  io_real(io, &w->density);
  io_real(io, &w->viscosity);
  io_real(io, &w->tension);
  io_real(io, &w->temperature);
  io_real(io, &w->specific_heat);
  io_real(io, &w->conductivity);
  io_real(io, &w->expansion);
  io_u32(io, &w->boils);
  io_real(io, &w->lost);
  io_real(io, &w->calm);
  io_u32(io, &w->resting);
  io_real(io, &w->top);
  io_u32(io, &w->source_count);
  if (w->source_count > F3D_SHALLOW_MOST_SOURCES) io->bad = 1;
  List sources;
  list_begin(io, &sources, F3D_SHALLOW_MOST_SOURCES);
  for (uint32_t i = 0; i < sources.count && i < F3D_SHALLOW_MOST_SOURCES; i++) {
    list_record(io, &sources, i);
    F3dShallowSource *s = &w->sources[i];
    io_real(io, &s->x);
    io_real(io, &s->z);
    io_real(io, &s->radius);
    io_real(io, &s->rate);
  }
  list_end(io, &sources);
}

static void io_spray(Io *io, F3dSpray *s) {
  io_vec(io, &s->at);
  io_vec(io, &s->velocity);
  io_real(io, &s->volume);
  io_u32(io, &s->water);
  io_u32(io, &s->kind);
  io_u32(io, &s->face);
  io_real(io, &s->flow);
  io_real(io, &s->width);
  io_real(io, &s->speed0);
  io_real(io, &s->top);
  io_real(io, &s->growth);
}

static void io_bubbles(Io *io, F3dBubbles *b) {
  io_vec(io, &b->at);
  io_real(io, &b->radius);
  io_real(io, &b->air);
  io_u32(io, &b->water);
}

/* ------------------------------------------------------------ sections
 *
 * Writing, a Staged names the world's own arrays; reading, it holds the
 * ones being filled, all of them allocated before the world is touched, so
 * a snapshot refused halfway leaves the world as it was.
 */
typedef struct Staged {
  F3dWorldState s;
  F3dSlot *slots;
  f3d_real *grid;
  F3dEventRecord *events;
  F3dManifold *manifolds;
  F3dHull *hulls;
  f3d_real *hull_vertices;
  uint32_t *hull_triangles;
  F3dMesh *meshes;
  f3d_real *mesh_vertices;
  uint32_t *mesh_triangles;
  uint8_t *mesh_edges;
  F3dJointSlot *joints;
  F3dCompound *compounds;
  F3dCompoundPart *compound_parts;
  F3dVehicleSlot *vehicles;
  F3dMultibodySlot *multibodies;
  F3dLump *lumps;
  F3dShallowSlot *shallows;
  f3d_real *shallow_data;
  F3dSpray *spray;
  F3dBubbles *bubbles;
} Staged;

static void staged_free(Staged *st) {
  f3d_free(st->slots);
  f3d_free(st->grid);
  f3d_free(st->events);
  f3d_free(st->manifolds);
  f3d_free(st->hulls);
  f3d_free(st->hull_vertices);
  f3d_free(st->hull_triangles);
  f3d_free(st->meshes);
  f3d_free(st->mesh_vertices);
  f3d_free(st->mesh_triangles);
  f3d_free(st->mesh_edges);
  f3d_free(st->joints);
  f3d_free(st->compounds);
  f3d_free(st->compound_parts);
  f3d_free(st->vehicles);
  f3d_free(st->multibodies);
  f3d_free(st->lumps);
  f3d_free(st->shallows);
  f3d_free(st->shallow_data);
  f3d_free(st->spray);
  f3d_free(st->bubbles);
}

/* Reading, [count] zeroed items of [size] into *[block] — none for
 * nought; marks the stream bad when there is no memory, or when what is
 * left of the section cannot hold [count] items of [least] bytes each, so
 * a count is believed only as far as the bytes behind it go and a short
 * snapshot never asks for gigabytes. [least] is nought for a block of a
 * fixed size, its count already bounded. Writing, nothing. */
static void make(Io *io, void **block, uint64_t count, size_t size, uint32_t least) {
  if (!io->reading || io->bad) return;
  if (count == 0) return;
  if (count * least > (uint64_t)(io->end - io->at)) {
    io->bad = 1;
    return;
  }
  const uint64_t bytes = count * (uint64_t)size;
  if (bytes / size != count || bytes > (uint64_t)SIZE_MAX) {
    io->bad = 1;
    return;
  }
  *block = f3d_alloc((size_t)bytes);
  if (*block == NULL) {
    io->bad = 1;
    return;
  }
  f3d_zero(*block, (size_t)bytes);
}

/* A list of [count] records, each read or written by [visit]; reading, the
 * list must hold [count] of them. */
#define IO_LIST(io, n, items, visit)                              \
  do {                                                            \
    List list_;                                                   \
    const uint32_t n_ = (n);                                      \
    list_begin((io), &list_, n_);                                 \
    if ((io)->reading && list_.count != n_) (io)->bad = 1;        \
    for (uint32_t i_ = 0; !(io)->bad && i_ < n_; i_++) {          \
      list_record((io), &list_, i_);                              \
      visit((io), &(items)[i_]);                                  \
    }                                                             \
    list_end((io), &list_);                                       \
  } while (0)

/* The world's own numbers. Version 2 added the water's rest; version 1,
 * without it, reads as a world that never set one, which steps with the
 * defaults. */
#define WORLD_VERSION 2u
static void sec_world(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  for (int i = 0; i < 3; i++) io_f64(io, &s->origin[i]);
  io_vec(io, &s->gravity);
  io_vec(io, &s->wind);
  io_real(io, &s->air_temperature);
  io_real(io, &s->air_density);
  io_real(io, &s->sleep_speed);
  io_real(io, &s->sleep_time);
  io_real(io, &s->contact_margin);
  io_u32(io, &s->speculative);
  io_u32(io, &s->substeps);
  io_real(io, &s->last_substep);
  io_u32(io, &s->fast);
  if (io->version >= 2) {
    io_real(io, &s->water_rest_energy);
    io_real(io, &s->water_rest_time);
    io_u32(io, &s->water_rest_set);
  } else {
    s->water_rest_energy = F3D_R(0.0);
    s->water_rest_time = F3D_R(0.0);
    s->water_rest_set = 0;
  }
}

/* The bodies' arena: its marks, then every slot up to the high-water one. */
static void sec_bodies(Io *io, Staged *st) {
  io_u32(io, &st->s.used);
  io_u32(io, &st->s.live);
  io_u32(io, &st->s.free_head);
  make(io, (void **)&st->slots, st->s.used, sizeof(F3dSlot), 1);
  IO_LIST(io, st->s.used, st->slots, io_body);
}

static void sec_heat(Io *io, Staged *st) {
  IO_LIST(io, st->s.used, st->slots, io_body_heat);
}

static void sec_fire(Io *io, Staged *st) {
  IO_LIST(io, st->s.used, st->slots, io_body_fire);
}

/* The compounds' parts' heat and fire. */
static void sec_lumps(Io *io, Staged *st) {
  io_u32(io, &st->s.lump_count);
  make(io, (void **)&st->lumps, st->s.lump_count, sizeof(F3dLump), 1);
  IO_LIST(io, st->s.lump_count, st->lumps, io_lump);
}

/* The wind grid: none, all three counts nought, or a grid of at least a
 * sample each way whose reals the section holds. */
static void sec_wind(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  io_vec(io, &s->grid_origin);
  io_real(io, &s->grid_cell);
  for (int i = 0; i < 3; i++) io_u32(io, &s->grid_n[i]);
  const uint32_t *n = s->grid_n;
  if (io->reading && (n[0] == 0 || n[1] == 0 || n[2] == 0) &&
      (n[0] | n[1] | n[2]) != 0) {
    io->bad = 1;
  }
  /* Two counts first, so the three never overflow what they are kept in. */
  const uint64_t plane = (uint64_t)n[0] * n[1];
  if (plane > UINT32_MAX) io->bad = 1;
  const uint64_t reals = io->bad ? 0u : plane * n[2] * 3u;
  if (reals > UINT32_MAX) io->bad = 1;
  make(io, (void **)&st->grid, reals, sizeof(f3d_real), io->real_bytes);
  if (!io->bad) io_real_block(io, st->grid, reals);
}

/* The events waiting, oldest first: written from the ring wherever it
 * starts, read into one that starts at nought. */
static void sec_events(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  io_u32(io, &s->events_dropped);
  io_u32(io, &s->events_count);
  if (io->reading) {
    s->events_head = 0;
    if (s->events_count > F3D_EVENT_CAPACITY) io->bad = 1;
    if (s->events_count > 0) {
      make(io, (void **)&st->events, F3D_EVENT_CAPACITY, sizeof(F3dEventRecord), 0);
    }
  }
  List list;
  list_begin(io, &list, s->events_count);
  if (io->reading && list.count != s->events_count) io->bad = 1;
  for (uint32_t i = 0; !io->bad && i < s->events_count; i++) {
    list_record(io, &list, i);
    io_event(io, &st->events[(s->events_head + i) % F3D_EVENT_CAPACITY]);
  }
  list_end(io, &list);
}

/* The last step's contacts: what the next compares against to say what
 * began and ended, and the impulses it warm-starts from. */
static void sec_contacts(Io *io, Staged *st) {
  io_u32(io, &st->s.manifold_count);
  make(io, (void **)&st->manifolds, st->s.manifold_count, sizeof(F3dManifold), 1);
  IO_LIST(io, st->s.manifold_count, st->manifolds, io_manifold);
}

static void sec_hulls(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  io_u32(io, &s->hull_count);
  io_u32(io, &s->hull_vertex_count);
  io_u32(io, &s->hull_triangle_count);
  make(io, (void **)&st->hulls, s->hull_count, sizeof(F3dHull), 1);
  make(io, (void **)&st->hull_vertices, (uint64_t)s->hull_vertex_count * 3u,
       sizeof(f3d_real), io->real_bytes);
  make(io, (void **)&st->hull_triangles, (uint64_t)s->hull_triangle_count * 3u,
       sizeof(uint32_t), 4);
  IO_LIST(io, s->hull_count, st->hulls, io_hull);
  if (io->bad) return;
  io_real_block(io, st->hull_vertices, (uint64_t)s->hull_vertex_count * 3u);
  io_u32_block(io, st->hull_triangles, (uint64_t)s->hull_triangle_count * 3u);
}

static void sec_meshes(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  io_u32(io, &s->mesh_count);
  io_u32(io, &s->mesh_vertex_count);
  io_u32(io, &s->mesh_triangle_count);
  make(io, (void **)&st->meshes, s->mesh_count, sizeof(F3dMesh), 1);
  make(io, (void **)&st->mesh_vertices, (uint64_t)s->mesh_vertex_count * 3u,
       sizeof(f3d_real), io->real_bytes);
  make(io, (void **)&st->mesh_triangles, (uint64_t)s->mesh_triangle_count * 3u,
       sizeof(uint32_t), 4);
  make(io, (void **)&st->mesh_edges, s->mesh_triangle_count, 1, 1);
  IO_LIST(io, s->mesh_count, st->meshes, io_mesh);
  if (io->bad) return;
  io_real_block(io, st->mesh_vertices, (uint64_t)s->mesh_vertex_count * 3u);
  io_u32_block(io, st->mesh_triangles, (uint64_t)s->mesh_triangle_count * 3u);
  io_byte_block(io, st->mesh_edges, s->mesh_triangle_count);
}

/* The joints' arena, warm-start impulses and all. */
static void sec_joints(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  io_u32(io, &s->joint_used);
  io_u32(io, &s->joint_live);
  io_u32(io, &s->joint_free_head);
  make(io, (void **)&st->joints, s->joint_used, sizeof(F3dJointSlot), 1);
  IO_LIST(io, s->joint_used, st->joints, io_joint);
}

static void sec_compounds(Io *io, Staged *st) {
  F3dWorldState *s = &st->s;
  io_u32(io, &s->compound_count);
  io_u32(io, &s->compound_part_count);
  make(io, (void **)&st->compounds, s->compound_count, sizeof(F3dCompound), 1);
  make(io, (void **)&st->compound_parts, s->compound_part_count,
       sizeof(F3dCompoundPart), 1);
  IO_LIST(io, s->compound_count, st->compounds, io_compound);
  IO_LIST(io, s->compound_part_count, st->compound_parts, io_part);
}

/* The vehicles, their wheels as the last step left them. */
static void sec_vehicles(Io *io, Staged *st) {
  io_u32(io, &st->s.vehicle_count);
  make(io, (void **)&st->vehicles, st->s.vehicle_count, sizeof(F3dVehicleSlot), 1);
  IO_LIST(io, st->s.vehicle_count, st->vehicles, io_vehicle);
}

/* The multibodies, their joints as the last step left them. */
static void sec_multibodies(Io *io, Staged *st) {
  io_u32(io, &st->s.multibody_count);
  io_u32(io, &st->s.multibody_links);
  make(io, (void **)&st->multibodies, st->s.multibody_count,
       sizeof(F3dMultibodySlot), 1);
  IO_LIST(io, st->s.multibody_count, st->multibodies, io_multibody);
}

/* The waters and their grids. */
static void sec_waters(Io *io, Staged *st) {
  io_u32(io, &st->s.shallow_count);
  io_u32(io, &st->s.shallow_reals);
  make(io, (void **)&st->shallows, st->s.shallow_count, sizeof(F3dShallowSlot), 1);
  make(io, (void **)&st->shallow_data, st->s.shallow_reals, sizeof(f3d_real),
       io->real_bytes);
  IO_LIST(io, st->s.shallow_count, st->shallows, io_water);
  if (!io->bad) io_real_block(io, st->shallow_data, st->s.shallow_reals);
}

/* The water in flight, held in blocks as large as the most there may be,
 * as the step keeps them. */
static void sec_spray(Io *io, Staged *st) {
  io_u32(io, &st->s.spray_count);
  if (io->reading && st->s.spray_count > F3D_SHALLOW_MOST_SPRAY) io->bad = 1;
  if (st->s.spray_count > 0) {
    make(io, (void **)&st->spray, F3D_SHALLOW_MOST_SPRAY, sizeof(F3dSpray), 0);
  }
  IO_LIST(io, st->s.spray_count, st->spray, io_spray);
}

static void sec_bubbles(Io *io, Staged *st) {
  io_u32(io, &st->s.bubble_count);
  if (io->reading && st->s.bubble_count > F3D_SHALLOW_MOST_BUBBLES) io->bad = 1;
  if (st->s.bubble_count > 0) {
    make(io, (void **)&st->bubbles, F3D_SHALLOW_MOST_BUBBLES, sizeof(F3dBubbles), 0);
  }
  IO_LIST(io, st->s.bubble_count, st->bubbles, io_bubbles);
}

typedef struct Section {
  uint32_t id;
  /* The version this build writes. */
  uint32_t version;
  /* The format minor it came in: a snapshot of that minor or later must
   * have it, an earlier one reads without it. */
  uint32_t since_minor;
  void (*io)(Io *io, Staged *st);
} Section;

/* In the order they are written and read: the bodies before what is kept
 * a body at a time. */
static const Section kSections[] = {
    {F3D_SECTION('W', 'R', 'L', 'D'), WORLD_VERSION, 0, sec_world},
    {F3D_SECTION('B', 'O', 'D', 'Y'), 1, 0, sec_bodies},
    {F3D_SECTION('H', 'E', 'A', 'T'), 1, 0, sec_heat},
    {F3D_SECTION('F', 'I', 'R', 'E'), 1, 0, sec_fire},
    {F3D_SECTION('L', 'U', 'M', 'P'), 1, 0, sec_lumps},
    {F3D_SECTION('W', 'I', 'N', 'D'), 1, 0, sec_wind},
    {F3D_SECTION('E', 'V', 'N', 'T'), 1, 0, sec_events},
    {F3D_SECTION('C', 'O', 'N', 'T'), 1, 0, sec_contacts},
    {F3D_SECTION('H', 'U', 'L', 'L'), 1, 0, sec_hulls},
    {F3D_SECTION('M', 'E', 'S', 'H'), 1, 0, sec_meshes},
    {F3D_SECTION('J', 'O', 'I', 'N'), 1, 0, sec_joints},
    {F3D_SECTION('C', 'O', 'M', 'P'), 1, 0, sec_compounds},
    {F3D_SECTION('V', 'E', 'H', 'I'), 1, 0, sec_vehicles},
    {F3D_SECTION('M', 'B', 'O', 'D'), 1, 0, sec_multibodies},
    {F3D_SECTION('W', 'A', 'T', 'R'), 1, 0, sec_waters},
    {F3D_SECTION('S', 'P', 'R', 'Y'), 1, 0, sec_spray},
    {F3D_SECTION('B', 'U', 'B', 'L'), 1, 0, sec_bubbles},
};

#define SECTION_COUNT (sizeof kSections / sizeof kSections[0])
#define HEADER_BYTES 20u
#define SECTION_HEADER_BYTES 12u

/* Writes, or with a null [base] counts, the snapshot of [world]. */
static uint64_t write_all(const F3dWorld *world, uint8_t *base) {
  Staged st;
  f3d_zero(&st, sizeof st);
  f3d_copy(&st.s, &world->s, sizeof st.s);
  /* Only read: the walk is the reader's too, so it takes them unqualified. */
  st.slots = world->slots;
  st.grid = world->grid;
  st.events = world->events;
  st.manifolds = world->manifolds;
  st.hulls = world->hulls;
  st.hull_vertices = world->hull_vertices;
  st.hull_triangles = world->hull_triangles;
  st.meshes = world->meshes;
  st.mesh_vertices = world->mesh_vertices;
  st.mesh_triangles = world->mesh_triangles;
  st.mesh_edges = world->mesh_edges;
  st.joints = world->joints;
  st.compounds = world->compounds;
  st.compound_parts = world->compound_parts;
  st.vehicles = world->vehicles;
  st.multibodies = world->multibodies;
  st.lumps = world->lumps;
  st.shallows = world->shallows;
  st.shallow_data = world->shallow_data;
  st.spray = world->spray;
  st.bubbles = world->bubbles;

  Io io;
  f3d_zero(&io, sizeof io);
  io.base = base;
  uint32_t magic = F3D_SNAPSHOT_MAGIC;
  uint32_t format = F3D_SNAPSHOT_MINOR | (F3D_SNAPSHOT_MAJOR << 16);
  uint32_t abi = F3D_ABI_VERSION;
  uint32_t real_bytes = (uint32_t)sizeof(f3d_real);
  uint32_t sections = (uint32_t)SECTION_COUNT;
  io_u32(&io, &magic);
  io_u32(&io, &format);
  io_u32(&io, &abi);
  io_u32(&io, &real_bytes);
  io_u32(&io, &sections);
  for (uint32_t i = 0; i < SECTION_COUNT; i++) {
    uint32_t id = kSections[i].id;
    uint32_t version = kSections[i].version;
    uint32_t length = 0;
    io_u32(&io, &id);
    io_u32(&io, &version);
    const uint64_t length_at = io.n;
    io_u32(&io, &length);
    io.version = version;
    kSections[i].io(&io, &st);
    if (base != NULL) {
      put_u32_at(base + length_at, (uint32_t)(io.n - length_at - 4u));
    }
  }
  return io.n;
}

uint32_t f3d_world_snapshot_size(const F3dWorld *world) {
  const uint64_t size = write_all(world, NULL);
  return size > UINT32_MAX ? 0u : (uint32_t)size;
}

uint32_t f3d_world_snapshot_write(const F3dWorld *world, uint8_t *buffer,
                                  uint32_t size) {
  const uint32_t needed = f3d_world_snapshot_size(world);
  if (needed == 0 || size < needed || buffer == NULL) return 0;
  write_all(world, buffer);
  return needed;
}

/* Whether [body] names a slot of the arena [st] read: what a step indexes
 * the slots with before it asks whether the body is still there. */
static int names_slot(const Staged *st, F3dBody body) {
  return (uint32_t)(body & 0xffffffffu) < st->s.used;
}

/* Whether [index], one past a place in a table of [count], is in it. */
static int one_past_in(uint32_t index, uint32_t count) {
  return index != 0 && index <= count;
}

/* Whether every triangle of [count] at [triangles] names three of the
 * [vertices] it is given. */
static int corners_in(const uint32_t *triangles, uint32_t count, uint32_t vertices) {
  for (uint64_t k = 0; k < (uint64_t)count * 3u; k++) {
    if (triangles[k] >= vertices) return 0;
  }
  return 1;
}

/* Whether a body of [shape] names, by [hull], a table entry the snapshot
 * has: a hull, a mesh or a compound; any other shape names none. */
static int shape_in(const Staged *st, uint8_t shape, uint32_t hull) {
  const F3dWorldState *s = &st->s;
  switch (shape) {
    case F3D_SHAPE_POINT:
    case F3D_SHAPE_SPHERE:
    case F3D_SHAPE_BOX:
    case F3D_SHAPE_CAPSULE:
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      return 1;
    case F3D_SHAPE_HULL:
      return one_past_in(hull, s->hull_count);
    case F3D_SHAPE_MESH:
      return one_past_in(hull, s->mesh_count);
    case F3D_SHAPE_COMPOUND:
      return one_past_in(hull, s->compound_count);
    default:
      return 0;
  }
}

/* The reals a water of [nx] × [nz] cells holds, as f3d_shallow.c lays
 * them out. */
static uint64_t water_reals(uint32_t nx, uint32_t nz) {
  return 5u * (uint64_t)nx * nz + ((uint64_t)nx + 1u) * nz + (uint64_t)nx * (nz + 1u);
}

/* Whether what was read hangs together: the arenas' marks inside them;
 * every hull's, mesh's, compound's and water's share inside the arrays it
 * names; every index a step follows — a body's shape and lumps, a
 * compound's part's hull, a triangle's corners, a contact's, a joint's, a
 * vehicle's and a link's bodies, a link's parent and freedoms — inside
 * what it indexes. A step reads all of these without asking again, so a
 * snapshot that fails one is refused rather than read past an array. */
static int consistent(const Staged *st) {
  const F3dWorldState *s = &st->s;
  if (s->live > s->used || s->free_head > s->used) return 0;
  /* The free list runs through free slots only, and the live are as many
   * as the arena says: what a caller sizes its buffers by. */
  if (s->free_head != 0 && st->slots[s->free_head - 1u].live) return 0;
  uint32_t live = 0;
  for (uint32_t i = 0; i < s->used; i++) {
    const F3dSlot *b = &st->slots[i];
    if (b->next_free > s->used) return 0;
    if (!b->live) {
      if (b->next_free != 0 && st->slots[b->next_free - 1u].live) return 0;
      continue;
    }
    live++;
    if (!shape_in(st, b->shape, b->hull)) return 0;
    if (b->lumps != 0) {
      /* A compound's parts' heat, one lump a part at most. */
      if (b->shape != F3D_SHAPE_COMPOUND ||
          (uint64_t)b->lumps - 1u + b->lump_count > s->lump_count ||
          b->lump_count > st->compounds[b->hull - 1u].part_count) {
        return 0;
      }
    }
    if (b->liquid > s->shallow_count) return 0;
  }
  if (live != s->live) return 0;
  if (s->joint_live > s->joint_used || s->joint_free_head > s->joint_used) {
    return 0;
  }
  if (s->joint_free_head != 0 && st->joints[s->joint_free_head - 1u].live) return 0;
  uint32_t joints_live = 0;
  for (uint32_t i = 0; i < s->joint_used; i++) {
    const F3dJointSlot *j = &st->joints[i];
    if (j->next_free > s->joint_used) return 0;
    if (!j->live) {
      if (j->next_free != 0 && st->joints[j->next_free - 1u].live) return 0;
      continue;
    }
    joints_live++;
    if (!names_slot(st, j->a) || !names_slot(st, j->b)) return 0;
  }
  if (joints_live != s->joint_live) return 0;
  for (uint32_t i = 0; i < s->hull_count; i++) {
    const F3dHull *h = &st->hulls[i];
    if ((uint64_t)h->first_vertex + h->vertex_count > s->hull_vertex_count ||
        (uint64_t)h->first_triangle + h->triangle_count > s->hull_triangle_count) {
      return 0;
    }
    if (!corners_in(st->hull_triangles + (size_t)h->first_triangle * 3u,
                    h->triangle_count, h->vertex_count)) {
      return 0;
    }
  }
  for (uint32_t i = 0; i < s->mesh_count; i++) {
    const F3dMesh *m = &st->meshes[i];
    if ((uint64_t)m->first_vertex + m->vertex_count > s->mesh_vertex_count ||
        (uint64_t)m->first_triangle + m->triangle_count > s->mesh_triangle_count) {
      return 0;
    }
    if (!corners_in(st->mesh_triangles + (size_t)m->first_triangle * 3u,
                    m->triangle_count, m->vertex_count)) {
      return 0;
    }
  }
  for (uint32_t i = 0; i < s->compound_count; i++) {
    const F3dCompound *c = &st->compounds[i];
    if ((uint64_t)c->first_part + c->part_count > s->compound_part_count) return 0;
  }
  for (uint32_t i = 0; i < s->compound_part_count; i++) {
    /* A part is one of the shapes f3d_world_create_compound takes: never a
     * mesh or a compound, and a hull only as one the world holds. */
    const F3dCompoundPart *p = &st->compound_parts[i];
    if (p->kind > F3D_SHAPE_HULL) return 0;
    if (p->kind == F3D_SHAPE_HULL && !one_past_in(p->hull, s->hull_count)) return 0;
  }
  for (uint32_t i = 0; i < s->manifold_count; i++) {
    const F3dManifold *m = &st->manifolds[i];
    if (!names_slot(st, m->a) || !names_slot(st, m->b)) return 0;
  }
  for (uint32_t i = 0; i < s->vehicle_count; i++) {
    const F3dVehicleSlot *v = &st->vehicles[i];
    if (v->live && !names_slot(st, v->chassis)) return 0;
  }
  /* The links beside the roots, as the world counts them: what the
   * collision filter makes room for. */
  uint64_t links = 0;
  for (uint32_t i = 0; i < s->multibody_count; i++) {
    const F3dMultibodySlot *m = &st->multibodies[i];
    if (!m->live) continue;
    links += m->link_count - (m->link_count > 0 ? 1u : 0u);
    /* A root at least, and a floating one's six freedoms first. */
    if (m->link_count == 0 || m->dof_count > F3D_MULTIBODY_MOST_DOFS ||
        (m->floating && m->dof_count < 6u)) {
      return 0;
    }
    for (uint32_t k = 0; k < m->link_count; k++) {
      const F3dLink *l = &m->links[k];
      /* Parents before children: the root's is its own. */
      if (k > 0 && l->parent >= k) return 0;
      if (l->dofs > 3u || (uint64_t)l->first_dof + l->dofs > m->dof_count) return 0;
      if (!names_slot(st, l->body)) return 0;
    }
  }
  if (links != s->multibody_links) return 0;
  for (uint32_t i = 0; i < s->shallow_count; i++) {
    const F3dShallowSlot *w = &st->shallows[i];
    if (!w->live) continue;
    /* As f3d_shallow_create makes them. */
    if (w->nx == 0 || w->nz == 0 || w->nx > 4096u || w->nz > 4096u) return 0;
    if ((uint64_t)w->first + water_reals(w->nx, w->nz) > s->shallow_reals) return 0;
  }
  return 1;
}

/* Reads [buffer] into [st]: 1, or 0 with whatever was made still in [st]
 * for the caller to free. */
static int read_all(const uint8_t *buffer, uint32_t size, Staged *st) {
  if (size < HEADER_BYTES) return 0;
  const uint32_t magic = get_u32_at(buffer);
  const uint32_t format = get_u32_at(buffer + 4);
  const uint32_t real_bytes = get_u32_at(buffer + 12);
  const uint32_t section_count = get_u32_at(buffer + 16);
  const uint32_t minor = format & 0xffffu, major = format >> 16;
  /* Major nought is every snapshot before 1.0.0, a memory dump this build
   * does not migrate; a later major is a break this build predates. */
  if (magic != F3D_SNAPSHOT_MAGIC || major != F3D_SNAPSHOT_MAJOR) return 0;
  if (real_bytes != 4 && real_bytes != 8) return 0;
  /* Where each known section is; the rest are passed over. */
  const uint8_t *found[SECTION_COUNT];
  uint32_t lengths[SECTION_COUNT], versions[SECTION_COUNT];
  for (uint32_t k = 0; k < SECTION_COUNT; k++) {
    found[k] = NULL;
    lengths[k] = versions[k] = 0;
  }
  const uint8_t *at = buffer + HEADER_BYTES;
  const uint8_t *const end = buffer + size;
  for (uint32_t i = 0; i < section_count; i++) {
    if ((size_t)(end - at) < SECTION_HEADER_BYTES) return 0;
    const uint32_t id = get_u32_at(at);
    const uint32_t version = get_u32_at(at + 4);
    const uint32_t length = get_u32_at(at + 8);
    at += SECTION_HEADER_BYTES;
    if ((size_t)(end - at) < length || version == 0) return 0;
    for (uint32_t k = 0; k < SECTION_COUNT; k++) {
      if (kSections[k].id != id) continue;
      if (found[k] != NULL) return 0;
      found[k] = at;
      lengths[k] = length;
      versions[k] = version;
    }
    at += length;
  }
  if (at != end) return 0;
  Io io;
  f3d_zero(&io, sizeof io);
  io.reading = 1;
  io.real_bytes = real_bytes;
  for (uint32_t k = 0; k < SECTION_COUNT; k++) {
    if (found[k] == NULL) {
      /* Missing from a snapshot that should have it: damaged. From an
       * earlier minor, before it was written: empty, as a new world's. */
      if (kSections[k].since_minor <= minor) return 0;
      continue;
    }
    io.at = found[k];
    io.end = found[k] + lengths[k];
    io.version = versions[k];
    kSections[k].io(&io, st);
    if (io.bad) return 0;
  }
  return consistent(st);
}

int f3d_world_restore(F3dWorld *world, const uint8_t *buffer, uint32_t size) {
  if (buffer == NULL) return 0;
  /* Everything read and allocated before anything is replaced, so a
   * restore that is refused or runs out of memory leaves the world as it
   * was. */
  Staged st;
  f3d_zero(&st, sizeof st);
  if (!read_all(buffer, size, &st)) {
    staged_free(&st);
    return 0;
  }
  f3d_free(world->slots);
  f3d_free(world->grid);
  f3d_free(world->events);
  f3d_free(world->manifolds);
  f3d_free(world->hulls);
  f3d_free(world->hull_vertices);
  f3d_free(world->hull_triangles);
  f3d_free(world->meshes);
  f3d_free(world->mesh_vertices);
  f3d_free(world->mesh_triangles);
  f3d_free(world->mesh_edges);
  f3d_free(world->joints);
  f3d_free(world->compounds);
  f3d_free(world->compound_parts);
  f3d_free(world->vehicles);
  f3d_free(world->multibodies);
  f3d_free(world->lumps);
  f3d_free(world->shallows);
  f3d_free(world->shallow_data);
  f3d_free(world->spray);
  f3d_free(world->bubbles);
  f3d_copy(&world->s, &st.s, sizeof st.s);
  world->slots = st.slots;
  world->capacity = st.s.used;
  world->grid = st.grid;
  world->events = st.events;
  world->manifolds = st.manifolds;
  world->manifold_capacity = st.s.manifold_count;
  world->hulls = st.hulls;
  world->hull_vertices = st.hull_vertices;
  world->hull_triangles = st.hull_triangles;
  world->meshes = st.meshes;
  world->mesh_vertices = st.mesh_vertices;
  world->mesh_triangles = st.mesh_triangles;
  world->mesh_edges = st.mesh_edges;
  /* The meshes' trees are built again from them by the next step. */
  f3d_clear_mesh_trees(world);
  world->joints = st.joints;
  world->joint_capacity = st.s.joint_used;
  world->joined_stale = 1;
  world->compounds = st.compounds;
  world->compound_parts = st.compound_parts;
  world->vehicles = st.vehicles;
  world->multibodies = st.multibodies;
  world->lumps = st.lumps;
  world->shallows = st.shallows;
  world->shallow_data = st.shallow_data;
  world->spray = st.spray;
  world->bubbles = st.bubbles;
  /* The tree is not in a snapshot: built again by the next step. */
  f3d_tree_clear(&world->tree);
  f3d_free(world->proxies);
  world->proxies = NULL;
  world->proxy_capacity = 0;
  world->pairs_ready = 0;
  return 1;
}
