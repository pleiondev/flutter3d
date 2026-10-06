/*
 * Vehicles — a chassis on wheels that hang from it on springs, each a ray
 * cast down from where its suspension is fixed.
 *
 * The chassis is an ordinary body: it collides, turns, rolls over, sleeps
 * and goes into a snapshot as any other. The wheels are not bodies. Once a
 * step, after the contacts and before the solver, each wheel casts its ray,
 * and where the ray lands the spring and damper push the chassis up, the
 * drive and brake push it along the road, and the tyre pushes it across to
 * hold it from sliding sideways. All three are forces on the bus at the
 * point the wheel stands on, held over every substep, as a game's own
 * forces are. What the wheel stands on is pushed back, when it moves.
 *
 * The tyre is a friction circle: together its push along and across can be
 * no more than the grip times the spring's force. Asked for more, both are
 * scaled down to the circle and the tyre slides — which is a drift, a
 * wheelspin or a locked brake, and is what [skid] says.
 *
 * Every order here is slot order, and every number is the core's own, so a
 * vehicle steps to the same bits wherever the world does.
 */
#include "f3d_internal.h"

static F3dVec3 turned(F3dMat3 m, F3dVec3 v) {
  return f3d_add(f3d_add(f3d_scale(m.c[0], v.x), f3d_scale(m.c[1], v.y)),
                 f3d_scale(m.c[2], v.z));
}

/* The sine and cosine of [x], the core's own: Taylor's series to the
 * eleventh power on a quarter turn, which holds a float to its last bit
 * there, after [x] is brought into a half turn either side of nought and
 * folded into the quarter. No library call, so every platform agrees. */
void f3d_sin_cos(f3d_real x, f3d_real *sine, f3d_real *cosine) {
  const f3d_real turn = F3D_R(2.0) * F3D_PI;
  if (!(f3d_abs(x) <= F3D_PI)) {
    const f3d_real k = x / turn;
    const f3d_real whole = (f3d_real)(int64_t)(k + (k >= F3D_R(0.0) ? F3D_R(0.5) : F3D_R(-0.5)));
    x -= whole * turn;
  }
  /* Past a quarter turn, from the other side: sin(π − x) = sin x and
   * cos(π − x) = −cos x. */
  f3d_real flip = F3D_R(1.0);
  if (x > F3D_PI / F3D_R(2.0)) {
    x = F3D_PI - x;
    flip = F3D_R(-1.0);
  } else if (x < -F3D_PI / F3D_R(2.0)) {
    x = -F3D_PI - x;
    flip = F3D_R(-1.0);
  }
  const f3d_real x2 = x * x;
  *sine = x * (F3D_R(1.0) -
               x2 / F3D_R(6.0) *
                   (F3D_R(1.0) -
                    x2 / F3D_R(20.0) *
                        (F3D_R(1.0) -
                         x2 / F3D_R(42.0) *
                             (F3D_R(1.0) -
                              x2 / F3D_R(72.0) *
                                  (F3D_R(1.0) - x2 / F3D_R(110.0))))));
  *cosine = flip *
            (F3D_R(1.0) -
             x2 / F3D_R(2.0) *
                 (F3D_R(1.0) -
                  x2 / F3D_R(12.0) *
                      (F3D_R(1.0) -
                       x2 / F3D_R(30.0) *
                           (F3D_R(1.0) -
                            x2 / F3D_R(56.0) *
                                (F3D_R(1.0) - x2 / F3D_R(90.0) *
                                                  (F3D_R(1.0) - x2 / F3D_R(132.0)))))));
}

static F3dVec3 unit(F3dVec3 v) {
  const f3d_real len = f3d_sqrt(f3d_dot(v, v));
  return len > F3D_R(0.0) ? f3d_scale(v, F3D_R(1.0) / len) : v;
}

static F3dVehicleSlot *vehicle_of(const F3dWorld *world, F3dVehicle vehicle) {
  if (vehicle == 0 || vehicle > world->s.vehicle_count) return NULL;
  F3dVehicleSlot *v = &world->vehicles[vehicle - 1u];
  return v->live ? v : NULL;
}

F3dVehicle f3d_vehicle_create(F3dWorld *world, F3dBody chassis, f3d_real ux,
                              f3d_real uy, f3d_real uz, f3d_real fx,
                              f3d_real fy, f3d_real fz) {
  const F3dSlot *s = f3d_slot_of(world, chassis);
  if (s == NULL || s->type != F3D_BODY_DYNAMIC) return 0;
  const F3dVec3 up = f3d_v3(ux, uy, uz), forward = f3d_v3(fx, fy, fz);
  if (!(f3d_finite(ux) && f3d_finite(uy) && f3d_finite(uz) &&
        f3d_finite(fx) && f3d_finite(fy) && f3d_finite(fz))) {
    return 0;
  }
  const f3d_real lu = f3d_dot(up, up), lf = f3d_dot(forward, forward);
  if (!(lu > F3D_R(0.0)) || !(lf > F3D_R(0.0))) return 0;
  const F3dVec3 u = unit(up), f = unit(forward);
  if (f3d_abs(f3d_dot(u, f)) > F3D_R(1e-3)) return 0;
  F3dVehicleSlot *all = (F3dVehicleSlot *)f3d_realloc(
      world->vehicles,
      ((size_t)world->s.vehicle_count + 1u) * sizeof(F3dVehicleSlot));
  if (all == NULL) return 0;
  world->vehicles = all;
  F3dVehicleSlot *v = &all[world->s.vehicle_count];
  f3d_zero(v, sizeof *v);
  v->live = 1;
  v->chassis = chassis;
  v->up = u;
  v->forward = f;
  world->s.vehicle_count++;
  return world->s.vehicle_count;
}

int f3d_vehicle_destroy(F3dWorld *world, F3dVehicle vehicle) {
  F3dVehicleSlot *v = vehicle_of(world, vehicle);
  if (v == NULL) return 0;
  v->live = 0;
  return 1;
}

int f3d_vehicle_is_valid(const F3dWorld *world, F3dVehicle vehicle) {
  const F3dVehicleSlot *v = vehicle_of(world, vehicle);
  return v != NULL && f3d_slot_of(world, v->chassis) != NULL;
}

int f3d_vehicle_add_wheel(F3dWorld *world, F3dVehicle vehicle,
                          const f3d_real *w) {
  F3dVehicleSlot *v = vehicle_of(world, vehicle);
  if (v == NULL || w == NULL || v->wheel_count >= F3D_VEHICLE_MOST_WHEELS) {
    return -1;
  }
  for (uint32_t i = 0; i < F3D_WHEEL_FLOATS; i++) {
    if (!f3d_finite(w[i])) return -1;
  }
  if (w[3] < F3D_R(0.0) || !(w[4] > F3D_R(0.0)) || !(w[5] > F3D_R(0.0)) ||
      w[6] < F3D_R(0.0) || !(w[7] > F3D_R(0.0))) {
    return -1;
  }
  F3dWheel *wheel = &v->wheels[v->wheel_count];
  f3d_zero(wheel, sizeof *wheel);
  wheel->attach = f3d_v3(w[0], w[1], w[2]);
  wheel->rest = w[3];
  wheel->radius = w[4];
  wheel->stiffness = w[5];
  wheel->damping = w[6];
  wheel->grip = w[7];
  wheel->length = wheel->rest;
  return (int)v->wheel_count++;
}

int f3d_vehicle_set_wheel(F3dWorld *world, F3dVehicle vehicle, uint32_t wheel,
                          f3d_real steer, f3d_real drive, f3d_real brake) {
  F3dVehicleSlot *v = vehicle_of(world, vehicle);
  if (v == NULL || wheel >= v->wheel_count) return 0;
  if (!(f3d_finite(steer) && f3d_finite(drive) && f3d_finite(brake)) ||
      brake < F3D_R(0.0)) {
    return 0;
  }
  F3dWheel *w = &v->wheels[wheel];
  w->steer = steer;
  w->drive = drive;
  w->brake = brake;
  F3dSlot *s = f3d_slot_of(world, v->chassis);
  if (s != NULL) f3d_wake(world, s);
  return 1;
}

uint32_t f3d_vehicle_wheel_count(const F3dWorld *world, F3dVehicle vehicle) {
  const F3dVehicleSlot *v = vehicle_of(world, vehicle);
  return v == NULL ? 0u : v->wheel_count;
}

uint32_t f3d_vehicle_read_wheels(const F3dWorld *world, F3dVehicle vehicle,
                                 f3d_real *out, uint32_t capacity) {
  const F3dVehicleSlot *v = vehicle_of(world, vehicle);
  if (v == NULL || out == NULL) return 0;
  uint32_t n = 0;
  for (; n < v->wheel_count && n < capacity; n++) {
    const F3dWheel *w = &v->wheels[n];
    f3d_real *o = out + (size_t)n * F3D_WHEEL_STATE_FLOATS;
    o[0] = w->touching ? F3D_R(1.0) : F3D_R(0.0);
    o[1] = w->length;
    o[2] = w->steer;
    o[3] = w->rotation;
    o[4] = w->spin;
    o[5] = w->centre.x;
    o[6] = w->centre.y;
    o[7] = w->centre.z;
    o[8] = w->normal.x;
    o[9] = w->normal.y;
    o[10] = w->normal.z;
    o[11] = w->force;
    o[12] = w->lateral;
    o[13] = w->skid;
  }
  return n;
}

/* [force] at [point] on [s]: the force, and its turn about the centre. */
static void push_at(F3dSlot *s, F3dVec3 force, F3dVec3 point) {
  s->force = f3d_add(s->force, force);
  s->torque = f3d_add(s->torque, f3d_cross(f3d_sub(point, s->position), force));
}

static F3dVec3 velocity_at(const F3dSlot *s, F3dVec3 point) {
  return f3d_add(s->velocity, f3d_cross(s->spin, f3d_sub(point, s->position)));
}

/* How many times the tyres are solved against each other a step. */
#define F3D_TYRE_ITERATIONS 8

/* A touching wheel, as the tyres' solver reads it. */
typedef struct Tread {
  F3dVec3 point, lever, along, across, ground_velocity;
  F3dSlot *ground;
  /* The spring's force, N, and the most the tyre holds, N s a step. */
  f3d_real spring, most;
  /* The drive's and the brake's impulses a step, N s. */
  f3d_real drive, brake;
  /* What the tyre has pushed with along and across this step, N s; and how
   * much it was asked for before the circle cut it. */
  f3d_real push_along, push_across, asked;
  /* What the brake has held with, inside [brake]. */
  f3d_real braked;
} Tread;

/* The impulse along [n] at the lever [r] that changes the chassis's speed
 * there by one: one over the inverse mass seen at that point. */
static f3d_real mass_along(const F3dSlot *s, F3dSym3 inverse_inertia,
                           F3dVec3 r, F3dVec3 n) {
  const F3dVec3 rn = f3d_cross(r, n);
  const f3d_real k =
      s->inverse_mass + f3d_dot(rn, f3d_sym_times(inverse_inertia, rn));
  return k > F3D_R(0.0) ? F3D_R(1.0) / k : F3D_R(0.0);
}

/* Casts wheel [w]'s ray and, when it lands, fills [t] and puts its spring
 * on the bus; 0 when it hangs. */
static int touch(F3dWorld *world, const F3dVehicleSlot *v, F3dSlot *s,
                 F3dWheel *w, F3dMat3 frame, f3d_real dt, Tread *t) {
  const F3dVec3 up = turned(frame, v->up);
  const F3dVec3 down = f3d_scale(up, F3D_R(-1.0));
  const F3dVec3 origin = f3d_add(s->position, turned(frame, w->attach));
  /* Forward turned by the steering about the up. */
  const F3dVec3 ahead = turned(frame, v->forward);
  const F3dVec3 left = f3d_cross(up, ahead);
  f3d_real sn, cs;
  f3d_sin_cos(w->steer, &sn, &cs);
  const F3dVec3 heading = f3d_add(f3d_scale(ahead, cs), f3d_scale(left, sn));
  F3dBody ground = 0;
  f3d_real hit[F3D_HIT_FLOATS];
  const f3d_real reach = w->rest + w->radius;
  const int touched = f3d_world_ray_cast(
      world, origin.x, origin.y, origin.z, down.x, down.y, down.z, reach,
      s->mask, f3d_handle_of(world, s), &ground, hit);
  w->touching = 0;
  w->force = F3D_R(0.0);
  w->lateral = F3D_R(0.0);
  w->skid = F3D_R(0.0);
  if (!touched) {
    w->length = w->rest;
    w->centre = f3d_madd(origin, down, w->length);
    w->normal = up;
    /* A wheel in the air keeps turning, slowing a little. */
    w->spin *= F3D_R(0.99);
    w->rotation += w->spin * dt;
    return 0;
  }
  const F3dVec3 point = f3d_v3(hit[0], hit[1], hit[2]);
  const F3dVec3 normal = f3d_v3(hit[3], hit[4], hit[5]);
  w->touching = 1;
  w->normal = normal;
  w->length = f3d_max(hit[6] - w->radius, F3D_R(0.0));
  w->centre = f3d_madd(origin, down, w->length);
  f3d_zero(t, sizeof *t);
  t->point = point;
  t->lever = f3d_sub(point, s->position);
  t->ground = f3d_slot_of(world, ground);
  t->ground_velocity = t->ground != NULL ? velocity_at(t->ground, point)
                                         : f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  const F3dVec3 rel = f3d_sub(velocity_at(s, point), t->ground_velocity);
  /* The spring and the damper, along the suspension: never pulling. */
  const f3d_real squeeze = w->rest - w->length;
  const f3d_real closing = -f3d_dot(rel, up);
  t->spring =
      f3d_max(w->stiffness * squeeze + w->damping * closing, F3D_R(0.0));
  w->force = t->spring;
  push_at(s, f3d_scale(up, t->spring), point);
  if (t->ground != NULL && t->ground->type == F3D_BODY_DYNAMIC) {
    push_at(t->ground, f3d_scale(up, -t->spring), point);
    f3d_wake(world, t->ground);
  }
  /* The tyre, in the road's plane. */
  t->along = unit(f3d_sub(heading, f3d_scale(normal, f3d_dot(heading, normal))));
  t->across = f3d_cross(normal, t->along);
  t->most = w->grip * t->spring * dt;
  t->drive = w->drive * dt;
  t->brake = w->brake * dt;
  w->lateral = f3d_dot(rel, t->across);
  return 1;
}

/* Gauss–Seidel over the tyres: each pass, every tyre takes out what is left
 * of its sideways slide and what its brake can stop of its roll, through
 * the chassis's mass and inertia at its point, and the two together are
 * kept inside its friction circle. The drive is pushed whole, in the
 * circle with the rest. The chassis's velocity is a copy here: what the
 * tyres settle on is put on the bus as forces, for the solver. */
static void solve_tyres(F3dSlot *s, Tread *treads, uint32_t n) {
  if (s->inverse_mass == F3D_R(0.0)) return;
  const F3dSym3 inverse_inertia = f3d_sym_turned(s->orientation, s->inverse_inertia);
  F3dVec3 v = s->velocity, w = s->spin;
  for (int pass = 0; pass < F3D_TYRE_ITERATIONS; pass++) {
    for (uint32_t i = 0; i < n; i++) {
      Tread *t = &treads[i];
      const F3dVec3 at = f3d_sub(f3d_add(v, f3d_cross(w, t->lever)), t->ground_velocity);
      /* Sideways: all of it. */
      const f3d_real slide = f3d_dot(at, t->across);
      const f3d_real side = -slide * mass_along(s, inverse_inertia, t->lever, t->across);
      /* Along: the brake stops the roll, never backs it up. */
      const f3d_real roll = f3d_dot(at, t->along);
      const f3d_real stop = -roll * mass_along(s, inverse_inertia, t->lever, t->along);
      const f3d_real braked = f3d_clamp(t->braked + stop, -t->brake, t->brake);
      const f3d_real want_along = t->drive + braked;
      const f3d_real want_across = t->push_across + side;
      const f3d_real asked =
          f3d_sqrt(want_along * want_along + want_across * want_across);
      f3d_real k = F3D_R(1.0);
      if (asked > t->most) k = asked > F3D_R(0.0) ? t->most / asked : F3D_R(0.0);
      const f3d_real along = want_along * k, across = want_across * k;
      const F3dVec3 change = f3d_add(f3d_scale(t->along, along - t->push_along),
                                     f3d_scale(t->across, across - t->push_across));
      v = f3d_madd(v, change, s->inverse_mass);
      w = f3d_add(w, f3d_sym_times(inverse_inertia, f3d_cross(t->lever, change)));
      t->push_along = along;
      t->push_across = across;
      t->braked = braked * k;
      t->asked = asked;
    }
  }
}

void f3d_step_vehicles(F3dWorld *world, f3d_real dt) {
  for (uint32_t i = 0; i < world->s.vehicle_count; i++) {
    F3dVehicleSlot *v = &world->vehicles[i];
    if (!v->live) continue;
    F3dSlot *s = f3d_slot_of(world, v->chassis);
    if (s == NULL) {
      v->live = 0;
      continue;
    }
    if (s->flags & F3D_FLAG_ASLEEP) continue;
    if (v->wheel_count == 0) continue;
    const F3dMat3 frame = f3d_mat_of(s->orientation);
    Tread treads[F3D_VEHICLE_MOST_WHEELS];
    uint32_t wheel_of[F3D_VEHICLE_MOST_WHEELS];
    uint32_t n = 0;
    for (uint32_t k = 0; k < v->wheel_count; k++) {
      if (touch(world, v, s, &v->wheels[k], frame, dt, &treads[n])) {
        wheel_of[n++] = k;
      }
    }
    solve_tyres(s, treads, n);
    for (uint32_t k = 0; k < n; k++) {
      const Tread *t = &treads[k];
      F3dWheel *w = &v->wheels[wheel_of[k]];
      const F3dVec3 force = f3d_scale(
          f3d_add(f3d_scale(t->along, t->push_along),
                  f3d_scale(t->across, t->push_across)),
          F3D_R(1.0) / dt);
      push_at(s, force, t->point);
      if (t->ground != NULL && t->ground->type == F3D_BODY_DYNAMIC) {
        push_at(t->ground, f3d_scale(force, F3D_R(-1.0)), t->point);
        f3d_wake(world, t->ground);
      }
      w->skid = t->asked > t->most && t->most > F3D_R(0.0)
                    ? t->asked / t->most - F3D_R(1.0)
                    : (t->asked > t->most ? F3D_R(1.0) : F3D_R(0.0));
      /* The wheel rolls with the road, unless the brake has it locked. */
      const f3d_real roll = f3d_dot(
          f3d_sub(velocity_at(s, t->point), t->ground_velocity), t->along);
      w->spin = (w->brake > F3D_R(0.0) && w->skid > F3D_R(0.0))
                    ? F3D_R(0.0)
                    : roll / w->radius;
      w->rotation += w->spin * dt;
    }
  }
}
