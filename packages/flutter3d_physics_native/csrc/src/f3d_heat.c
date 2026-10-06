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
      /* A wood fire's continuous flame near 1100 K, a third of its heat
       * radiated, and its gas absorbing 0.8 per metre (Babrauskas). */
      m.flame_temperature = F3D_R(1100.0);
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_R(0.3);
      m.flame_absorption = F3D_R(0.8);
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
      /* A thin, clean flame: as hot as wood's, and seen through hardly
       * glowing. */
      m.flame_temperature = F3D_R(1050.0);
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_R(0.3);
      m.flame_absorption = F3D_R(0.5);
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
      /* A sooty flame: hotter, nearly half its heat radiated, and dark
       * with soot that absorbs a few times what wood's does. */
      m.flame_temperature = F3D_R(1200.0);
      m.flame_convection = F3D_R(25.0);
      m.flame_radiant = F3D_R(0.45);
      m.flame_absorption = F3D_R(2.5);
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
  /* A material that burns has a flame hotter than it catches at. */
  if (m.ignition_temperature > F3D_R(0.0) &&
      !(f3d_finite(m.flame_temperature) &&
        m.flame_temperature > m.ignition_temperature)) {
    return 0;
  }
  if (!in_range(m.flame_convection, F3D_R(0.0), big)) return 0;
  if (!in_range(m.flame_radiant, F3D_R(0.0), F3D_R(1.0))) return 0;
  if (!in_range(m.flame_absorption, F3D_R(0.0), big)) return 0;
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

/* Less than this, W, a body is not worth radiating to: a kilogram of wood
 * it warms by a fifth of a kelvin an hour. It decides how far a source
 * looks, from how strongly it radiates, and nothing else is cut. */
#define F3D_RADIANT_LEAST F3D_R(0.1)
/* How many rays decide how much of a body a source sees past what stands
 * between them: its centre and four points around it. */
#define F3D_RADIANT_RAYS 5u
/* A buoyant plume spreads by this much of its height on each side
 * (Heskestad: b = 0.12 (z − z₀)). */
#define F3D_PLUME_SPREAD F3D_R(0.12)
/* Air's specific heat at constant pressure, J / (kg K). */
#define F3D_AIR_HEAT F3D_R(1005.0)

/* The radius of the ball with a body's surface: what radiation sees of it. */
static f3d_real seen_radius(const F3dSlot *s) {
  return f3d_sqrt(s->surface / (F3D_R(4.0) * F3D_PI));
}

/* The share of everything a point sends out that a ball of radius [r] at
 * [d] from it catches: its solid angle over the whole sphere's. Never more
 * than (r/d)² / 2. */
static f3d_real caught(f3d_real r, f3d_real d) {
  if (d <= r) return F3D_R(0.5);
  const f3d_real s = r / d;
  return F3D_R(0.5) * (F3D_R(1.0) - f3d_sqrt(F3D_R(1.0) - s * s));
}

/* e^(−x) for x ≥ 0, as 1 / (1 + x/256)^256: within a fraction of a per cent
 * for the few metres of flame it is asked about, and the same bits
 * everywhere. */
static f3d_real decay(f3d_real x) {
  f3d_real y = F3D_R(1.0) + f3d_max(x, F3D_R(0.0)) / F3D_R(256.0);
  for (int i = 0; i < 8; i++) y *= y;
  return F3D_R(1.0) / y;
}

/* x^(1/3) and x^(2/5) for x ≥ 0, by Newton's method: the core's own, so the
 * same bits everywhere. */
static f3d_real cube_root(f3d_real x) {
  if (!(x > F3D_R(0.0))) return F3D_R(0.0);
  f3d_real y = x > F3D_R(1.0) ? f3d_sqrt(x) : F3D_R(1.0);
  for (int i = 0; i < 40; i++) y -= (y * y * y - x) / (F3D_R(3.0) * y * y);
  return y;
}

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

/* How long a fire's flame is, m, from the heat it gives off [q], W, over a
 * base of diameter [d], m: Heskestad's L = 0.235·Q^(2/5) − 1.02·D with Q in
 * kW, never shorter than the base. */
static f3d_real flame_length(f3d_real q, f3d_real d) {
  return f3d_max(F3D_R(0.235) * two_fifths(q * F3D_R(1e-3)) - F3D_R(1.02) * d,
                 d);
}

/* What can be heated: a body with a surface and a thermal mass, not a
 * mesh — a level's floor is the room, already the air's temperature it
 * radiates against. */
static int receives(const F3dSlot *s) {
  return s->live && s->shape != F3D_SHAPE_MESH && s->surface > F3D_R(0.0) &&
         capacity_of(s) > F3D_R(0.0);
}

typedef struct Near {
  const F3dWorld *world;
  uint32_t self;
  uint32_t count, capacity;
  uint32_t *slots;
  int failed;
} Near;

static int near_body(void *context, int32_t leaf) {
  Near *n = (Near *)context;
  const uint32_t slot = n->world->tree.nodes[leaf].slot;
  if (slot == n->self) return 1;
  if (n->count == n->capacity) {
    const uint32_t grown = n->capacity == 0 ? 64u : n->capacity * 2u;
    uint32_t *more = (uint32_t *)f3d_realloc(n->slots, (size_t)grown * sizeof(uint32_t));
    if (more == NULL) {
      n->failed = 1;
      return 0;
    }
    n->slots = more;
    n->capacity = grown;
  }
  n->slots[n->count++] = slot;
  return 1;
}

/* How much of [b], a ball of radius [rb], is seen from [a]'s centre past
 * every other body: the share of F3D_RADIANT_RAYS rays that reach it, to
 * its centre and to four points around it at √½ of its radius — the circle
 * that halves the disc it shows. */
static f3d_real seen(F3dWorld *world, const F3dSlot *a, const F3dSlot *b,
                     f3d_real rb) {
  const F3dBody ha = f3d_handle_of(world, a), hb = f3d_handle_of(world, b);
  const F3dVec3 to = f3d_sub(b->position, a->position);
  const f3d_real d = f3d_sqrt(f3d_dot(to, to));
  if (!(d > F3D_R(0.0))) return F3D_R(1.0);
  const F3dVec3 n = f3d_scale(to, F3D_R(1.0) / d);
  /* Two directions across the line, the same however it points. */
  const F3dVec3 helper = f3d_abs(n.y) < F3D_R(0.9)
                             ? f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0))
                             : f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0));
  F3dVec3 e1 = f3d_cross(n, helper);
  e1 = f3d_scale(e1, F3D_R(1.0) / f3d_sqrt(f3d_dot(e1, e1)));
  const F3dVec3 e2 = f3d_cross(n, e1);
  const f3d_real off = F3D_R(0.70710678) * rb;
  const F3dVec3 aims[F3D_RADIANT_RAYS] = {
      b->position, f3d_madd(b->position, e1, off), f3d_madd(b->position, e1, -off),
      f3d_madd(b->position, e2, off), f3d_madd(b->position, e2, -off)};
  uint32_t open = 0;
  for (uint32_t k = 0; k < F3D_RADIANT_RAYS; k++) {
    const F3dVec3 r = f3d_sub(aims[k], a->position);
    const f3d_real len = f3d_sqrt(f3d_dot(r, r));
    if (!(len > F3D_R(0.0))) {
      open++;
      continue;
    }
    const F3dVec3 dir = f3d_scale(r, F3D_R(1.0) / len);
    F3dBody hit[4];
    f3d_real hits[4 * F3D_HIT_FLOATS];
    const uint32_t count = f3d_world_ray_cast_all(
        world, a->position.x, a->position.y, a->position.z, dir.x, dir.y, dir.z,
        len, UINT32_MAX, ha, hit, hits, 4);
    int blocked = 0;
    for (uint32_t h = 0; h < count; h++) {
      if (hit[h] != hb && hit[h] != ha) blocked = 1;
    }
    if (!blocked) open++;
  }
  return (f3d_real)open / (f3d_real)F3D_RADIANT_RAYS;
}

/* Heat across the air between bodies apart, from every body hotter or
 * colder than the air and every fire, to the bodies near it.
 *
 * Every body already gives the air εσA(T⁴ − Tₐ⁴), as if all it saw were at
 * the air's temperature. What it sees of another body is not: that body
 * catches the share of the excess its solid angle is, as much of it as its
 * emissivity takes in, and as much as nothing stands in the way. A burning
 * body's flame sends its material's radiant share of the fire's heat out
 * from its centre the same way. So a body at the air's temperature gives
 * nothing, a cold one draws heat from what sees it, and what is caught was
 * already given up: no heat is made.
 *
 * And a burning body's flame stands on it — a column as wide as the body,
 * spreading as a plume does, as long as Heskestad says and leaning with the
 * wind by the speed of its own buoyancy. A body standing in it is heated by
 * the flame's gas, by its contact and by what the gas radiates, over the
 * share of its ball the column covers up to the half that faces it.
 *
 * A source looks as far as its radiation could still give the largest body
 * F3D_RADIANT_LEAST. Sources in slot order and what they find sorted, so the
 * same world passes the same heat. */
static void radiate(F3dWorld *world, f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  const f3d_real ta4 = ta * ta * ta * ta;
  /* The largest body that can be heated, as radiation sees it. */
  f3d_real largest = F3D_R(0.0);
  for (uint32_t i = 0; i < world->s.used; i++) {
    const F3dSlot *s = &world->slots[i];
    if (receives(s)) largest = f3d_max(largest, seen_radius(s));
  }
  if (!(largest > F3D_R(0.0))) return;
  const f3d_real g2 = f3d_dot(world->s.gravity, world->s.gravity);
  const f3d_real g = f3d_sqrt(g2);
  const F3dVec3 up = g2 > F3D_R(0.0)
                         ? f3d_scale(world->s.gravity, F3D_R(-1.0) / g)
                         : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  Near n;
  n.world = world;
  n.capacity = 0;
  n.slots = NULL;
  n.failed = 0;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *a = &world->slots[i];
    if (!a->live || a->shape == F3D_SHAPE_MESH || !(a->surface > F3D_R(0.0))) {
      continue;
    }
    const F3dMaterial *ma = &a->material;
    const f3d_real t = a->temperature;
    /* What it sends out above the room, and its flame's. */
    const f3d_real excess = ma->emissivity * F3D_STEFAN_BOLTZMANN * a->surface *
                            (t * t * t * t - ta4);
    const int alight = (a->flags & F3D_FLAG_BURNING) != 0;
    const f3d_real flame = alight ? ma->flame_radiant * a->heat_release
                                  : F3D_R(0.0);
    const f3d_real sent = excess + flame;
    const f3d_real ra = seen_radius(a);
    /* The column: Heskestad's length, leaning with the wind where it
     * stands by the buoyant speed (g·Q / (ρ c_p Tₐ D))^(1/3). */
    f3d_real column = F3D_R(0.0);
    F3dVec3 axis = up;
    if (alight && a->heat_release > F3D_R(0.0)) {
      const f3d_real across = F3D_R(2.0) * ra;
      column = flame_length(a->heat_release, across) + ra;
      const f3d_real rise = cube_root(
          g * a->heat_release /
          (world->s.air_density * F3D_AIR_HEAT * ta * across));
      f3d_real wind[3];
      f3d_world_sample_wind(world, a->position.x, a->position.y,
                            a->position.z, wind);
      F3dVec3 blow = f3d_v3(wind[0], wind[1], wind[2]);
      blow = f3d_sub(blow, f3d_scale(up, f3d_dot(blow, up)));
      const F3dVec3 lean = f3d_add(f3d_scale(up, rise), blow);
      const f3d_real len = f3d_sqrt(f3d_dot(lean, lean));
      if (len > F3D_R(0.0)) axis = f3d_scale(lean, F3D_R(1.0) / len);
    }
    if (f3d_abs(sent) < F3D_RADIANT_LEAST && column == F3D_R(0.0)) continue;
    /* caught ≤ (r/d)²/2: past this, the largest body catches less than the
     * least worth sending. */
    const f3d_real far =
        largest * f3d_sqrt(f3d_abs(sent) / (F3D_R(2.0) * F3D_RADIANT_LEAST));
    const f3d_real top = ra + F3D_PLUME_SPREAD * column;
    const f3d_real reach = f3d_max(far, column + top + largest);
    F3dBox box;
    box.lo = f3d_sub(a->position, f3d_v3(reach, reach, reach));
    box.hi = f3d_add(a->position, f3d_v3(reach, reach, reach));
    n.self = i;
    n.count = 0;
    f3d_tree_query(&world->tree, box, near_body, &n);
    if (n.failed) break;
    for (uint32_t p = 1; p < n.count; p++) {
      const uint32_t v = n.slots[p];
      uint32_t q = p;
      while (q > 0 && n.slots[q - 1u] > v) {
        n.slots[q] = n.slots[q - 1u];
        q--;
      }
      n.slots[q] = v;
    }
    const f3d_real flame_e =
        F3D_R(1.0) - decay(ma->flame_absorption * F3D_R(2.0) * ra);
    for (uint32_t k = 0; k < n.count; k++) {
      F3dSlot *b = &world->slots[n.slots[k]];
      if (!receives(b)) continue;
      const F3dVec3 between = f3d_sub(b->position, a->position);
      const f3d_real d = f3d_sqrt(f3d_dot(between, between));
      if (d > reach) continue;
      const f3d_real rb = seen_radius(b);
      /* In the flame. */
      f3d_real inside = F3D_R(0.0);
      if (column > F3D_R(0.0)) {
        const f3d_real along = f3d_clamp(f3d_dot(between, axis), F3D_R(0.0), column);
        const F3dVec3 off = f3d_sub(between, f3d_scale(axis, along));
        const f3d_real apart = f3d_sqrt(f3d_dot(off, off));
        const f3d_real width = ra + F3D_PLUME_SPREAD * along;
        inside = f3d_clamp((width + rb - apart) / (F3D_R(2.0) * rb),
                           F3D_R(0.0), F3D_R(1.0));
      }
      if (inside > F3D_R(0.0) && b->temperature < ma->flame_temperature) {
        const f3d_real cb = capacity_of(b);
        const f3d_real tf = ma->flame_temperature, tb = b->temperature;
        const f3d_real cond =
            (ma->flame_convection + flame_e * b->material.emissivity *
                                        F3D_STEFAN_BOLTZMANN *
                                        (tf * tf + tb * tb) * (tf + tb)) *
            b->surface * F3D_R(0.5) * inside;
        /* Never past the flame in one step. */
        const f3d_real gdt = f3d_min(cond * dt, cb);
        b->heat += gdt * (tf - tb);
      }
      /* From afar, on what is outside the flame. */
      const f3d_real share = b->material.emissivity * caught(rb, d) *
                             (F3D_R(1.0) - inside);
      if (f3d_abs(sent) * share < F3D_RADIANT_LEAST) continue;
      b->heat += sent * share * seen(world, a, b, rb) * dt;
    }
  }
  f3d_free(n.slots);
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
