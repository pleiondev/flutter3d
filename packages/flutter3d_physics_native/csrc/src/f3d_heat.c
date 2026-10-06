/*
 * Heat and fire on bodies — P9: what a body is made of, its temperature,
 * the heat and water the bus brings it, and the fire it can carry.
 *
 * A body is one temperature throughout — a lumped mass, which is right
 * while heat crosses it faster than it leaves its surface (a Biot number
 * under a tenth) and is what a game's crate, log or tyre needs. Bodies that
 * touch pass heat across the contact.
 */
#include "f3d_internal.h"

int f3d_material_preset(F3dMaterialKind kind, F3dMaterial *out) {
  F3dMaterial m;
  f3d_zero(&m, sizeof m);
  m.emissivity = F3D_R(0.9);
  m.conductivity = F3D_R(1.0);
  switch (kind) {
    case F3D_MATERIAL_INERT:
      m.specific_heat = F3D_R(1000.0);
      break;
    case F3D_MATERIAL_WOOD:
      /* Pine: piloted ignition near 300 °C, about fifteen megajoules a
       * kilogram, and a burning surface losing about eleven grams a second
       * per square metre. */
      m.specific_heat = F3D_R(1700.0);
      m.conductivity = F3D_R(0.12);
      m.ignition_temperature = F3D_R(573.15);
      m.heat_of_combustion = F3D_R(1.5e7);
      m.burn_rate = F3D_R(0.011);
      m.fuel_fraction = F3D_R(0.8);
      m.flame_feedback = F3D_R(0.3);
      break;
    case F3D_MATERIAL_PAPER:
      /* It catches at 451 °F. */
      m.specific_heat = F3D_R(1340.0);
      m.conductivity = F3D_R(0.05);
      m.ignition_temperature = F3D_R(506.15);
      m.heat_of_combustion = F3D_R(1.6e7);
      m.burn_rate = F3D_R(0.02);
      m.fuel_fraction = F3D_R(0.9);
      m.flame_feedback = F3D_R(0.3);
      break;
    case F3D_MATERIAL_RUBBER:
      m.specific_heat = F3D_R(2010.0);
      m.conductivity = F3D_R(0.16);
      m.emissivity = F3D_R(0.92);
      m.ignition_temperature = F3D_R(623.15);
      m.heat_of_combustion = F3D_R(3.2e7);
      m.burn_rate = F3D_R(0.03);
      m.fuel_fraction = F3D_R(0.9);
      m.flame_feedback = F3D_R(0.3);
      break;
    case F3D_MATERIAL_STEEL:
      /* Weathered, not polished: a polished surface is a tenth of this. */
      m.specific_heat = F3D_R(490.0);
      m.conductivity = F3D_R(50.0);
      m.emissivity = F3D_R(0.6);
      break;
    case F3D_MATERIAL_STONE:
      m.specific_heat = F3D_R(840.0);
      m.conductivity = F3D_R(2.5);
      m.emissivity = F3D_R(0.93);
      break;
    default:
      return 0;
  }
  *out = m;
  return 1;
}

static int in_range(f3d_real x, f3d_real low, f3d_real high) {
  return f3d_finite(x) && x >= low && x <= high;
}

int f3d_body_set_material(F3dWorld *world, F3dBody body,
                          const F3dMaterial *material) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || material == NULL) return 0;
  const F3dMaterial m = *material;
  const f3d_real big = F3D_R(1e30);
  if (!(f3d_finite(m.specific_heat) && m.specific_heat > F3D_R(0.0))) return 0;
  if (!in_range(m.emissivity, F3D_R(0.0), F3D_R(1.0))) return 0;
  if (!in_range(m.ignition_temperature, F3D_R(0.0), big)) return 0;
  if (!in_range(m.heat_of_combustion, F3D_R(0.0), big)) return 0;
  if (!in_range(m.burn_rate, F3D_R(0.0), big)) return 0;
  /* Below one: a body that burnt all of itself would have no mass left to
   * move. */
  if (!(in_range(m.fuel_fraction, F3D_R(0.0), F3D_R(1.0)) &&
        m.fuel_fraction < F3D_R(1.0))) {
    return 0;
  }
  if (!in_range(m.flame_feedback, F3D_R(0.0), F3D_R(1.0))) return 0;
  if (!(f3d_finite(m.conductivity) && m.conductivity > F3D_R(0.0))) return 0;
  s->material = m;
  s->fuel = s->mass * m.fuel_fraction;
  if (s->fuel <= F3D_R(0.0) || m.ignition_temperature <= F3D_R(0.0)) {
    s->flags &= (uint8_t)~F3D_FLAG_BURNING;
    s->heat_release = F3D_R(0.0);
  }
  return 1;
}

int f3d_body_set_temperature(F3dWorld *world, F3dBody body, f3d_real kelvin) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(kelvin) && kelvin > F3D_R(0.0))) return 0;
  s->temperature = kelvin;
  return 1;
}

int f3d_body_get_temperature(const F3dWorld *world, F3dBody body,
                             f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->temperature;
  return 1;
}

int f3d_body_add_heat(F3dWorld *world, F3dBody body, f3d_real joules) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !f3d_finite(joules)) return 0;
  s->heat += joules;
  return 1;
}

int f3d_body_add_water(F3dWorld *world, F3dBody body, f3d_real kg) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !f3d_finite(kg)) return 0;
  if (kg > F3D_R(0.0)) {
    /* It lands at the air's temperature and mixes with what is there:
     * counted at the body's own, it would bring heat from nowhere. Taken
     * off, it leaves at the body's, and the body's temperature stays. */
    const f3d_real body_heat =
        s->mass * s->material.specific_heat + s->water * F3D_WATER_HEAT;
    const f3d_real added = kg * F3D_WATER_HEAT;
    s->temperature = (body_heat * s->temperature +
                      added * world->s.air_temperature) /
                     (body_heat + added);
  }
  s->water = f3d_max(s->water + kg, F3D_R(0.0));
  return 1;
}

int f3d_body_get_water(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->water;
  return 1;
}

int f3d_body_get_fuel(const F3dWorld *world, F3dBody body, f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->fuel;
  return 1;
}

int f3d_body_is_burning(const F3dWorld *world, F3dBody body, int *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = (s->flags & F3D_FLAG_BURNING) != 0;
  return 1;
}

int f3d_body_get_heat_release(const F3dWorld *world, F3dBody body,
                              f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->heat_release;
  return 1;
}

/* W / (m² K) from a surface to air moving past it at [u] m/s: Watson's
 * correlation, 10.45 − u + 10 √u, the one wind chill was built on. It is
 * measured from still air to twenty metres a second, so it is held there:
 * past that it would start to fall. */
static f3d_real convection(f3d_real u) {
  const f3d_real v = f3d_min(f3d_max(u, F3D_R(0.0)), F3D_R(20.0));
  return F3D_R(10.45) - v + F3D_R(10.0) * f3d_sqrt(v);
}

/* J/K the body holds: its own and its water's. */
static f3d_real capacity_of(const F3dSlot *s) {
  return s->mass * s->material.specific_heat + s->water * F3D_WATER_HEAT;
}

/* How big a body is where it touches: a ball's radius, a capsule's, a
 * box's least half extent. */
static f3d_real radius_of(const F3dSlot *s) {
  switch (s->shape) {
    case F3D_SHAPE_SPHERE:
    case F3D_SHAPE_CAPSULE:
      return s->size.x;
    case F3D_SHAPE_BOX:
      return f3d_min(s->size.x, f3d_min(s->size.y, s->size.z));
    default:
      return F3D_R(0.0);
  }
}

/* Twice the area of the polygon a, b, c, d in that order, seen along n. */
static f3d_real quad2(F3dVec3 a, F3dVec3 b, F3dVec3 c, F3dVec3 d, F3dVec3 n) {
  return f3d_abs(f3d_dot(f3d_cross(f3d_sub(c, a), f3d_sub(d, b)), n));
}

/* The area two bodies touch over, m². A face resting on a face touches over
 * the polygon its points span — of four points in whatever order, the
 * largest of the three ways round is the convex one. A curved body pressed
 * in by δ touches over Hertz's circle of radius √(Rδ), and two points of a
 * line touch over its length by that circle's width. */
static f3d_real contact_area(const F3dManifold *m, f3d_real r) {
  f3d_real depth = F3D_R(0.0);
  for (uint32_t i = 0; i < m->count; i++) {
    depth = f3d_max(depth, m->points[i].depth);
  }
  const f3d_real pressed = r * depth;
  const F3dVec3 n = m->normal;
  const F3dContactPoint *p = m->points;
  f3d_real area = F3D_PI * pressed;
  if (m->count == 2) {
    const F3dVec3 d = f3d_sub(p[1].point, p[0].point);
    area = f3d_max(area, f3d_sqrt(f3d_dot(d, d)) * F3D_R(2.0) *
                             f3d_sqrt(pressed));
  } else if (m->count == 3) {
    area = f3d_max(area, F3D_R(0.5) * f3d_abs(f3d_dot(
                             f3d_cross(f3d_sub(p[1].point, p[0].point),
                                       f3d_sub(p[2].point, p[0].point)),
                             n)));
  } else if (m->count == 4) {
    const f3d_real a = quad2(p[0].point, p[1].point, p[2].point, p[3].point, n);
    const f3d_real b = quad2(p[0].point, p[1].point, p[3].point, p[2].point, n);
    const f3d_real c = quad2(p[0].point, p[2].point, p[1].point, p[3].point, n);
    area = f3d_max(area, F3D_R(0.5) * f3d_max(a, f3d_max(b, c)));
  }
  return area;
}

/* Heat across every contact that touches. The conductance is Holm's
 * constriction of two bodies meeting over a spot of radius a,
 * G = 4a / (1/k₁ + 1/k₂), with a the radius of a circle of the contact's
 * area; and the exchange is taken implicitly for the pair, so it carries
 * them towards one temperature and never past it. In key order, so the
 * same world passes the same heat. */
static void conduct(F3dWorld *world, f3d_real dt) {
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    const F3dManifold *m = &world->manifolds[i];
    if (!m->touching) continue;
    F3dSlot *a = f3d_slot_of(world, m->a);
    F3dSlot *b = f3d_slot_of(world, m->b);
    if (a == NULL || b == NULL) continue;
    const f3d_real ca = capacity_of(a), cb = capacity_of(b);
    /* No thermal mass: a fixed one is a reservoir, and nothing else can
     * have none. */
    const f3d_real ia = ca > F3D_R(0.0) ? F3D_R(1.0) / ca : F3D_R(0.0);
    const f3d_real ib = cb > F3D_R(0.0) ? F3D_R(1.0) / cb : F3D_R(0.0);
    if (ia == F3D_R(0.0) && ib == F3D_R(0.0)) continue;
    const f3d_real ra = radius_of(a), rb = radius_of(b);
    const f3d_real r = ra > F3D_R(0.0) && rb > F3D_R(0.0)
                           ? ra * rb / (ra + rb)
                           : f3d_max(ra, rb);
    const f3d_real area = contact_area(m, r);
    if (!(area > F3D_R(0.0))) continue;
    const f3d_real spot = f3d_sqrt(area / F3D_PI);
    const f3d_real g =
        F3D_R(4.0) * spot /
        (F3D_R(1.0) / a->material.conductivity +
         F3D_R(1.0) / b->material.conductivity);
    const f3d_real gdt = g * dt;
    const f3d_real q = gdt * (b->temperature - a->temperature) /
                       (F3D_R(1.0) + gdt * (ia + ib));
    a->temperature += q * ia;
    b->temperature -= q * ib;
  }
}

/* A body counts as a source of radiation to its neighbours this far above
 * the air, K, or burning: below it the exchange is lost in convection. */
#define F3D_RADIANT_ABOVE_AIR F3D_R(30.0)
/* The share of a fire's heat that leaves it as radiation rather than in
 * the hot gas: about a third for wood and paper. */
#define F3D_FLAME_RADIANT F3D_R(0.3)
/* Neighbours are looked for this many of a source's own radii away, and
 * never further than F3D_RADIANT_MOST, m. */
#define F3D_RADIANT_RADII F3D_R(12.0)
#define F3D_RADIANT_MOST F3D_R(6.0)
#define F3D_RADIANT_NEIGHBOURS 64u

/* The radius of the ball with a body's surface: what radiation sees of it. */
static f3d_real seen_radius(const F3dSlot *s) {
  return f3d_sqrt(s->surface / (F3D_R(4.0) * F3D_PI));
}

/* The share of everything a point sends out that a ball of radius [r] at
 * [d] from it catches: its solid angle over the whole sphere's. */
static f3d_real caught(f3d_real r, f3d_real d) {
  if (d <= r) return F3D_R(0.5);
  const f3d_real s = r / d;
  return F3D_R(0.5) * (F3D_R(1.0) - f3d_sqrt(F3D_R(1.0) - s * s));
}

typedef struct Near {
  const F3dWorld *world;
  uint32_t self;
  uint32_t count;
  uint32_t slots[F3D_RADIANT_NEIGHBOURS];
} Near;

static int near_body(void *context, int32_t leaf) {
  Near *n = (Near *)context;
  const uint32_t slot = n->world->tree.nodes[leaf].slot;
  if (slot != n->self && n->count < F3D_RADIANT_NEIGHBOURS) {
    n->slots[n->count++] = slot;
  }
  return 1;
}

/* The gas of a fire's continuous flame, K, and what it passes to a surface
 * standing in it, W/(m² K). */
#define F3D_FLAME_TEMPERATURE F3D_R(1100.0)
#define F3D_FLAME_CONVECTION F3D_R(25.0)

/* How strongly a wood fire's flame absorbs, per m of flame it is seen
 * through: its emissivity is 1 − e^(−κL). */
#define F3D_FLAME_ABSORPTION F3D_R(0.8)

/* e^(−x) for x ≥ 0, as 1 / (1 + x/256)^256: within a fraction of a per cent
 * for the few metres of flame it is asked about, and the same bits
 * everywhere. */
static f3d_real decay(f3d_real x) {
  f3d_real y = F3D_R(1.0) + f3d_max(x, F3D_R(0.0)) / F3D_R(256.0);
  for (int i = 0; i < 8; i++) y *= y;
  return F3D_R(1.0) / y;
}

/* x^(2/5) for x ≥ 0, by Newton's method on y⁵ = x²: the core's own, so the
 * same bits everywhere. */
static f3d_real two_fifths(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  const f3d_real x2 = x * x;
  f3d_real y = f3d_sqrt(f3d_sqrt(x));
  for (int i = 0; i < 12; i++) {
    const f3d_real y4 = y * y * y * y;
    y -= (y4 * y - x2) / (F3D_R(5.0) * y4);
  }
  return y;
}

/* How tall a fire's flame stands above what burns, m, from the heat it
 * gives off [q], W, over a base of diameter [d], m: Heskestad's
 * L = 0.235·Q^(2/5) − 1.02·D with Q in kW, never shorter than the base. */
static f3d_real flame_length(f3d_real q, f3d_real d) {
  return f3d_max(F3D_R(0.235) * two_fifths(q * F3D_R(1e-3)) - F3D_R(1.02) * d,
                 d);
}

static int is_source(const F3dSlot *s, f3d_real ta) {
  return (s->flags & F3D_FLAG_BURNING) ||
         s->temperature > ta + F3D_RADIANT_ABOVE_AIR;
}

/* Heat across the air between bodies apart, from every hot or burning one
 * to the bodies near it. Two parts:
 *
 * - their surfaces, as grey balls of their own surface's area:
 *   εᵢεⱼσ·AᵢFᵢⱼ·(Tᵢ⁴ − Tⱼ⁴), with Fᵢⱼ the share of i's sky j fills, and
 *   AᵢFᵢⱼ taken as the smaller of the two ways round so the exchange is the
 *   same from either side. Like conduction it is a conductance times the
 *   difference, taken implicitly for the pair, so it never carries one
 *   past the other;
 * - a burning body's flame: F3D_FLAME_RADIANT of the heat its fire gave
 *   off the step before leaves as radiation from its centre, and each
 *   neighbour catches its solid angle's share of it, as much as its
 *   emissivity takes in. That is what sets a crate beside a fire alight.
 *
 * Nothing stands in the way: a wall between two bodies does not shade one
 * from the other. Sources in slot order and their neighbours sorted, so
 * the same world passes the same heat; a pair of two sources is taken once,
 * from the lower slot. */
static void radiate(F3dWorld *world, f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *a = &world->slots[i];
    if (!a->live || !(a->surface > F3D_R(0.0)) || !is_source(a, ta)) continue;
    const f3d_real ra = seen_radius(a);
    const int alight = (a->flags & F3D_FLAG_BURNING) != 0;
    const f3d_real flame = alight ? F3D_FLAME_RADIANT * a->heat_release
                                  : F3D_R(0.0);
    /* The flame: a column that wraps the source, a fifth wider than it at
     * its centre and spreading as a plume does, a fifth of its height on
     * each side, up against gravity for as tall as Heskestad says above
     * the source's top. */
    const f3d_real g2 = f3d_dot(world->s.gravity, world->s.gravity);
    const F3dVec3 up = g2 > F3D_R(0.0)
                           ? f3d_scale(world->s.gravity, F3D_R(-1.0) / f3d_sqrt(g2))
                           : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
    const f3d_real tall =
        alight ? flame_length(a->heat_release, F3D_R(2.0) * ra) : F3D_R(0.0);
    const F3dVec3 base = a->position;
    const f3d_real column = alight ? tall + ra : F3D_R(0.0);
    const f3d_real wrap = F3D_R(1.2) * ra;
    /* What the flame radiates into what stands in it: its gas seen
     * through its own width. */
    const f3d_real flame_e =
        F3D_R(1.0) - decay(F3D_FLAME_ABSORPTION * F3D_R(2.0) * wrap);
    const f3d_real reach = f3d_max(
        f3d_min(F3D_RADIANT_RADII * f3d_max(ra, F3D_R(0.25)), F3D_RADIANT_MOST),
        column + F3D_R(2.0) * wrap);
    F3dBox box;
    box.lo = f3d_sub(a->position, f3d_v3(reach, reach, reach));
    box.hi = f3d_add(a->position, f3d_v3(reach, reach, reach));
    Near n;
    n.world = world;
    n.self = i;
    n.count = 0;
    f3d_tree_query(&world->tree, box, near_body, &n);
    /* Sorted, so the tree's shape does not decide the order. */
    for (uint32_t p = 1; p < n.count; p++) {
      const uint32_t v = n.slots[p];
      uint32_t q = p;
      while (q > 0 && n.slots[q - 1u] > v) {
        n.slots[q] = n.slots[q - 1u];
        q--;
      }
      n.slots[q] = v;
    }
    for (uint32_t k = 0; k < n.count; k++) {
      F3dSlot *b = &world->slots[n.slots[k]];
      if (!b->live || !(b->surface > F3D_R(0.0))) continue;
      const F3dVec3 between = f3d_sub(b->position, a->position);
      const f3d_real d = f3d_sqrt(f3d_dot(between, between));
      if (d > reach) continue;
      const f3d_real rb = seen_radius(b);
      /* Standing in the flame: the share of its ball the column covers,
       * up to the half that faces it, heated by the flame's gas and by
       * what that gas radiates. Taken so a step never carries it past the
       * flame's temperature. */
      f3d_real inside = F3D_R(0.0);
      if (alight) {
        const F3dVec3 rel = f3d_sub(b->position, base);
        const f3d_real along = f3d_clamp(f3d_dot(rel, up), F3D_R(0.0), column);
        const F3dVec3 off = f3d_sub(rel, f3d_scale(up, along));
        const f3d_real apart = f3d_sqrt(f3d_dot(off, off));
        const f3d_real width = wrap + F3D_R(0.2) * along;
        inside = f3d_clamp((width + rb - apart) / (F3D_R(2.0) * rb),
                           F3D_R(0.0), F3D_R(1.0));
      }
      if (inside > F3D_R(0.0) && b->temperature < F3D_FLAME_TEMPERATURE) {
        const f3d_real cb = capacity_of(b);
        const f3d_real tf = F3D_FLAME_TEMPERATURE, tb = b->temperature;
        const f3d_real g =
            (F3D_FLAME_CONVECTION + flame_e * b->material.emissivity *
                                        F3D_STEFAN_BOLTZMANN *
                                        (tf * tf + tb * tb) * (tf + tb)) *
            b->surface * F3D_R(0.5) * inside;
        const f3d_real gdt = cb > F3D_R(0.0) ? f3d_min(g * dt, cb) : g * dt;
        b->heat += gdt * (tf - tb);
      }
      /* The rest of it, outside the flame, sees the fire from afar. */
      if (flame > F3D_R(0.0)) {
        b->heat += flame * caught(rb, d) * (F3D_R(1.0) - inside) *
                   b->material.emissivity * dt;
      }
      /* A pair of two sources is the lower slot's to take. */
      if (is_source(b, ta) && n.slots[k] < i) continue;
      const f3d_real ca = capacity_of(a), cb = capacity_of(b);
      const f3d_real ia = ca > F3D_R(0.0) ? F3D_R(1.0) / ca : F3D_R(0.0);
      const f3d_real ib = cb > F3D_R(0.0) ? F3D_R(1.0) / cb : F3D_R(0.0);
      if (ia == F3D_R(0.0) && ib == F3D_R(0.0)) continue;
      const f3d_real view = f3d_min(a->surface * caught(rb, d),
                                    b->surface * caught(ra, d));
      const f3d_real t1 = a->temperature, t2 = b->temperature;
      const f3d_real g = a->material.emissivity * b->material.emissivity *
                         F3D_STEFAN_BOLTZMANN * view *
                         (t1 * t1 + t2 * t2) * (t1 + t2);
      const f3d_real gdt = g * dt;
      const f3d_real q = gdt * (t2 - t1) / (F3D_R(1.0) + gdt * (ia + ib));
      a->temperature += q * ia;
      b->temperature -= q * ib;
    }
  }
}

void f3d_step_heat(F3dWorld *world, f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  conduct(world, dt);
  radiate(world, dt);
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    const F3dMaterial *m = &s->material;
    f3d_real power = s->heat / dt;
    s->heat = F3D_R(0.0);
    s->heat_release = F3D_R(0.0);
    /* The fire: a burning surface loses mass at the burn rate, the mass
     * releases its heat of combustion, and the flame's share of that goes
     * back into the body; the rest leaves as hot gas. The mass leaves at
     * the body's velocity, so the velocity does not change. */
    if (s->flags & F3D_FLAG_BURNING) {
      const f3d_real burnt =
          f3d_min(m->burn_rate * s->surface * dt, s->fuel);
      const f3d_real released = burnt * m->heat_of_combustion / dt;
      power += m->flame_feedback * released;
      s->heat_release = (F3D_R(1.0) - m->flame_feedback) * released;
      s->fuel -= burnt;
      s->mass -= burnt;
      f3d_refresh_mass(world, s);
      if (s->fuel <= F3D_R(0.0)) {
        s->fuel = F3D_R(0.0);
        s->flags &= (uint8_t)~F3D_FLAG_BURNING;
        f3d_push_event(world, f3d_handle_of(world, s), F3D_EVENT_BURNT_OUT);
      }
    }
    const f3d_real dry = s->mass * m->specific_heat;
    const f3d_real capacity = dry + s->water * F3D_WATER_HEAT;
    if (!(capacity > F3D_R(0.0))) continue;
    /* What the surface gives the air: convection to the air moving past
     * it, and radiation εσ(T⁴ − Tₐ⁴), written exactly as
     * εσ(T² + Tₐ²)(T + Tₐ)·(T − Tₐ) so both are a conductance times the
     * difference. Taken implicitly with the conductance as it is, the
     * step cannot overshoot the air's temperature, however small the body
     * or long the step. */
    f3d_real conductance = F3D_R(0.0);
    if (s->surface > F3D_R(0.0)) {
      f3d_real wind[3];
      f3d_world_sample_wind(world, s->position.x, s->position.y,
                            s->position.z, wind);
      const f3d_real ux = s->velocity.x - wind[0];
      const f3d_real uy = s->velocity.y - wind[1];
      const f3d_real uz = s->velocity.z - wind[2];
      const f3d_real u = f3d_sqrt(ux * ux + uy * uy + uz * uz);
      const f3d_real t = s->temperature;
      conductance = s->surface *
                    (convection(u) + m->emissivity * F3D_STEFAN_BOLTZMANN *
                                         (t * t + ta * ta) * (t + ta));
    }
    f3d_real next = (capacity * s->temperature + dt * (power + conductance * ta)) /
                    (capacity + dt * conductance);
    /* Water on the body holds it at its boiling point: what would heat
     * the body past it boils water off instead, and only once the water
     * has gone does the body heat on. */
    if (s->water > F3D_R(0.0) && next > F3D_WATER_BOILS) {
      const f3d_real excess = (next - F3D_WATER_BOILS) * capacity;
      const f3d_real boils = excess / F3D_WATER_LATENT;
      if (boils < s->water) {
        s->water -= boils;
        next = F3D_WATER_BOILS;
      } else {
        const f3d_real left = excess - s->water * F3D_WATER_LATENT;
        s->water = F3D_R(0.0);
        next = dry > F3D_R(0.0) ? F3D_WATER_BOILS + left / dry
                                : F3D_WATER_BOILS;
      }
    }
    s->temperature = f3d_max(next, F3D_R(1e-3));
    /* Alight at the ignition temperature, out below it. A wet body is held
     * at boiling, below any ignition temperature here, so water puts a fire
     * out and keeps a wet body from catching. */
    const f3d_real ignition = m->ignition_temperature;
    if (ignition <= F3D_R(0.0)) continue;
    if (s->flags & F3D_FLAG_BURNING) {
      if (s->temperature < ignition) {
        s->flags &= (uint8_t)~F3D_FLAG_BURNING;
        f3d_push_event(world, f3d_handle_of(world, s),
                       F3D_EVENT_EXTINGUISHED);
      }
    } else if (s->fuel > F3D_R(0.0) && s->water <= F3D_R(0.0) &&
               s->temperature >= ignition) {
      s->flags |= F3D_FLAG_BURNING;
      f3d_push_event(world, f3d_handle_of(world, s), F3D_EVENT_IGNITED);
    }
  }
}
