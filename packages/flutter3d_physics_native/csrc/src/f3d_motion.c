/*
 * How bodies move — P9: shapes as inertia, surface and drag; the wind's
 * drag; semi-implicit Euler for the centre and a momentum-keeping turn for
 * the orientation; and sleep.
 */
#include "f3d_internal.h"

F3dSym3 f3d_sym_turned(F3dQuat q, F3dSym3 t) {
  const f3d_real x = q.x, y = q.y, z = q.z, w = q.w;
  const f3d_real r00 = F3D_R(1.0) - F3D_R(2.0) * (y * y + z * z);
  const f3d_real r01 = F3D_R(2.0) * (x * y - z * w);
  const f3d_real r02 = F3D_R(2.0) * (x * z + y * w);
  const f3d_real r10 = F3D_R(2.0) * (x * y + z * w);
  const f3d_real r11 = F3D_R(1.0) - F3D_R(2.0) * (x * x + z * z);
  const f3d_real r12 = F3D_R(2.0) * (y * z - x * w);
  const f3d_real r20 = F3D_R(2.0) * (x * z - y * w);
  const f3d_real r21 = F3D_R(2.0) * (y * z + x * w);
  const f3d_real r22 = F3D_R(1.0) - F3D_R(2.0) * (x * x + y * y);
  F3dSym3 m;
  if (t.xy == F3D_R(0.0) && t.xz == F3D_R(0.0) && t.yz == F3D_R(0.0)) {
    /* Diagonal, as every shape but a hull is: R · diag(d) · Rᵀ written out,
     * the same arithmetic as before hulls came. */
    const f3d_real dx = t.xx, dy = t.yy, dz = t.zz;
    m.xx = r00 * r00 * dx + r01 * r01 * dy + r02 * r02 * dz;
    m.yy = r10 * r10 * dx + r11 * r11 * dy + r12 * r12 * dz;
    m.zz = r20 * r20 * dx + r21 * r21 * dy + r22 * r22 * dz;
    m.xy = r00 * r10 * dx + r01 * r11 * dy + r02 * r12 * dz;
    m.xz = r00 * r20 * dx + r01 * r21 * dy + r02 * r22 * dz;
    m.yz = r10 * r20 * dx + r11 * r21 * dy + r12 * r22 * dz;
    return m;
  }
  /* R · T, then that times Rᵀ. */
  const f3d_real r[3][3] = {{r00, r01, r02}, {r10, r11, r12}, {r20, r21, r22}};
  const f3d_real tt[3][3] = {
      {t.xx, t.xy, t.xz}, {t.xy, t.yy, t.yz}, {t.xz, t.yz, t.zz}};
  f3d_real rt[3][3];
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      rt[i][j] = r[i][0] * tt[0][j] + r[i][1] * tt[1][j] + r[i][2] * tt[2][j];
    }
  }
  f3d_real o[3][3];
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      o[i][j] = rt[i][0] * r[j][0] + rt[i][1] * r[j][1] + rt[i][2] * r[j][2];
    }
  }
  m.xx = o[0][0];
  m.yy = o[1][1];
  m.zz = o[2][2];
  m.xy = o[0][1];
  m.xz = o[0][2];
  m.yz = o[1][2];
  return m;
}

F3dSym3 f3d_sym_inverse(F3dSym3 m) {
  const f3d_real c00 = m.yy * m.zz - m.yz * m.yz;
  const f3d_real c01 = m.xz * m.yz - m.xy * m.zz;
  const f3d_real c02 = m.xy * m.yz - m.xz * m.yy;
  const f3d_real det = m.xx * c00 + m.xy * c01 + m.xz * c02;
  if (!(det > F3D_R(0.0)) || !f3d_finite(det)) {
    return f3d_sym_diag(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  }
  if (m.xy == F3D_R(0.0) && m.xz == F3D_R(0.0) && m.yz == F3D_R(0.0)) {
    return f3d_sym_diag(F3D_R(1.0) / m.xx, F3D_R(1.0) / m.yy,
                        F3D_R(1.0) / m.zz);
  }
  const f3d_real inv = F3D_R(1.0) / det;
  F3dSym3 o;
  o.xx = c00 * inv;
  o.xy = c01 * inv;
  o.xz = c02 * inv;
  o.yy = (m.xx * m.zz - m.xz * m.xz) * inv;
  o.yz = (m.xy * m.xz - m.xx * m.yz) * inv;
  o.zz = (m.xx * m.yy - m.xy * m.xy) * inv;
  return o;
}

/* A shape's size with its rounding: a rounded box's inertia, surface and
 * drag are taken as the box it rounds out to — the corners it fills are a
 * few per cent of either at the radii a game rounds by. */
static F3dVec3 grown(const F3dSlot *s) {
  const f3d_real r = s->rounding;
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      return f3d_v3(s->size.x + r, F3D_R(0.0), F3D_R(0.0));
    case F3D_SHAPE_CAPSULE:
      return f3d_v3(s->size.x + r, s->size.y, F3D_R(0.0));
    case F3D_SHAPE_CYLINDER:
      return f3d_v3(s->size.x + r, s->size.y + r, F3D_R(0.0));
    case F3D_SHAPE_CONE:
      return f3d_v3(s->size.x + r, s->size.y + r, F3D_R(0.0));
    default:
      return f3d_add(s->size, f3d_v3(r, r, r));
  }
}

/* The inertia tensor of [mass] spread evenly through the shape, about its
 * centre of mass: as flutter3d_physics' inertia.dart has a box's
 * m/3 · (b² + c²) with half extents, a sphere's 2/5 m r², a capsule as a
 * cylinder and two hemispherical caps sharing the mass by volume; a
 * cylinder's ½ m r² about its axis and m (3r² + 4h²)/12 across; a cone's,
 * about its centroid a quarter of its height above the base,
 * 3/10 m r² about its axis and 3/20 m r² + 3/80 m H² across; and a hull's
 * from its tetrahedra, kilogram for kilogram. */
static F3dSym3 inertia_of(const F3dWorld *world, const F3dSlot *s) {
  const f3d_real m = s->mass;
  if (!(m > F3D_R(0.0))) return f3d_sym_diag(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  const F3dVec3 d = grown(s);
  switch (s->shape) {
    case F3D_SHAPE_SPHERE: {
      const f3d_real i = F3D_R(0.4) * m * d.x * d.x;
      return f3d_sym_diag(i, i, i);
    }
    case F3D_SHAPE_BOX: {
      const f3d_real third = m / F3D_R(3.0);
      return f3d_sym_diag(third * (d.y * d.y + d.z * d.z),
                          third * (d.x * d.x + d.z * d.z),
                          third * (d.x * d.x + d.y * d.y));
    }
    case F3D_SHAPE_CAPSULE: {
      const f3d_real r = d.x, h = d.y, r2 = r * r;
      const f3d_real cylinder_volume = F3D_R(2.0) * h * r2;
      const f3d_real caps_volume = F3D_R(4.0) / F3D_R(3.0) * r2 * r;
      const f3d_real cylinder =
          m * cylinder_volume / (cylinder_volume + caps_volume);
      const f3d_real caps = m - cylinder;
      const f3d_real axial =
          cylinder * F3D_R(0.5) * r2 + caps * F3D_R(0.4) * r2;
      const f3d_real across =
          cylinder * (F3D_R(0.25) * r2 + h * h / F3D_R(3.0)) +
          caps * (F3D_R(0.4) * r2 + h * h + F3D_R(0.75) * h * r);
      return f3d_sym_diag(across, axial, across);
    }
    case F3D_SHAPE_CYLINDER: {
      const f3d_real r2 = d.x * d.x, h2 = d.y * d.y;
      const f3d_real across =
          m * (F3D_R(3.0) * r2 + F3D_R(4.0) * h2) / F3D_R(12.0);
      return f3d_sym_diag(across, F3D_R(0.5) * m * r2, across);
    }
    case F3D_SHAPE_CONE: {
      const f3d_real r2 = d.x * d.x, big = d.y * d.y;
      const f3d_real across = m * (F3D_R(3.0) / F3D_R(20.0) * r2 +
                                   F3D_R(3.0) / F3D_R(80.0) * big);
      return f3d_sym_diag(across, F3D_R(0.3) * m * r2, across);
    }
    case F3D_SHAPE_HULL: {
      if (s->hull == 0 || s->hull > world->s.hull_count) break;
      const F3dSym3 u = world->hulls[s->hull - 1u].unit_inertia;
      F3dSym3 o;
      o.xx = u.xx * m;
      o.yy = u.yy * m;
      o.zz = u.zz * m;
      o.xy = u.xy * m;
      o.xz = u.xz * m;
      o.yz = u.yz * m;
      return o;
    }
    default:
      break;
  }
  return f3d_sym_diag(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
}

static f3d_real surface_of(const F3dWorld *world, const F3dSlot *s) {
  const F3dVec3 d = grown(s);
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      return F3D_R(4.0) * F3D_PI * d.x * d.x;
    case F3D_SHAPE_BOX:
      return F3D_R(8.0) * (d.x * d.y + d.y * d.z + d.z * d.x);
    case F3D_SHAPE_CAPSULE:
      return F3D_R(4.0) * F3D_PI * d.x * d.x +
             F3D_R(4.0) * F3D_PI * d.x * d.y;
    case F3D_SHAPE_CYLINDER:
      return F3D_R(2.0) * F3D_PI * d.x * d.x +
             F3D_R(4.0) * F3D_PI * d.x * d.y;
    case F3D_SHAPE_CONE:
      /* The base and the slant: π r² + π r √(r² + H²). */
      return F3D_PI * d.x * d.x +
             F3D_PI * d.x * f3d_sqrt(d.x * d.x + d.y * d.y);
    case F3D_SHAPE_HULL:
      if (s->hull == 0 || s->hull > world->s.hull_count) return F3D_R(0.0);
      return world->hulls[s->hull - 1u].surface;
    case F3D_SHAPE_MESH:
      if (s->hull == 0 || s->hull > world->s.mesh_count) return F3D_R(0.0);
      return world->meshes[s->hull - 1u].surface;
    default:
      return F3D_R(0.0);
  }
}

static f3d_real shape_drag_of(const F3dSlot *s) {
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      return F3D_R(0.47);
    case F3D_SHAPE_BOX:
      return F3D_R(1.05);
    case F3D_SHAPE_CAPSULE:
      return F3D_R(0.6);
    case F3D_SHAPE_CYLINDER:
      return F3D_R(0.82);
    case F3D_SHAPE_CONE:
      return F3D_R(0.5);
    case F3D_SHAPE_HULL:
      return F3D_R(1.0);
    default:
      return F3D_R(0.0);
  }
}

void f3d_refresh_mass(const F3dWorld *world, F3dSlot *s) {
  const int dynamic = s->type == F3D_BODY_DYNAMIC && s->mass > F3D_R(0.0);
  s->inverse_mass = dynamic ? F3D_R(1.0) / s->mass : F3D_R(0.0);
  s->inertia = inertia_of(world, s);
  s->inverse_inertia = dynamic && !(s->flags & F3D_FLAG_LOCKED)
                           ? f3d_sym_inverse(s->inertia)
                           : f3d_sym_diag(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  s->surface = surface_of(world, s);
  s->shape_drag = s->drag > F3D_R(0.0) ? s->drag : shape_drag_of(s);
}

/* Turns the body through one step of its spin, keeping its angular
 * momentum: L = I·ω with the old orientation, the turn
 * q += ½·dt·(ω ⊗ q) and a normalisation, and ω read back out of L with the
 * new one. That is the gyroscopic term of Euler's equations taken
 * implicitly, as RigidBody.integrateOrientation takes it. */
static void turn(F3dSlot *s, f3d_real dt) {
  const f3d_real wx = s->spin.x, wy = s->spin.y, wz = s->spin.z;
  if (wx == F3D_R(0.0) && wy == F3D_R(0.0) && wz == F3D_R(0.0)) return;
  const F3dVec3 l =
      f3d_sym_times(f3d_sym_turned(s->orientation, s->inertia), s->spin);
  const f3d_real x = s->orientation.x, y = s->orientation.y;
  const f3d_real z = s->orientation.z, w = s->orientation.w;
  const f3d_real h = F3D_R(0.5) * dt;
  const f3d_real nx = x + h * (w * wx + wy * z - wz * y);
  const f3d_real ny = y + h * (w * wy + wz * x - wx * z);
  const f3d_real nz = z + h * (w * wz + wx * y - wy * x);
  const f3d_real nw = w - h * (wx * x + wy * y + wz * z);
  const f3d_real length = f3d_sqrt(nx * nx + ny * ny + nz * nz + nw * nw);
  s->orientation.x = nx / length;
  s->orientation.y = ny / length;
  s->orientation.z = nz / length;
  s->orientation.w = nw / length;
  const f3d_real keep = F3D_R(1.0) / (F3D_R(1.0) + dt * s->angular_damping);
  const F3dVec3 o = f3d_sym_times(
      f3d_sym_turned(s->orientation, s->inverse_inertia), l);
  s->spin.x = o.x * keep;
  s->spin.y = o.y * keep;
  s->spin.z = o.z * keep;
}

int f3d_turns(const F3dSlot *s) {
  const F3dSym3 m = s->inverse_inertia;
  return m.xx != F3D_R(0.0) || m.yy != F3D_R(0.0) || m.zz != F3D_R(0.0) ||
         m.xy != F3D_R(0.0) || m.xz != F3D_R(0.0) || m.yz != F3D_R(0.0);
}

void f3d_integrate_velocity(const F3dWorld *world, F3dSlot *s, f3d_real h) {
  const F3dVec3 g = world->s.gravity;
  const f3d_real im = s->inverse_mass;
  /* The wind's drag, ½ ρ C A |u| u against the velocity u through the
   * air, with A a quarter of the surface: a convex body's projected area
   * averaged over every way it can face, so a tumbling box needs no
   * orientation to say how much wind it catches. Taken implicitly with
   * |u| as the substep found it: u' = (u + a h) / (1 + k h). Stable for a
   * leaf in a gale at any step, and its fixed point is k u = a exactly, so
   * a falling body settles at its terminal speed and not beside it. */
  f3d_real keep = F3D_R(1.0);
  f3d_real wind[3] = {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0)};
  if (s->surface > F3D_R(0.0) && s->shape_drag > F3D_R(0.0)) {
    f3d_world_sample_wind(world, s->position.x, s->position.y, s->position.z,
                          wind);
    const f3d_real ux = s->velocity.x - wind[0];
    const f3d_real uy = s->velocity.y - wind[1];
    const f3d_real uz = s->velocity.z - wind[2];
    const f3d_real speed = f3d_sqrt(ux * ux + uy * uy + uz * uz);
    const f3d_real k = F3D_R(0.5) * world->s.air_density * s->shape_drag *
                       (F3D_R(0.25) * s->surface) * speed * im;
    keep = F3D_R(1.0) / (F3D_R(1.0) + k * h);
  }
  s->velocity.x =
      wind[0] + (s->velocity.x - wind[0] + (g.x + s->force.x * im) * h) * keep;
  s->velocity.y =
      wind[1] + (s->velocity.y - wind[1] + (g.y + s->force.y * im) * h) * keep;
  s->velocity.z =
      wind[2] + (s->velocity.z - wind[2] + (g.z + s->force.z * im) * h) * keep;
  if (s->linear_damping > F3D_R(0.0)) {
    const f3d_real damp = F3D_R(1.0) / (F3D_R(1.0) + h * s->linear_damping);
    s->velocity.x *= damp;
    s->velocity.y *= damp;
    s->velocity.z *= damp;
  }
  if (f3d_turns(s)) {
    const F3dVec3 dw = f3d_sym_times(
        f3d_sym_turned(s->orientation, s->inverse_inertia),
        f3d_scale(s->torque, h));
    s->spin = f3d_add(s->spin, dw);
  }
}

/* The most a body turns in one substep, radians: an eighth of a turn, as
 * Box2D v3 holds it (B2_MAX_ROTATION). */
#define F3D_MAX_TURN (F3D_R(0.25) * F3D_PI)

void f3d_integrate_position(F3dSlot *s, f3d_real h) {
  s->position.x += s->velocity.x * h;
  s->position.y += s->velocity.y * h;
  s->position.z += s->velocity.z * h;
  if (!f3d_turns(s)) return;
  /* **No more than an eighth of a turn a substep.** A rod two metres long
   * and two centimetres thick is five thousand times easier to turn about
   * its length than across it, and a contact at its end with friction spins
   * it about its length at thousands of radians a second — which a real
   * pencil also does. Turned tens of radians in a substep, the first-order
   * turn is no turn at all, the momentum read back through that tiny
   * inertia grows, and the rod flew off at hundreds of millions of radians
   * a second. Held to π/4 a substep — 188 rad/s at four substeps of a
   * sixtieth — the turn stays a turn and the spin stays bounded. */
  const f3d_real most = F3D_MAX_TURN / h;
  f3d_real w2 = f3d_dot(s->spin, s->spin);
  if (w2 > most * most) s->spin = f3d_scale(s->spin, most / f3d_sqrt(w2));
  turn(s, h);
  /* And after: the turn reads the spin back out of the momentum through
   * the new orientation, and through a tiny inertia that can be far past
   * what went in. */
  w2 = f3d_dot(s->spin, s->spin);
  if (w2 > most * most) s->spin = f3d_scale(s->spin, most / f3d_sqrt(w2));
}

void f3d_finish_motion(const F3dWorld *world, F3dSlot *s, f3d_real dt) {
  s->force = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  s->torque = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  if (s->type != F3D_BODY_DYNAMIC || (s->flags & F3D_FLAG_ASLEEP)) return;
  /* How long it has been still: slower than the sleep speed, in m/s and in
   * rad/s alike. Spin counts: a body turning on the spot is not at rest.
   * Whether it sleeps is its island's to say, in the collision stage. */
  const f3d_real sleep2 = world->s.sleep_speed * world->s.sleep_speed;
  const f3d_real v2 = f3d_dot(s->velocity, s->velocity);
  const f3d_real w2 = f3d_dot(s->spin, s->spin);
  if (v2 > sleep2 || w2 > sleep2) {
    s->still = F3D_R(0.0);
  } else {
    s->still += dt;
  }
}
