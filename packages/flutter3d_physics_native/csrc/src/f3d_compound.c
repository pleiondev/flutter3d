/*
 * Compound shapes — several shapes on one body: a table's top and legs, a
 * dumbbell, a chair, a hammer. Each part is one of the shapes a body can be,
 * placed and turned in the compound's frame.
 *
 * The parts are one solid of even density: the compound's centre of mass is
 * the parts' by volume, and the parts are moved together so it is at the
 * body's origin, as a hull is. Its inertia is each part's turned into the
 * compound's frame and carried to its centre by the parallel axis theorem.
 * Where parts overlap the overlap is counted twice; a game that cares builds
 * them not to.
 *
 * Contacts are each part's against the other shape — or against each of its
 * parts — through the narrow phase every other shape goes through, and
 * joined into the one manifold a pair of bodies has, along the deepest
 * part's normal: a mesh's triangles are joined the same way. A part whose
 * normal turns more than eighteen degrees from that one waits for the next
 * step, which is what a compound wedged between two faces of one body gives
 * up.
 */
#include "f3d_internal.h"

static int finite3(const f3d_real *v) {
  return f3d_finite(v[0]) && f3d_finite(v[1]) && f3d_finite(v[2]);
}

/* Whether [size] is one a body of [kind] takes, as f3d_body_set_shape
 * checks it. */
static int size_fits(uint32_t kind, F3dVec3 size) {
  const f3d_real a = size.x, b = size.y, c = size.z;
  switch (kind) {
    case F3D_SHAPE_SPHERE:
      return a > F3D_R(0.0);
    case F3D_SHAPE_BOX:
      return a > F3D_R(0.0) && b > F3D_R(0.0) && c > F3D_R(0.0);
    case F3D_SHAPE_CAPSULE:
      return a > F3D_R(0.0) && b >= F3D_R(0.0);
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      return a > F3D_R(0.0) && b > F3D_R(0.0);
    case F3D_SHAPE_HULL:
      return 1;
    default:
      return 0;
  }
}

/* How far a part reaches from its centre: a sphere round it. */
static f3d_real reach_of_part(const F3dWorld *world, uint32_t kind,
                              F3dVec3 size, f3d_real rounding, uint32_t hull) {
  const f3d_real r = size.x, h = size.y;
  f3d_real reach = F3D_R(0.0);
  switch (kind) {
    case F3D_SHAPE_SPHERE:
      reach = r;
      break;
    case F3D_SHAPE_BOX:
      reach = f3d_sqrt(f3d_dot(size, size));
      break;
    case F3D_SHAPE_CAPSULE:
      reach = r + h;
      break;
    case F3D_SHAPE_CYLINDER:
      reach = f3d_sqrt(r * r + h * h);
      break;
    case F3D_SHAPE_CONE: {
      /* Its apex three quarters of the height above the centroid, its rim
       * a quarter below. */
      const f3d_real rim = f3d_sqrt(r * r + F3D_R(0.0625) * h * h);
      reach = f3d_max(F3D_R(0.75) * h, rim);
      break;
    }
    case F3D_SHAPE_HULL: {
      const F3dHull *k = &world->hulls[hull - 1u];
      const F3dVec3 far =
          f3d_v3(f3d_max(f3d_abs(k->lo.x), f3d_abs(k->hi.x)),
                 f3d_max(f3d_abs(k->lo.y), f3d_abs(k->hi.y)),
                 f3d_max(f3d_abs(k->lo.z), f3d_abs(k->hi.z)));
      reach = f3d_sqrt(f3d_dot(far, far));
      break;
    }
    default:
      break;
  }
  return reach + rounding;
}

uint32_t f3d_world_create_compound(F3dWorld *world, const uint32_t *kinds,
                                   const uint32_t *hulls, const f3d_real *parts,
                                   uint32_t count) {
  if (world == NULL || kinds == NULL || parts == NULL || count == 0 ||
      count > F3D_COMPOUND_MOST_PARTS) {
    return 0;
  }
  F3dCompoundPart made[F3D_COMPOUND_MOST_PARTS];
  f3d_real volumes[F3D_COMPOUND_MOST_PARTS];
  f3d_zero(made, sizeof made);
  f3d_real total = F3D_R(0.0);
  F3dVec3 centre = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  for (uint32_t i = 0; i < count; i++) {
    const f3d_real *r = parts + (size_t)i * F3D_COMPOUND_PART_FLOATS;
    F3dCompoundPart *p = &made[i];
    p->kind = kinds[i];
    if (!finite3(r) || !f3d_finite(r[3]) || !finite3(r + 4) ||
        !finite3(r + 7) || !f3d_finite(r[10])) {
      return 0;
    }
    p->size = f3d_v3(r[0], r[1], r[2]);
    p->rounding = r[3];
    if (p->rounding < F3D_R(0.0) || !size_fits(p->kind, p->size)) return 0;
    if (p->kind == F3D_SHAPE_HULL) {
      if (hulls == NULL || hulls[i] == 0 || hulls[i] > world->s.hull_count) {
        return 0;
      }
      p->hull = hulls[i];
      p->size = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    }
    if (p->kind == F3D_SHAPE_SPHERE) p->size.y = p->size.z = F3D_R(0.0);
    if (p->kind == F3D_SHAPE_CAPSULE || p->kind == F3D_SHAPE_CYLINDER ||
        p->kind == F3D_SHAPE_CONE) {
      p->size.z = F3D_R(0.0);
    }
    p->at = f3d_v3(r[4], r[5], r[6]);
    const f3d_real qx = r[7], qy = r[8], qz = r[9], qw = r[10];
    const f3d_real len = f3d_sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
    if (!(len > F3D_R(0.0)) || !f3d_finite(len)) return 0;
    p->turn.x = qx / len;
    p->turn.y = qy / len;
    p->turn.z = qz / len;
    p->turn.w = qw / len;
    volumes[i] = f3d_shape_volume(world, p->kind, p->size, p->rounding, p->hull);
    total += volumes[i];
    centre = f3d_madd(centre, p->at, volumes[i]);
  }
  if (!(total > F3D_R(0.0)) || !f3d_finite(total)) return 0;
  centre = f3d_scale(centre, F3D_R(1.0) / total);
  /* A kilogram of it: each part its share by volume, its own inertia
   * turned into the compound's frame, carried to the centre. */
  F3dCompound c;
  f3d_zero(&c, sizeof c);
  c.unit_inertia = f3d_sym_diag(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  for (uint32_t i = 0; i < count; i++) {
    F3dCompoundPart *p = &made[i];
    p->at = f3d_sub(p->at, centre);
    const f3d_real m = volumes[i] / total;
    const F3dSym3 own = f3d_sym_turned(
        p->turn, f3d_shape_inertia(world, p->kind, p->size, p->rounding,
                                   p->hull, m));
    const F3dVec3 d = p->at;
    const f3d_real dd = f3d_dot(d, d);
    c.unit_inertia.xx += own.xx + m * (dd - d.x * d.x);
    c.unit_inertia.yy += own.yy + m * (dd - d.y * d.y);
    c.unit_inertia.zz += own.zz + m * (dd - d.z * d.z);
    c.unit_inertia.xy += own.xy - m * d.x * d.y;
    c.unit_inertia.xz += own.xz - m * d.x * d.z;
    c.unit_inertia.yz += own.yz - m * d.y * d.z;
    c.surface +=
        f3d_shape_surface(world, p->kind, p->size, p->rounding, p->hull);
    p->reach = reach_of_part(world, p->kind, p->size, p->rounding, p->hull);
    const F3dVec3 lo = f3d_sub(p->at, f3d_v3(p->reach, p->reach, p->reach));
    const F3dVec3 hi = f3d_add(p->at, f3d_v3(p->reach, p->reach, p->reach));
    if (i == 0) {
      c.lo = lo;
      c.hi = hi;
    } else {
      c.lo = f3d_v3(f3d_min(c.lo.x, lo.x), f3d_min(c.lo.y, lo.y),
                    f3d_min(c.lo.z, lo.z));
      c.hi = f3d_v3(f3d_max(c.hi.x, hi.x), f3d_max(c.hi.y, hi.y),
                    f3d_max(c.hi.z, hi.z));
    }
  }
  c.offset = centre;
  c.volume = total;
  c.first_part = world->s.compound_part_count;
  c.part_count = count;
  /* Into the world's arrays, every allocation made before any is kept. */
  F3dCompoundPart *all = (F3dCompoundPart *)f3d_realloc(
      world->compound_parts,
      ((size_t)world->s.compound_part_count + count) * sizeof(F3dCompoundPart));
  if (all == NULL) return 0;
  world->compound_parts = all;
  F3dCompound *compounds = (F3dCompound *)f3d_realloc(
      world->compounds,
      ((size_t)world->s.compound_count + 1u) * sizeof(F3dCompound));
  if (compounds == NULL) return 0;
  world->compounds = compounds;
  f3d_copy(&all[c.first_part], made, (size_t)count * sizeof(F3dCompoundPart));
  f3d_copy(&compounds[world->s.compound_count], &c, sizeof c);
  world->s.compound_part_count += count;
  world->s.compound_count++;
  return world->s.compound_count;
}

int f3d_world_get_compound_offset(const F3dWorld *world, uint32_t compound,
                                  f3d_real *out) {
  if (compound == 0 || compound > world->s.compound_count) return 0;
  const F3dVec3 o = world->compounds[compound - 1u].offset;
  out[0] = o.x;
  out[1] = o.y;
  out[2] = o.z;
  return 1;
}

uint32_t f3d_world_compound_part_count(const F3dWorld *world,
                                       uint32_t compound) {
  if (compound == 0 || compound > world->s.compound_count) return 0;
  return world->compounds[compound - 1u].part_count;
}

int f3d_body_set_compound(F3dWorld *world, F3dBody body, uint32_t compound) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || compound == 0 || compound > world->s.compound_count) {
    return 0;
  }
  s->shape = F3D_SHAPE_COMPOUND;
  s->hull = compound;
  s->size = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  f3d_refresh_mass(world, s);
  s->flags |= F3D_FLAG_MOVED;
  f3d_wake(world, s);
  return 1;
}

F3dPlaced f3d_placed_part(const F3dPlaced *c, uint32_t i) {
  const F3dCompoundPart *part = &c->parts[i];
  F3dPlaced p;
  f3d_zero(&p, sizeof p);
  p.kind = part->kind;
  p.size = part->size;
  /* The body's rounding rounds every part further. */
  p.rounding = part->rounding + c->rounding;
  p.at = f3d_add(c->at, f3d_add(f3d_add(f3d_scale(c->axes.c[0], part->at.x),
                                        f3d_scale(c->axes.c[1], part->at.y)),
                                f3d_scale(c->axes.c[2], part->at.z)));
  const F3dMat3 own = f3d_mat_of(part->turn);
  for (int k = 0; k < 3; k++) {
    p.axes.c[k] = f3d_add(f3d_add(f3d_scale(c->axes.c[0], own.c[k].x),
                                  f3d_scale(c->axes.c[1], own.c[k].y)),
                          f3d_scale(c->axes.c[2], own.c[k].z));
  }
  if (part->kind == F3D_SHAPE_HULL && c->world != NULL) {
    const F3dWorld *world = c->world;
    p.hull = &world->hulls[part->hull - 1u];
    p.vertices = world->hull_vertices + (size_t)p.hull->first_vertex * 3u;
    p.triangles = world->hull_triangles + (size_t)p.hull->first_triangle * 3u;
  }
  return p;
}

/* How many parts a side of a pair has: a compound's, or itself. */
static uint32_t parts_of(const F3dPlaced *p) {
  if (p->kind != F3D_SHAPE_COMPOUND) return 1;
  return p->compound != NULL ? p->compound->part_count : 0;
}

static F3dPlaced part_of(const F3dPlaced *p, uint32_t i) {
  return p->kind == F3D_SHAPE_COMPOUND ? f3d_placed_part(p, i) : *p;
}

/* How far a side reaches from where it stands, or below nought for a side
 * whose reach is not a sphere: a mesh, which the narrow phase culls by its
 * own tree. */
static f3d_real reach_of(const F3dPlaced *side, const F3dPlaced *placed,
                         uint32_t i) {
  if (side->kind == F3D_SHAPE_COMPOUND) {
    return side->parts[i].reach + side->rounding;
  }
  switch (placed->kind) {
    case F3D_SHAPE_SPHERE:
    case F3D_SHAPE_BOX:
    case F3D_SHAPE_CAPSULE:
    case F3D_SHAPE_CYLINDER:
    case F3D_SHAPE_CONE:
      return reach_of_part(NULL, placed->kind, placed->size, placed->rounding,
                           0);
    default:
      return F3D_R(-1.0);
  }
}

uint32_t f3d_collide_compound(const F3dPlaced *a, const F3dPlaced *b,
                              f3d_real margin, F3dManifold *out,
                              F3dManifold *second) {
  out->count = 0;
  if (second != NULL) second->count = 0;
  const uint32_t na = parts_of(a), nb = parts_of(b);
  enum { ROOM = 64 };
  F3dVec3 pts[ROOM], normals[ROOM];
  f3d_real depth[ROOM];
  uint32_t ids[ROOM];
  uint32_t found = 0;
  for (uint32_t i = 0; i < na; i++) {
    const F3dPlaced pa = part_of(a, i);
    const f3d_real ra = reach_of(a, &pa, i);
    for (uint32_t j = 0; j < nb; j++) {
      const F3dPlaced pb = part_of(b, j);
      const f3d_real rb = reach_of(b, &pb, j);
      if (ra >= F3D_R(0.0) && rb >= F3D_R(0.0)) {
        const F3dVec3 d = f3d_sub(pa.at, pb.at);
        const f3d_real most = ra + rb + margin;
        if (f3d_dot(d, d) > most * most) continue;
      }
      /* A part against a mesh may meet two of its faces: both kept, each
       * point with its own face's normal, for the join below. */
      F3dManifold made[F3D_PAIR_MANIFOLDS];
      f3d_zero(made, sizeof made);
      const uint32_t manifolds = f3d_collide_pair(&pa, &pb, margin, made);
      /* The pair of parts in the top byte, so a point keeps its warm start
       * from step to step and two parts' points are not taken for one. */
      const uint32_t parts = ((i * F3D_COMPOUND_MOST_PARTS + j) * 37u + 1u) & 0xFFu;
      for (uint32_t h = 0; h < manifolds; h++) {
        const F3dManifold *tm = &made[h];
        for (uint32_t k = 0; k < tm->count && found < ROOM; k++) {
          pts[found] = tm->points[k].point;
          normals[found] = tm->normal;
          depth[found] = tm->points[k].depth;
          ids[found] = (tm->points[k].id & 0x00FFFFFFu) | (parts << 24);
          found++;
        }
      }
    }
  }
  if (found == 0) return 0;
  f3d_join_points(pts, normals, depth, ids, NULL, found, out, second);
  return out->count;
}
