/*
 * Vehicles — a chassis on wheels that hang from it on springs, each a ray
 * cast down from where its suspension is fixed.
 *
 * The chassis is an ordinary body: it collides, turns, rolls over, sleeps
 * and goes into a snapshot as any other. The wheels are not bodies. Once a
 * step, after the contacts and before the solver, each wheel casts its ray,
 * and where the ray lands the spring and damper push the chassis up, the
 * drive, the brake and the tyre's rolling resistance push it along the
 * road, and the tyre pushes it across to
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
  return f3d_vehicle_add_wheel_with(world, vehicle, w, F3D_WHEEL_FLOATS);
}

int f3d_vehicle_add_wheel_with(F3dWorld *world, F3dVehicle vehicle,
                               const f3d_real *w, uint32_t count) {
  F3dVehicleSlot *v = vehicle_of(world, vehicle);
  if (v == NULL || w == NULL || v->wheel_count >= F3D_VEHICLE_MOST_WHEELS ||
      count < F3D_WHEEL_FLOATS || count > F3D_WHEEL_FLOATS_ALL) {
    return -1;
  }
  for (uint32_t i = 0; i < count; i++) {
    if (!f3d_finite(w[i])) return -1;
  }
  if (w[3] < F3D_R(0.0) || !(w[4] > F3D_R(0.0)) || !(w[5] > F3D_R(0.0)) ||
      w[6] < F3D_R(0.0) || !(w[7] > F3D_R(0.0))) {
    return -1;
  }
  const f3d_real width = count > 8u ? w[8] : F3D_R(0.0);
  const f3d_real rolling = count > 9u ? w[9] : F3D_R(F3D_WHEEL_ROLLING_DEFAULT);
  if (width < F3D_R(0.0) || rolling < F3D_R(0.0)) return -1;
  F3dWheel *wheel = &v->wheels[v->wheel_count];
  f3d_zero(wheel, sizeof *wheel);
  wheel->attach = f3d_v3(w[0], w[1], w[2]);
  wheel->rest = w[3];
  wheel->radius = w[4];
  wheel->stiffness = w[5];
  wheel->damping = w[6];
  wheel->grip = w[7];
  wheel->width = width > F3D_R(0.0) ? width : F3D_R(F3D_WHEEL_WIDTH_SHARE) * wheel->radius;
  wheel->rolling = rolling;
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

/* The most passes the springs are solved together in a step, and the
 * change in a spring's push, as a share of what it carries, under which
 * they are taken to agree. */
#define F3D_SPRING_PASSES 64
#define F3D_SPRING_AGREED F3D_R(1e-5)

/* A touching wheel, as the tyres' solver reads it. */
typedef struct Tread {
  F3dVec3 point, lever, along, across, up, normal, ground_velocity;
  F3dSlot *ground;
  /* How far the spring is squeezed, m, and its stiffness and damping. */
  f3d_real squeeze, stiffness, damping;
  /* What the spring and damper push with over the step, N s, and the
   * force that is, N. */
  f3d_real lift, spring;
  /* The most the tyre holds, N s a step. */
  f3d_real most;
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

/* Casts wheel [w] down its suspension and, when it lands, fills [t]; 0
 * when it hangs.
 *
 * Two casts: a ray down the wheel's middle, exact on a road, and the wheel
 * itself — a cylinder of its radius on its axle, from fully compressed down
 * through its travel. The ray alone would see a kerb or a plank only where
 * it met it, and one a few centimetres wide not at all when the car crossed
 * it between steps. Where the rim meets something higher than the ray
 * does, the wheel stands on that, along the normal of what it met; else on
 * what the ray found, so a car on a road runs as it would on the ray.
 * Higher means by more than F3D_LINEAR_SLOP, the overlap the solver
 * leaves anything resting: under it, the two say the same of the road. */
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
  int touched = f3d_world_ray_cast(
      world, origin.x, origin.y, origin.z, down.x, down.y, down.z, reach,
      s->mask, f3d_handle_of(world, s), &ground, hit);
  f3d_real length = touched ? f3d_max(hit[6] - w->radius, F3D_R(0.0)) : w->rest;
  F3dVec3 normal = f3d_v3(hit[3], hit[4], hit[5]);
  int on_rim = 0;
  /* The cylinder's axis is its local y: turned onto the axle, the shortest
   * way. */
  const F3dVec3 axle = f3d_cross(up, heading);
  F3dQuat turn = {axle.z, F3D_R(0.0), -axle.x, F3D_R(1.0) + axle.y};
  if (turn.w < F3D_R(1e-6)) {
    turn.x = F3D_R(1.0);
    turn.z = F3D_R(0.0);
    turn.w = F3D_R(0.0);
  }
  F3dBody rim_ground = 0;
  f3d_real rim[F3D_HIT_FLOATS];
  if (f3d_world_cast_shape(
          world, F3D_SHAPE_CYLINDER, w->radius, F3D_R(0.5) * w->width,
          F3D_R(0.0), F3D_R(0.0), origin.x, origin.y, origin.z, turn.x, turn.y,
          turn.z, turn.w, down.x * w->rest, down.y * w->rest, down.z * w->rest,
          s->mask, f3d_handle_of(world, s), &rim_ground, rim)) {
    const f3d_real at = rim[6] * w->rest;
    if (!touched || at < length - F3D_LINEAR_SLOP) {
      touched = 1;
      ground = rim_ground;
      length = at;
      normal = f3d_v3(rim[3], rim[4], rim[5]);
      on_rim = 1;
    }
  }
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
  w->touching = 1;
  w->normal = normal;
  w->length = length;
  w->centre = f3d_madd(origin, down, w->length);
  /* Where the ray landed; or, on the rim, under the wheel's centre along
   * what it met — a flat face meets the cylinder's whole width, and the
   * cast names one end of that line. */
  const F3dVec3 point = on_rim ? f3d_madd(w->centre, normal, -w->radius)
                               : f3d_v3(hit[0], hit[1], hit[2]);
  f3d_zero(t, sizeof *t);
  t->point = point;
  t->lever = f3d_sub(point, s->position);
  t->ground = f3d_slot_of(world, ground);
  t->ground_velocity = t->ground != NULL ? velocity_at(t->ground, point)
                                         : f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
  const F3dVec3 rel = f3d_sub(velocity_at(s, point), t->ground_velocity);
  /* The spring and the damper, along the suspension: solved with the
   * others' in solve_springs. */
  t->up = up;
  t->normal = normal;
  t->squeeze = w->rest - w->length;
  t->stiffness = w->stiffness;
  t->damping = w->damping;
  /* The tyre, in the road's plane. */
  t->along = unit(f3d_sub(heading, f3d_scale(normal, f3d_dot(heading, normal))));
  t->across = f3d_cross(normal, t->along);
  t->drive = w->drive * dt;
  w->lateral = f3d_dot(rel, t->across);
  return 1;
}

/* The springs and dampers of every touching wheel, solved together and
 * implicitly: each pushes with what it will at the step's end, where the
 * chassis has moved under all of them.
 *
 * Spring k and damper c on a squeeze x closing at u, over a step of dt:
 * the force is F = k x' + c u', at the squeeze x' and the closing u' the
 * step ends on. The closing u' is u less what the pushes take out of it
 * through the chassis's mass and inertia at each point — every wheel's
 * push moves every other's point, which is what solves them together, and
 * in a car on four wheels is what has each carry its share of the mass
 * and not all of it. The squeeze the integrator reaches over its n
 * substeps, from a force held through them, is x + dt (β u' + (1 − β) u)
 * with β = (n + 1) / 2n; the share (1 − β) of the spring taken at the
 * step's start is what the substeps take as the position they integrate
 * already, so only the rest, α = (n − 1) / 2n of it, is taken at the end:
 * F = k x + (c + α dt k) u'. That makes a spring with no damper keep its
 * energy exactly, step after step, and the damper take out of each step
 * e^(−2ζω dt) of it to first order, at any dt and any mass: a quarter of
 * a tonne or forty kilograms on the same springs is a damped oscillator of
 * its own frequency and damping ratio, and a damper far past critical on a
 * light chassis is a slow creep back to rest at k / c, not a kick.
 *
 * Projected Gauss–Seidel, the pushes never pulling, until no push changes
 * by F3D_SPRING_AGREED of what it carries, or F3D_SPRING_PASSES. The
 * chassis's velocity is a copy, as the tyres'. */
static void solve_springs(const F3dWorld *world, F3dSlot *s, Tread *treads,
                          uint32_t n, f3d_real dt) {
  const F3dSym3 inverse_inertia = f3d_sym_turned(s->orientation, s->inverse_inertia);
  F3dVec3 v = f3d_madd(s->velocity,
                       f3d_madd(world->s.gravity, s->force, s->inverse_mass), dt);
  F3dVec3 w = f3d_madd(s->spin, f3d_sym_times(inverse_inertia, s->torque), dt);
  const f3d_real substeps = (f3d_real)(world->s.substeps > 0 ? world->s.substeps : 1u);
  const f3d_real alpha = (substeps - F3D_R(1.0)) / (F3D_R(2.0) * substeps);
  f3d_real inverse[F3D_VEHICLE_MOST_WHEELS], soft[F3D_VEHICLE_MOST_WHEELS];
  f3d_real scale = F3D_R(0.0);
  for (uint32_t i = 0; i < n; i++) {
    Tread *t = &treads[i];
    const f3d_real m = mass_along(s, inverse_inertia, t->lever, t->up);
    inverse[i] = m > F3D_R(0.0) ? F3D_R(1.0) / m : F3D_R(0.0);
    soft[i] = dt * (t->damping + alpha * dt * t->stiffness);
    t->lift = F3D_R(0.0);
    scale = f3d_max(scale, m);
  }
  /* What a push of the step's weight on the heaviest point is, N s: the
   * yardstick the passes agree to. */
  const f3d_real agreed = F3D_SPRING_AGREED * scale *
                          f3d_sqrt(f3d_dot(world->s.gravity, world->s.gravity)) * dt;
  for (int pass = 0; pass < F3D_SPRING_PASSES; pass++) {
    f3d_real most = F3D_R(0.0);
    for (uint32_t i = 0; i < n; i++) {
      Tread *t = &treads[i];
      const F3dVec3 at = f3d_sub(f3d_add(v, f3d_cross(w, t->lever)), t->ground_velocity);
      const f3d_real closing = -f3d_dot(at, t->up);
      const f3d_real want =
          (dt * t->stiffness * t->squeeze + soft[i] * closing - t->lift) /
          (F3D_R(1.0) + soft[i] * inverse[i]);
      const f3d_real lift = f3d_max(t->lift + want, F3D_R(0.0));
      const f3d_real change = lift - t->lift;
      t->lift = lift;
      v = f3d_madd(v, t->up, change * s->inverse_mass);
      w = f3d_add(w, f3d_sym_times(inverse_inertia,
                                   f3d_cross(t->lever, f3d_scale(t->up, change))));
      most = f3d_max(most, f3d_abs(change));
    }
    if (most <= agreed) break;
  }
}

/* Gauss–Seidel over the tyres: each pass, every tyre takes out what is left
 * of its sideways slide and what its brake can stop of its roll, through
 * the chassis's mass and inertia at its point, and the two together are
 * kept inside its friction circle. The drive is pushed whole, in the
 * circle with the rest. The chassis's velocity is a copy here: what the
 * tyres settle on is put on the bus as forces, for the solver. The copy
 * is the velocity the step will end on without the tyres — gravity and
 * the springs already on the bus taken in — so a braked car on a slope
 * holds there, rather than creeping down it by a step's pull each step. */
static void solve_tyres(const F3dWorld *world, F3dSlot *s, Tread *treads,
                        uint32_t n, f3d_real dt) {
  if (s->inverse_mass == F3D_R(0.0)) return;
  const F3dSym3 inverse_inertia = f3d_sym_turned(s->orientation, s->inverse_inertia);
  F3dVec3 v = f3d_madd(s->velocity,
                       f3d_madd(world->s.gravity, s->force, s->inverse_mass), dt);
  F3dVec3 w = f3d_madd(s->spin, f3d_sym_times(inverse_inertia, s->torque), dt);
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
    solve_springs(world, s, treads, n, dt);
    /* What the road pushes the wheel with, G, is what the wheel pushes the
     * chassis with: the wheel has no mass to keep any of it. Its strut
     * slides along the up, so the spring sets G's share along the up, and
     * the strut, rigid every other way, passes the rest: G · up = spring.
     * G is the road's load N along its normal n and the tyre's push T in
     * the road's plane, so N = (spring − T · up) / (n · up). A chassis
     * pitched on its springs over a slope is held along the slope's normal,
     * not along its own up, which would lean it on the slope by its pitch;
     * and a wheel meeting a kerb's edge is pushed back by it as well as up.
     * The load first without T, for the tyres' grip; T's share once they
     * have pushed. A road that faces away from the up holds nothing. */
    f3d_real tilt[F3D_VEHICLE_MOST_WHEELS], load[F3D_VEHICLE_MOST_WHEELS];
    for (uint32_t k = 0; k < n; k++) {
      Tread *t = &treads[k];
      const F3dWheel *w = &v->wheels[wheel_of[k]];
      t->spring = t->lift / dt;
      v->wheels[wheel_of[k]].force = t->spring;
      tilt[k] = f3d_dot(t->normal, t->up);
      load[k] = tilt[k] > F3D_R(0.0) ? t->spring / tilt[k] : F3D_R(0.0);
      const F3dVec3 force = f3d_scale(t->normal, load[k]);
      push_at(s, force, t->point);
      if (t->ground != NULL && t->ground->type == F3D_BODY_DYNAMIC) {
        push_at(t->ground, f3d_scale(force, F3D_R(-1.0)), t->point);
        f3d_wake(world, t->ground);
      }
      t->most = w->grip * load[k] * dt;
      /* Rolling resistance: the tyre's flexing under its load takes μ N
       * from its roll, and holds it from rolling up to that, as a brake
       * of μ N does. */
      t->brake = (w->brake + w->rolling * load[k]) * dt;
    }
    solve_tyres(world, s, treads, n, dt);
    for (uint32_t k = 0; k < n; k++) {
      const Tread *t = &treads[k];
      F3dWheel *w = &v->wheels[wheel_of[k]];
      const F3dVec3 push = f3d_scale(
          f3d_add(f3d_scale(t->along, t->push_along),
                  f3d_scale(t->across, t->push_across)),
          F3D_R(1.0) / dt);
      const f3d_real more =
          tilt[k] > F3D_R(0.0) ? -f3d_dot(push, t->up) / tilt[k] : F3D_R(0.0);
      const F3dVec3 force = f3d_madd(push, t->normal, more);
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
