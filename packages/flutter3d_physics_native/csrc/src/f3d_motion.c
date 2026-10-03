/*
 * How bodies move — P9: shapes as inertia, surface and drag; the wind's
 * drag; semi-implicit Euler for the centre and a momentum-keeping turn for
 * the orientation; and sleep.
 */
#include "f3d_internal.h"

F3dSym3 f3d_sym_turned(F3dQuat q, F3dVec3 d) {
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
  m.xx = r00 * r00 * d.x + r01 * r01 * d.y + r02 * r02 * d.z;
  m.yy = r10 * r10 * d.x + r11 * r11 * d.y + r12 * r12 * d.z;
  m.zz = r20 * r20 * d.x + r21 * r21 * d.y + r22 * r22 * d.z;
  m.xy = r00 * r10 * d.x + r01 * r11 * d.y + r02 * r12 * d.z;
  m.xz = r00 * r20 * d.x + r01 * r21 * d.y + r02 * r22 * d.z;
  m.yz = r10 * r20 * d.x + r11 * r21 * d.y + r12 * r22 * d.z;
  return m;
}

/* The principal moments of [mass] spread evenly through the shape, as
 * flutter3d_physics' inertia.dart has them: a box's m/3 · (b² + c²) with
 * half extents, a sphere's 2/5 m r², and a capsule as a cylinder and two
 * hemispherical caps sharing the mass by volume. */
static F3dVec3 inertia_of(const F3dSlot *s) {
  F3dVec3 out = {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0)};
  const f3d_real m = s->mass;
  if (!(m > F3D_R(0.0))) return out;
  const F3dVec3 d = s->size;
  switch (s->shape) {
    case F3D_SHAPE_SPHERE: {
      const f3d_real i = F3D_R(0.4) * m * d.x * d.x;
      out.x = out.y = out.z = i;
      break;
    }
    case F3D_SHAPE_BOX: {
      const f3d_real third = m / F3D_R(3.0);
      out.x = third * (d.y * d.y + d.z * d.z);
      out.y = third * (d.x * d.x + d.z * d.z);
      out.z = third * (d.x * d.x + d.y * d.y);
      break;
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
      out.x = across;
      out.y = axial;
      out.z = across;
      break;
    }
    default:
      break;
  }
  return out;
}

static f3d_real surface_of(const F3dSlot *s) {
  const F3dVec3 d = s->size;
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
      return F3D_R(4.0) * F3D_PI * d.x * d.x;
    case F3D_SHAPE_BOX:
      return F3D_R(8.0) * (d.x * d.y + d.y * d.z + d.z * d.x);
    case F3D_SHAPE_CAPSULE:
      return F3D_R(4.0) * F3D_PI * d.x * d.x +
             F3D_R(4.0) * F3D_PI * d.x * d.y;
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
    default:
      return F3D_R(0.0);
  }
}

static f3d_real inverted(f3d_real x) {
  return x > F3D_R(0.0) ? F3D_R(1.0) / x : F3D_R(0.0);
}

void f3d_refresh_mass(F3dSlot *s) {
  const int dynamic = s->type == F3D_BODY_DYNAMIC && s->mass > F3D_R(0.0);
  s->inverse_mass = dynamic ? F3D_R(1.0) / s->mass : F3D_R(0.0);
  s->inertia = inertia_of(s);
  if (dynamic && !(s->flags & F3D_FLAG_LOCKED)) {
    s->inverse_inertia.x = inverted(s->inertia.x);
    s->inverse_inertia.y = inverted(s->inertia.y);
    s->inverse_inertia.z = inverted(s->inertia.z);
  } else {
    s->inverse_inertia.x = s->inverse_inertia.y = s->inverse_inertia.z =
        F3D_R(0.0);
  }
  s->surface = surface_of(s);
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

void f3d_step_motion(F3dWorld *world, f3d_real dt) {
  const F3dVec3 g = world->s.gravity;
  const f3d_real rho = world->s.air_density;
  const f3d_real sleep2 = world->s.sleep_speed * world->s.sleep_speed;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    if (s->type != F3D_BODY_DYNAMIC || (s->flags & F3D_FLAG_ASLEEP)) {
      s->force.x = s->force.y = s->force.z = F3D_R(0.0);
      s->torque.x = s->torque.y = s->torque.z = F3D_R(0.0);
      continue;
    }
    const f3d_real im = s->inverse_mass;
    /* The wind's drag, ½ ρ C A |u| u against the velocity u through the
     * air, with A a quarter of the surface: a convex body's projected area
     * averaged over every way it can face, so a tumbling box needs no
     * orientation to say how much wind it catches. Taken implicitly with
     * |u| as the step found it: u' = (u + a dt) / (1 + k dt). Stable for a
     * leaf in a gale at any step, and its fixed point is k u = a exactly,
     * so a falling body settles at its terminal speed and not beside it. */
    f3d_real keep = F3D_R(1.0);
    f3d_real wind[3] = {F3D_R(0.0), F3D_R(0.0), F3D_R(0.0)};
    if (s->surface > F3D_R(0.0) && s->shape_drag > F3D_R(0.0)) {
      f3d_world_sample_wind(world, s->position.x, s->position.y,
                            s->position.z, wind);
      const f3d_real ux = s->velocity.x - wind[0];
      const f3d_real uy = s->velocity.y - wind[1];
      const f3d_real uz = s->velocity.z - wind[2];
      const f3d_real speed = f3d_sqrt(ux * ux + uy * uy + uz * uz);
      const f3d_real k = F3D_R(0.5) * rho * s->shape_drag *
                         (F3D_R(0.25) * s->surface) * speed * im;
      keep = F3D_R(1.0) / (F3D_R(1.0) + k * dt);
    }
    s->velocity.x =
        wind[0] + (s->velocity.x - wind[0] + (g.x + s->force.x * im) * dt) * keep;
    s->velocity.y =
        wind[1] + (s->velocity.y - wind[1] + (g.y + s->force.y * im) * dt) * keep;
    s->velocity.z =
        wind[2] + (s->velocity.z - wind[2] + (g.z + s->force.z * im) * dt) * keep;
    if (s->linear_damping > F3D_R(0.0)) {
      const f3d_real damp = F3D_R(1.0) / (F3D_R(1.0) + dt * s->linear_damping);
      s->velocity.x *= damp;
      s->velocity.y *= damp;
      s->velocity.z *= damp;
    }
    s->position.x += s->velocity.x * dt;
    s->position.y += s->velocity.y * dt;
    s->position.z += s->velocity.z * dt;
    if (s->inverse_inertia.x != F3D_R(0.0) ||
        s->inverse_inertia.y != F3D_R(0.0) ||
        s->inverse_inertia.z != F3D_R(0.0)) {
      F3dVec3 l = s->torque;
      l.x *= dt;
      l.y *= dt;
      l.z *= dt;
      const F3dVec3 dw = f3d_sym_times(
          f3d_sym_turned(s->orientation, s->inverse_inertia), l);
      s->spin.x += dw.x;
      s->spin.y += dw.y;
      s->spin.z += dw.z;
      turn(s, dt);
    }
    s->force.x = s->force.y = s->force.z = F3D_R(0.0);
    s->torque.x = s->torque.y = s->torque.z = F3D_R(0.0);
    /* How long it has been still: slower than the sleep speed, in m/s and
     * in rad/s alike. Spin counts: a body turning on the spot is not at
     * rest. Whether it sleeps is its island's to say, in the collision
     * stage. */
    const f3d_real v2 = s->velocity.x * s->velocity.x +
                        s->velocity.y * s->velocity.y +
                        s->velocity.z * s->velocity.z;
    const f3d_real w2 =
        s->spin.x * s->spin.x + s->spin.y * s->spin.y + s->spin.z * s->spin.z;
    if (v2 > sleep2 || w2 > sleep2) {
      s->still = F3D_R(0.0);
    } else {
      s->still += dt;
    }
  }
}
