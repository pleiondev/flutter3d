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

static f3d_real capacity_of(const F3dSlot *s);
static int ensure_lumps(F3dWorld *world);
static void body_from_lumps(F3dWorld *world, F3dSlot *s);

/* A compound's parts' heat, made now if it has none yet; null for any
 * other body, or when memory ran out. */
static F3dLump *lumps_of(F3dWorld *world, F3dSlot *s) {
  if (s->shape != F3D_SHAPE_COMPOUND) return NULL;
  if (!ensure_lumps(world) || s->lumps == 0) return NULL;
  return &world->lumps[s->lumps - 1u];
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
  const int burns = m.ignition_temperature > F3D_R(0.0);
  F3dLump *l = lumps_of(world, s);
  for (uint32_t i = 0; l != NULL && i < s->lump_count; i++) {
    l[i].fuel = l[i].mass * m.fuel_fraction;
    if (l[i].fuel <= F3D_R(0.0) || !burns) {
      l[i].burning = 0;
      l[i].heat_release = F3D_R(0.0);
    }
  }
  if (l != NULL) {
    body_from_lumps(world, s);
    return 1;
  }
  s->fuel = s->mass * m.fuel_fraction;
  if (s->fuel <= F3D_R(0.0) || !burns) {
    s->flags &= (uint8_t)~F3D_FLAG_BURNING;
    s->heat_release = F3D_R(0.0);
  }
  return 1;
}

int f3d_body_set_temperature(F3dWorld *world, F3dBody body, f3d_real kelvin) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(kelvin) && kelvin > F3D_R(0.0))) return 0;
  F3dLump *l = lumps_of(world, s);
  for (uint32_t i = 0; l != NULL && i < s->lump_count; i++) {
    l[i].temperature = kelvin;
    l[i].interior = kelvin;
    l[i].reached = F3D_R(0.0);
    l[i].skin = kelvin;
  }
  s->temperature = kelvin;
  s->interior = kelvin;
  s->reached = F3D_R(0.0);
  s->skin = kelvin;
  return 1;
}

/* The part [part] of [body]'s heat, or null: a compound's part, or part
 * nought of any other body, which is the body. */
static int part_ok(const F3dSlot *s, uint32_t part) {
  if (s->shape == F3D_SHAPE_COMPOUND) return 1;
  return part == 0;
}

int f3d_body_get_part_temperature(F3dWorld *world, F3dBody body, uint32_t part,
                                  f3d_real *out) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || out == NULL || !part_ok(s, part)) return 0;
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    if (s->shape == F3D_SHAPE_COMPOUND) return 0;
    *out = s->temperature;
    return 1;
  }
  if (part >= s->lump_count) return 0;
  *out = l[part].temperature;
  return 1;
}

int f3d_body_set_part_temperature(F3dWorld *world, F3dBody body, uint32_t part,
                                  f3d_real kelvin) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !part_ok(s, part) ||
      !(f3d_finite(kelvin) && kelvin > F3D_R(0.0))) {
    return 0;
  }
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    if (s->shape == F3D_SHAPE_COMPOUND) return 0;
    return f3d_body_set_temperature(world, body, kelvin);
  }
  if (part >= s->lump_count) return 0;
  l[part].temperature = kelvin;
  l[part].interior = kelvin;
  l[part].reached = F3D_R(0.0);
  l[part].skin = kelvin;
  body_from_lumps(world, s);
  return 1;
}

int f3d_body_is_part_burning(F3dWorld *world, F3dBody body, uint32_t part,
                             int *out) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || out == NULL || !part_ok(s, part)) return 0;
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    if (s->shape == F3D_SHAPE_COMPOUND) return 0;
    *out = (s->flags & F3D_FLAG_BURNING) != 0;
    return 1;
  }
  if (part >= s->lump_count) return 0;
  *out = l[part].burning != 0;
  return 1;
}

int f3d_body_add_heat_at(F3dWorld *world, F3dBody body, f3d_real x, f3d_real y,
                         f3d_real z, f3d_real joules) {
  F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || !(f3d_finite(x) && f3d_finite(y) && f3d_finite(z) &&
                     f3d_finite(joules))) {
    return 0;
  }
  F3dLump *l = lumps_of(world, s);
  if (l == NULL) {
    s->heat += joules;
    return 1;
  }
  /* Into the part whose centre is nearest the point. */
  const F3dPlaced whole = f3d_placed_of(world, s);
  const F3dVec3 p = f3d_v3(x, y, z);
  uint32_t best = 0;
  f3d_real d2 = F3D_R(-1.0);
  for (uint32_t i = 0; i < s->lump_count; i++) {
    const F3dVec3 d = f3d_sub(f3d_placed_part(&whole, i).at, p);
    const f3d_real e = f3d_dot(d, d);
    if (d2 < F3D_R(0.0) || e < d2) {
      d2 = e;
      best = i;
    }
  }
  l[best].heat += joules;
  return 1;
}

int f3d_body_get_temperature(const F3dWorld *world, F3dBody body,
                             f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL) return 0;
  *out = s->temperature;
  return 1;
}

int f3d_body_get_surface_temperature(const F3dWorld *world, F3dBody body,
                                     f3d_real *out) {
  const F3dSlot *s = f3d_slot_of(world, body);
  if (s == NULL || out == NULL) return 0;
  *out = s->skin;
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
  F3dLump *l = lumps_of(world, s);
  if (l != NULL) {
    /* Over a compound's parts by their surfaces. */
    f3d_real surface = F3D_R(0.0);
    const F3dCompound *c = &world->compounds[s->hull - 1u];
    for (uint32_t i = 0; i < s->lump_count; i++) {
      surface += f3d_shape_surface(world, world->compound_parts[c->first_part + i].kind,
                                   world->compound_parts[c->first_part + i].size,
                                   world->compound_parts[c->first_part + i].rounding,
                                   world->compound_parts[c->first_part + i].hull);
    }
    for (uint32_t i = 0; i < s->lump_count; i++) {
      const F3dCompoundPart *p = &world->compound_parts[c->first_part + i];
      const f3d_real share =
          surface > F3D_R(0.0)
              ? f3d_shape_surface(world, p->kind, p->size, p->rounding, p->hull) / surface
              : F3D_R(1.0) / (f3d_real)s->lump_count;
      const f3d_real add = kg * share;
      if (add > F3D_R(0.0)) {
        const f3d_real held = l[i].mass * s->material.specific_heat +
                              l[i].water * F3D_WATER_HEAT;
        const f3d_real added = add * F3D_WATER_HEAT;
        const f3d_real was = l[i].temperature;
        l[i].temperature = (held * l[i].temperature +
                            added * world->s.air_temperature) /
                           (held + added);
        /* Mixed all through: the whole of it moves alike. */
        l[i].interior += l[i].temperature - was;
        l[i].skin += l[i].temperature - was;
      }
      l[i].water = f3d_max(l[i].water + add, F3D_R(0.0));
    }
    body_from_lumps(world, s);
    return 1;
  }
  if (kg > F3D_R(0.0)) {
    /* It lands at the air's temperature and mixes with what is there:
     * counted at the body's own, it would bring heat from nowhere. Taken
     * off, it leaves at the body's, and the body's temperature stays. */
    const f3d_real body_heat = capacity_of(s);
    const f3d_real added = kg * F3D_WATER_HEAT;
    const f3d_real was = s->temperature;
    s->temperature = (body_heat * s->temperature +
                      added * world->s.air_temperature) /
                     (body_heat + added);
    /* Mixed all through: the whole of it moves alike. */
    s->interior += s->temperature - was;
    s->skin += s->temperature - was;
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

/* How big a shape of [kind] and [size] is where it touches: a ball's
 * radius, a capsule's, a box's least half extent. */
static f3d_real touch_radius(uint32_t kind, F3dVec3 size) {
  switch (kind) {
    case F3D_SHAPE_SPHERE:
    case F3D_SHAPE_CAPSULE:
      return size.x;
    case F3D_SHAPE_BOX:
      return f3d_min(size.x, f3d_min(size.y, size.z));
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

/* ------------------------------------------------------------- lumps */

/* A compound's own record, or null for any other body. */
static const F3dCompound *compound_of(const F3dWorld *world, const F3dSlot *s) {
  if (s->shape != F3D_SHAPE_COMPOUND || s->hull == 0 ||
      s->hull > world->s.compound_count) {
    return NULL;
  }
  return &world->compounds[s->hull - 1u];
}

static const F3dCompoundPart *part_of(const F3dWorld *world,
                                      const F3dCompound *c, uint32_t i) {
  return &world->compound_parts[c->first_part + i];
}

static f3d_real part_volume(const F3dWorld *world, const F3dCompoundPart *p) {
  return f3d_shape_volume(world, p->kind, p->size, p->rounding, p->hull);
}

static f3d_real part_surface(const F3dWorld *world, const F3dCompoundPart *p) {
  return f3d_shape_surface(world, p->kind, p->size, p->rounding, p->hull);
}

/* A compound's parts' heat, made from the body's: each part as hot as the
 * body, with its share of the mass and fuel by volume and of the water by
 * surface. */
static void lumps_from_body(const F3dWorld *world, const F3dSlot *s,
                            const F3dCompound *c, F3dLump *out) {
  f3d_real volume = F3D_R(0.0), surface = F3D_R(0.0);
  for (uint32_t i = 0; i < c->part_count; i++) {
    volume += part_volume(world, part_of(world, c, i));
    surface += part_surface(world, part_of(world, c, i));
  }
  for (uint32_t i = 0; i < c->part_count; i++) {
    const F3dCompoundPart *p = part_of(world, c, i);
    const f3d_real by_volume = volume > F3D_R(0.0)
                                   ? part_volume(world, p) / volume
                                   : F3D_R(1.0) / (f3d_real)c->part_count;
    const f3d_real by_surface = surface > F3D_R(0.0)
                                    ? part_surface(world, p) / surface
                                    : F3D_R(1.0) / (f3d_real)c->part_count;
    F3dLump *l = &out[i];
    f3d_zero(l, sizeof *l);
    l->temperature = s->temperature;
    l->interior = s->interior;
    l->reached = s->reached;
    l->skin = s->skin;
    l->mass = s->mass * by_volume;
    l->fuel = s->fuel * by_volume;
    l->water = s->water * by_surface;
    l->burning = (s->flags & F3D_FLAG_BURNING) != 0;
  }
}

/* Gives every live compound its parts' heat and drops what no live
 * compound holds: the world's lumps rebuilt in slot order when they no
 * longer match, a part's kept where its body kept its shape. 0 when memory
 * ran out. */
static int ensure_lumps(F3dWorld *world) {
  uint32_t need = 0;
  int fits = 1;
  for (uint32_t i = 0; i < world->s.used; i++) {
    const F3dSlot *s = &world->slots[i];
    const F3dCompound *c = s->live ? compound_of(world, s) : NULL;
    if (c == NULL) {
      if (s->lumps != 0) fits = 0;
      continue;
    }
    if (s->lumps == 0 || s->lump_count != c->part_count ||
        s->lumps - 1u + s->lump_count > world->s.lump_count ||
        s->lumps - 1u != need) {
      fits = 0;
    }
    need += c->part_count;
  }
  if (fits && need == world->s.lump_count) return 1;
  F3dLump *made = need > 0 ? (F3dLump *)f3d_alloc((size_t)need * sizeof(F3dLump))
                           : NULL;
  if (need > 0 && made == NULL) return 0;
  uint32_t at = 0;
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    const F3dCompound *c = s->live ? compound_of(world, s) : NULL;
    if (c == NULL) {
      s->lumps = 0;
      s->lump_count = 0;
      continue;
    }
    const int kept = s->lumps != 0 && s->lump_count == c->part_count &&
                     s->lumps - 1u + s->lump_count <= world->s.lump_count;
    if (kept) {
      f3d_copy(&made[at], &world->lumps[s->lumps - 1u],
               (size_t)c->part_count * sizeof(F3dLump));
    } else {
      lumps_from_body(world, s, c, &made[at]);
    }
    s->lumps = at + 1u;
    s->lump_count = c->part_count;
    at += c->part_count;
  }
  f3d_free(world->lumps);
  world->lumps = made;
  world->s.lump_count = need;
  return 1;
}

/* A compound body's whole from its parts: its temperature the parts'
 * weighted by what they hold, and its water, fuel, fire and mass theirs
 * summed. */
static void body_from_lumps(F3dWorld *world, F3dSlot *s) {
  if (s->lumps == 0) return;
  const F3dLump *l = &world->lumps[s->lumps - 1u];
  f3d_real held = F3D_R(0.0), warm = F3D_R(0.0), water = F3D_R(0.0);
  f3d_real fuel = F3D_R(0.0), release = F3D_R(0.0), mass = F3D_R(0.0);
  f3d_real inside = F3D_R(0.0), reached = F3D_R(0.0), skin = F3D_R(0.0);
  int burning = 0;
  for (uint32_t i = 0; i < s->lump_count; i++) {
    const f3d_real c = l[i].mass * s->material.specific_heat +
                       l[i].water * F3D_WATER_HEAT;
    held += c;
    warm += c * l[i].temperature;
    inside += c * l[i].interior;
    reached += c * l[i].reached;
    skin += c * l[i].skin;
    water += l[i].water;
    fuel += l[i].fuel;
    release += l[i].heat_release;
    mass += l[i].mass;
    burning |= l[i].burning != 0;
  }
  if (held > F3D_R(0.0)) {
    s->temperature = warm / held;
    s->interior = inside / held;
    s->reached = reached / held;
    s->skin = skin / held;
  }
  s->water = water;
  s->fuel = fuel;
  s->heat_release = release;
  if (burning) {
    s->flags |= F3D_FLAG_BURNING;
  } else {
    s->flags &= (uint8_t)~F3D_FLAG_BURNING;
  }
  if (mass != s->mass) {
    s->mass = mass;
    f3d_refresh_mass(world, s);
  }
}

/* ---------------------------------------------------------- the step's */

/* What heat sees for a step: a whole body, or one part of a compound,
 * worked on as a copy and written back at the end. */
typedef struct Heat {
  F3dLump l;
  uint32_t slot;
  F3dVec3 at;
  f3d_real surface;
  /* How big it is where it touches. */
  f3d_real touch;
  /* How far it reaches from [at], for a compound's parts. */
  f3d_real reach;
  /* m³; and how many times further from the interior's temperature its
   * surface is than its mean, this step. */
  f3d_real volume;
  f3d_real gain;
  /* The hottest its surface is where something touches it this step, K;
   * nought where nothing does. */
  f3d_real spot;
} Heat;

/* Every live body's entries, and where each body's start. */
typedef struct Heats {
  Heat *h;
  uint32_t count;
  uint32_t *first, *many;
} Heats;

static f3d_real held_by(const F3dWorld *world, const Heat *h) {
  return h->l.mass * world->slots[h->slot].material.specific_heat +
         h->l.water * F3D_WATER_HEAT;
}

/* Its surface's temperature: as far from the interior's as the gain says. */
static f3d_real skin_of(const Heat *h) {
  return h->l.interior + h->gain * (h->l.temperature - h->l.interior);
}

/* How heat lies in a body, by the heat balance integral (Goodman): from
 * the surface heat reaches in over a layer that thickens as δ² = 6αt
 * whatever warms or cools it, α = k/(ρc), and across the layer the
 * temperature falls off as a parabola to the interior's. A parabola holds a
 * third of its surface's excess, so the mean's excess over the interior is
 * the surface's times Aδ/3V, and the surface is 3V/(Aδ) times as far from
 * the interior as the mean is. Once the layer is as deep as the body is
 * thick, V/A, the interior warms too, at its slowest mode's rate (π/2)²α/L²,
 * and a body that is all one temperature again has no layer. A small or
 * conductive body gets there within a step and is one temperature
 * throughout; a log of wood takes hours, and its surface catches long
 * before its middle has warmed.
 *
 * The layer grows by this step's [dt] here; the gain is the step's. */
static void lay_heat(const F3dWorld *world, Heat *h, f3d_real dt) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  h->gain = F3D_R(1.0);
  if (!(h->volume > F3D_R(0.0) && h->surface > F3D_R(0.0) &&
        h->l.mass > F3D_R(0.0) && m->specific_heat > F3D_R(0.0))) {
    return;
  }
  const f3d_real thick = h->volume / h->surface;
  const f3d_real alpha =
      m->conductivity * h->volume / (h->l.mass * m->specific_heat);
  h->l.reached = f3d_min(h->l.reached + F3D_R(6.0) * alpha * dt, thick * thick);
  if (h->l.reached > F3D_R(0.0)) {
    h->gain = F3D_R(3.0) * thick / f3d_sqrt(h->l.reached);
  }
}

/* After the step: the interior warming once the layer is through, and a
 * body all one temperature, within a hundredth of a kelvin, starting a new
 * layer when it is next warmed or cooled. */
static void settle_heat(const F3dWorld *world, Heat *h, f3d_real dt) {
  F3dLump *l = &h->l;
  const F3dMaterial *m = &world->slots[h->slot].material;
  if (h->volume > F3D_R(0.0) && h->surface > F3D_R(0.0) &&
      l->mass > F3D_R(0.0) && m->specific_heat > F3D_R(0.0)) {
    const f3d_real thick = h->volume / h->surface;
    if (l->reached >= thick * thick) {
      const f3d_real alpha =
          m->conductivity * h->volume / (l->mass * m->specific_heat);
      const f3d_real x = F3D_R(0.25) * F3D_PI * F3D_PI * alpha * dt /
                         (thick * thick);
      l->interior += (l->temperature - l->interior) * x / (F3D_R(1.0) + x);
    }
  }
  if (f3d_abs(l->temperature - l->interior) <= F3D_R(0.01)) {
    l->interior = l->temperature;
    l->reached = F3D_R(0.0);
  }
}

/* The entry of a body that is nearest [p]: its only one, or the part. */
static Heat *nearest(Heats *hs, uint32_t slot, F3dVec3 p) {
  Heat *best = &hs->h[hs->first[slot]];
  f3d_real d2 = F3D_R(-1.0);
  for (uint32_t k = 0; k < hs->many[slot]; k++) {
    Heat *h = &hs->h[hs->first[slot] + k];
    const F3dVec3 d = f3d_sub(h->at, p);
    const f3d_real e = f3d_dot(d, d);
    if (d2 < F3D_R(0.0) || e < d2) {
      d2 = e;
      best = h;
    }
  }
  return best;
}

/* How readily [h]'s surface takes heat from a sudden touch, √(kρc), with
 * its density its mass over its volume; −1 for one with no thermal mass or
 * no volume to hold it — a reservoir, whose surface a touch does not move. */
static f3d_real effusivity(const F3dWorld *world, const Heat *h) {
  const F3dMaterial *m = &world->slots[h->slot].material;
  if (!(h->l.mass > F3D_R(0.0) && h->volume > F3D_R(0.0))) return F3D_R(-1.0);
  return f3d_sqrt(m->conductivity * (h->l.mass / h->volume) * m->specific_heat);
}

/* Heat across every contact that touches, each side's part nearest the
 * contact. The conductance is Holm's constriction of two bodies meeting
 * over a spot of radius a, G = 4a / (1/k₁ + 1/k₂), with a the radius of a
 * circle of the contact's area, between their surfaces; and the exchange is
 * taken implicitly for the pair, each surface moving by its gain over its
 * thermal mass, so it carries the surfaces towards one temperature and
 * never past it. In key order, so the same world passes the same heat. */
static void conduct(F3dWorld *world, Heats *hs, f3d_real dt) {
  for (uint32_t i = 0; i < world->s.manifold_count; i++) {
    const F3dManifold *m = &world->manifolds[i];
    if (!m->touching || m->count == 0) continue;
    F3dSlot *sa = f3d_slot_of(world, m->a);
    F3dSlot *sb = f3d_slot_of(world, m->b);
    if (sa == NULL || sb == NULL) continue;
    const uint32_t ia_slot = (uint32_t)(m->a & 0xffffffffu);
    const uint32_t ib_slot = (uint32_t)(m->b & 0xffffffffu);
    if (hs->many[ia_slot] == 0 || hs->many[ib_slot] == 0) continue;
    F3dVec3 centre = f3d_v3(F3D_R(0.0), F3D_R(0.0), F3D_R(0.0));
    for (uint32_t k = 0; k < m->count; k++) {
      centre = f3d_add(centre, m->points[k].point);
    }
    centre = f3d_scale(centre, F3D_R(1.0) / (f3d_real)m->count);
    Heat *a = nearest(hs, ia_slot, centre);
    Heat *b = nearest(hs, ib_slot, centre);
    /* Where they meet, the two surfaces are at once at the temperature
     * their effusivities e = √(kρc) weigh them to — straw on a red-hot
     * stone is at nearly the stone's — however little the contact passes to
     * either whole, and however lightly they touch. That spot is what
     * lights a fuel. A side with no thermal mass, or none it fills, holds
     * the spot at its own. */
    const f3d_real ta = skin_of(a), tb = skin_of(b);
    const f3d_real ea = effusivity(world, a), eb = effusivity(world, b);
    const f3d_real meet = ea < F3D_R(0.0)   ? ta
                          : eb < F3D_R(0.0) ? tb
                                            : (ea * ta + eb * tb) / (ea + eb);
    a->spot = f3d_max(a->spot, meet);
    b->spot = f3d_max(b->spot, meet);
    const f3d_real ca = held_by(world, a), cb = held_by(world, b);
    /* No thermal mass: a fixed one is a reservoir, and nothing else can
     * have none. */
    const f3d_real ia = ca > F3D_R(0.0) ? F3D_R(1.0) / ca : F3D_R(0.0);
    const f3d_real ib = cb > F3D_R(0.0) ? F3D_R(1.0) / cb : F3D_R(0.0);
    if (ia == F3D_R(0.0) && ib == F3D_R(0.0)) continue;
    /* What a joule does to each surface. */
    const f3d_real sa_k = ia * a->gain, sb_k = ib * b->gain;
    const f3d_real ra = a->touch, rb = b->touch;
    const f3d_real r = ra > F3D_R(0.0) && rb > F3D_R(0.0)
                           ? ra * rb / (ra + rb)
                           : f3d_max(ra, rb);
    const f3d_real area = contact_area(m, r);
    if (!(area > F3D_R(0.0))) continue;
    const f3d_real spot = f3d_sqrt(area / F3D_PI);
    const f3d_real g = F3D_R(4.0) * spot /
                       (F3D_R(1.0) / sa->material.conductivity +
                        F3D_R(1.0) / sb->material.conductivity);
    const f3d_real gdt = g * dt;
    const f3d_real q = gdt * (tb - ta) /
                       (F3D_R(1.0) + gdt * (sa_k + sb_k));
    a->l.temperature += q * ia;
    b->l.temperature -= q * ib;
  }
}

/* Heat between a compound's own parts where they meet: Holm's
 * constriction again, G = 2ak for one material, over a spot as wide as the
 * narrower part's cross-section — a table's leg into its top. Parts whose
 * reaches do not meet do not touch. Implicit a pair at a time, in part
 * order. */
static void conduct_within(F3dWorld *world, Heats *hs, f3d_real dt) {
  for (uint32_t i = 0; i < world->s.used; i++) {
    if (hs->many[i] < 2u) continue;
    const f3d_real k = world->slots[i].material.conductivity;
    for (uint32_t p = 0; p < hs->many[i]; p++) {
      for (uint32_t q = p + 1u; q < hs->many[i]; q++) {
        Heat *a = &hs->h[hs->first[i] + p];
        Heat *b = &hs->h[hs->first[i] + q];
        const F3dVec3 d = f3d_sub(a->at, b->at);
        if (f3d_dot(d, d) > (a->reach + b->reach) * (a->reach + b->reach)) continue;
        const f3d_real spot = f3d_min(a->touch, b->touch);
        if (!(spot > F3D_R(0.0))) continue;
        const f3d_real ca = held_by(world, a), cb = held_by(world, b);
        if (!(ca > F3D_R(0.0) && cb > F3D_R(0.0))) continue;
        const f3d_real gdt = F3D_R(2.0) * spot * k * dt;
        const f3d_real flow = gdt * (b->l.temperature - a->l.temperature) /
                              (F3D_R(1.0) + gdt * (F3D_R(1.0) / ca + F3D_R(1.0) / cb));
        /* Through the body, not across a surface: each part moves alike
         * all through. */
        a->l.temperature += flow / ca;
        a->l.interior += flow / ca;
        b->l.temperature -= flow / cb;
        b->l.interior -= flow / cb;
      }
    }
  }
}

/* Less than this, W, a body is not worth radiating to: a kilogram of wood
 * it warms by a fifth of a kelvin an hour. It decides how far a source
 * looks, from how strongly it radiates, and nothing else is cut. */
#define F3D_RADIANT_LEAST F3D_R(0.1)
/* Nor is one it would warm by less than this, K/s — a third of a kelvin
 * an hour: what a big body takes from a distant source is not worth the
 * rays that would decide how much of it the source sees. */
#define F3D_RADIANT_SLOWEST F3D_R(1e-4)
/* A body that looks smaller than this, its radius over its distance, is
 * seen whole or not at all: one ray, to its centre, decides. */
#define F3D_RADIANT_SMALL F3D_R(0.15)
/* How many rays decide how much of a body a source sees past what stands
 * between them: its centre and four points around it. */
#define F3D_RADIANT_RAYS 5u
/* A buoyant plume spreads by this much of its height on each side
 * (Heskestad: b = 0.12 (z − z₀)). */
#define F3D_PLUME_SPREAD F3D_R(0.12)
/* Air's specific heat at constant pressure, J / (kg K). */
#define F3D_AIR_HEAT F3D_R(1005.0)

/* The radius of the ball with an entry's surface: what radiation sees of
 * it. */
static f3d_real seen_radius(const Heat *h) {
  return f3d_sqrt(h->surface / (F3D_R(4.0) * F3D_PI));
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

f3d_real f3d_flame_of(const F3dWorld *world, F3dVec3 at, f3d_real surface,
                      f3d_real release, F3dVec3 *axis) {
  const f3d_real g2 = f3d_dot(world->s.gravity, world->s.gravity);
  const f3d_real g = f3d_sqrt(g2);
  const F3dVec3 up = g2 > F3D_R(0.0)
                         ? f3d_scale(world->s.gravity, F3D_R(-1.0) / g)
                         : f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0));
  *axis = up;
  if (!(release > F3D_R(0.0) && surface > F3D_R(0.0))) return F3D_R(0.0);
  /* Heskestad's length over a base as wide as the body, from its middle;
   * leaning with the wind where it stands by the buoyant speed
   * (g·Q / (ρ c_p Tₐ D))^(1/3). */
  const f3d_real r = f3d_sqrt(surface / (F3D_R(4.0) * F3D_PI));
  const f3d_real across = F3D_R(2.0) * r;
  const f3d_real rise = cube_root(
      g * release / (world->s.air_density * F3D_AIR_HEAT *
                     world->s.air_temperature * across));
  f3d_real wind[3];
  f3d_world_sample_wind(world, at.x, at.y, at.z, wind);
  F3dVec3 blow = f3d_v3(wind[0], wind[1], wind[2]);
  blow = f3d_sub(blow, f3d_scale(up, f3d_dot(blow, up)));
  const F3dVec3 lean = f3d_add(f3d_scale(up, rise), blow);
  const f3d_real len = f3d_sqrt(f3d_dot(lean, lean));
  if (len > F3D_R(0.0)) *axis = f3d_scale(lean, F3D_R(1.0) / len);
  return flame_length(release, across) + r;
}

/* Whether a body's entries radiate and are radiated to: not a mesh — a
 * level's floor is the room, already the air's temperature everything
 * radiates against. */
static int radiates(const F3dSlot *s) {
  return s->live && s->shape != F3D_SHAPE_MESH;
}

/* What can be heated: an entry with a surface and a thermal mass. */
static int receives(const F3dWorld *world, const Heat *h) {
  return radiates(&world->slots[h->slot]) && h->surface > F3D_R(0.0) &&
         held_by(world, h) > F3D_R(0.0);
}

typedef struct Near {
  const F3dWorld *world;
  uint32_t count, capacity;
  uint32_t *slots;
  int failed;
} Near;

static int near_body(void *context, int32_t leaf) {
  Near *n = (Near *)context;
  const uint32_t slot = n->world->tree.nodes[leaf].slot;
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
 * that halves the disc it shows; or, when it looks small, whether the one
 * to its centre does. */
static f3d_real seen(F3dWorld *world, F3dVec3 from, F3dBody ha, F3dVec3 to,
                     F3dBody hb, f3d_real rb) {
  const F3dVec3 line = f3d_sub(to, from);
  const f3d_real d = f3d_sqrt(f3d_dot(line, line));
  if (!(d > F3D_R(0.0))) return F3D_R(1.0);
  const F3dVec3 n = f3d_scale(line, F3D_R(1.0) / d);
  /* Two directions across the line, the same however it points. */
  const F3dVec3 helper = f3d_abs(n.y) < F3D_R(0.9)
                             ? f3d_v3(F3D_R(0.0), F3D_R(1.0), F3D_R(0.0))
                             : f3d_v3(F3D_R(1.0), F3D_R(0.0), F3D_R(0.0));
  F3dVec3 e1 = f3d_cross(n, helper);
  e1 = f3d_scale(e1, F3D_R(1.0) / f3d_sqrt(f3d_dot(e1, e1)));
  const F3dVec3 e2 = f3d_cross(n, e1);
  const f3d_real off = F3D_R(0.70710678) * rb;
  const F3dVec3 aims[F3D_RADIANT_RAYS] = {
      to, f3d_madd(to, e1, off), f3d_madd(to, e1, -off), f3d_madd(to, e2, off),
      f3d_madd(to, e2, -off)};
  const uint32_t rays = rb < F3D_RADIANT_SMALL * d ? 1u : F3D_RADIANT_RAYS;
  uint32_t open = 0;
  for (uint32_t k = 0; k < rays; k++) {
    if (!f3d_world_segment_blocked(world, from, aims[k], ha, hb)) open++;
  }
  return (f3d_real)open / (f3d_real)rays;
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
static void radiate(F3dWorld *world, Heats *hs, f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  const f3d_real ta4 = ta * ta * ta * ta;
  /* The largest thing that can be heated, as radiation sees it. */
  f3d_real largest = F3D_R(0.0);
  for (uint32_t e = 0; e < hs->count; e++) {
    if (receives(world, &hs->h[e])) largest = f3d_max(largest, seen_radius(&hs->h[e]));
  }
  if (!(largest > F3D_R(0.0))) return;
  /* Where every body stands now, for the rays that decide what sees what. */
  f3d_update_proxies(world, F3D_R(0.0));
  f3d_build_mesh_trees(world);
  Near n;
  n.world = world;
  n.capacity = 0;
  n.slots = NULL;
  n.failed = 0;
  for (uint32_t e = 0; e < hs->count && !n.failed; e++) {
    const Heat *a = &hs->h[e];
    const F3dSlot *sa = &world->slots[a->slot];
    if (!radiates(sa) || !(a->surface > F3D_R(0.0))) continue;
    const F3dMaterial *ma = &sa->material;
    const f3d_real t = skin_of(a);
    /* What its surface sends out above the room, and its flame's. */
    const f3d_real excess = ma->emissivity * F3D_STEFAN_BOLTZMANN * a->surface *
                            (t * t * t * t - ta4);
    const int alight = a->l.burning != 0;
    const f3d_real flame = alight ? ma->flame_radiant * a->l.heat_release
                                  : F3D_R(0.0);
    const f3d_real sent = excess + flame;
    const f3d_real ra = seen_radius(a);
    /* The column the flame stands in. */
    F3dVec3 axis;
    const f3d_real column = f3d_flame_of(
        world, a->at, a->surface, alight ? a->l.heat_release : F3D_R(0.0), &axis);
    if (f3d_abs(sent) < F3D_RADIANT_LEAST && column == F3D_R(0.0)) continue;
    /* caught ≤ (r/d)²/2: past this, the largest thing catches less than
     * the least worth sending. */
    const f3d_real far =
        largest * f3d_sqrt(f3d_abs(sent) / (F3D_R(2.0) * F3D_RADIANT_LEAST));
    const f3d_real top = ra + F3D_PLUME_SPREAD * column;
    const f3d_real reach = f3d_max(far, column + top + largest);
    F3dBox box;
    box.lo = f3d_sub(a->at, f3d_v3(reach, reach, reach));
    box.hi = f3d_add(a->at, f3d_v3(reach, reach, reach));
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
    const F3dBody ha = f3d_handle_of(world, sa);
    for (uint32_t k = 0; k < n.count; k++) {
      const uint32_t other = n.slots[k];
      if (other >= world->s.used) continue;
      const F3dBody hb = f3d_handle_of(world, &world->slots[other]);
      for (uint32_t j = 0; j < hs->many[other]; j++) {
        Heat *b = &hs->h[hs->first[other] + j];
        /* Not itself; but another part of its own body, yes: a beam's
         * burning end heats the part beside it. */
        if (b == a || !receives(world, b)) continue;
        const F3dSlot *sb = &world->slots[b->slot];
        const F3dVec3 between = f3d_sub(b->at, a->at);
        const f3d_real d = f3d_sqrt(f3d_dot(between, between));
        if (d > reach) continue;
        const f3d_real rb = seen_radius(b);
        /* In the flame. */
        f3d_real inside = F3D_R(0.0);
        if (column > F3D_R(0.0)) {
          const f3d_real along =
              f3d_clamp(f3d_dot(between, axis), F3D_R(0.0), column);
          const F3dVec3 off = f3d_sub(between, f3d_scale(axis, along));
          const f3d_real apart = f3d_sqrt(f3d_dot(off, off));
          const f3d_real width = ra + F3D_PLUME_SPREAD * along;
          inside = f3d_clamp((width + rb - apart) / (F3D_R(2.0) * rb),
                             F3D_R(0.0), F3D_R(1.0));
        }
        const f3d_real tb = skin_of(b);
        if (inside > F3D_R(0.0) && tb < ma->flame_temperature) {
          /* What the surface can take before it is as hot as the flame. */
          const f3d_real cb = held_by(world, b) / b->gain;
          const f3d_real tf = ma->flame_temperature;
          const f3d_real cond =
              (ma->flame_convection + flame_e * sb->material.emissivity *
                                          F3D_STEFAN_BOLTZMANN *
                                          (tf * tf + tb * tb) * (tf + tb)) *
              b->surface * F3D_R(0.5) * inside;
          /* Never past the flame in one step. */
          const f3d_real gdt = f3d_min(cond * dt, cb);
          b->l.heat += gdt * (tf - tb);
        }
        /* From afar, on what is outside the flame. */
        const f3d_real share = sb->material.emissivity * caught(rb, d) *
                               (F3D_R(1.0) - inside);
        const f3d_real worth =
            f3d_max(F3D_RADIANT_LEAST, F3D_RADIANT_SLOWEST * held_by(world, b));
        if (f3d_abs(sent) * share < worth) continue;
        b->l.heat += sent * share * seen(world, a->at, ha, b->at, hb, rb) * dt;
      }
    }
  }
  f3d_free(n.slots);
}

enum { CAUGHT = 1, WENT_OUT = 2, BURNT_OUT = 4 };

/* One entry's step: its fire, its heat, what it gives the air, its water
 * and whether it is alight. Returns what changed, as CAUGHT, WENT_OUT and
 * BURNT_OUT. */
static uint32_t step_entry(F3dWorld *world, const F3dSlot *s, Heat *h,
                           f3d_real dt) {
  const f3d_real ta = world->s.air_temperature;
  const F3dMaterial *m = &s->material;
  F3dLump *l = &h->l;
  uint32_t said = 0;
  f3d_real power = l->heat / dt;
  l->heat = F3D_R(0.0);
  l->heat_release = F3D_R(0.0);
  /* The fire: a burning surface loses mass at the burn rate, the mass
   * releases its heat of combustion, and the flame's share of that goes
   * back into it; the rest leaves as hot gas. The mass leaves at the body's
   * velocity, so the velocity does not change. */
  if (l->burning) {
    const f3d_real burnt = f3d_min(m->burn_rate * h->surface * dt, l->fuel);
    const f3d_real released = burnt * m->heat_of_combustion / dt;
    power += m->flame_feedback * released;
    l->heat_release = (F3D_R(1.0) - m->flame_feedback) * released;
    l->fuel -= burnt;
    l->mass -= burnt;
    if (l->fuel <= F3D_R(0.0)) {
      l->fuel = F3D_R(0.0);
      l->burning = 0;
      said |= BURNT_OUT;
    }
  }
  const f3d_real dry = l->mass * m->specific_heat;
  const f3d_real capacity = dry + l->water * F3D_WATER_HEAT;
  if (!(capacity > F3D_R(0.0))) return said;
  const f3d_real gain = h->gain;
  const f3d_real inner = l->interior;
  /* The surface as the step found it. */
  const f3d_real was = l->skin;
  /* What the surface gives the air: convection to the air moving past it,
   * and radiation εσ(T⁴ − Tₐ⁴), written exactly as εσ(T² + Tₐ²)(T + Tₐ)·
   * (T − Tₐ) so both are a conductance times the difference — at the
   * surface's temperature, which moves by the gain times the mean's. Taken
   * implicitly with the conductance as it is, the step cannot carry the
   * surface past the air's temperature, however small the body or long the
   * step. */
  f3d_real conductance = F3D_R(0.0);
  if (h->surface > F3D_R(0.0)) {
    f3d_real wind[3];
    f3d_world_sample_wind(world, h->at.x, h->at.y, h->at.z, wind);
    const f3d_real ux = s->velocity.x - wind[0];
    const f3d_real uy = s->velocity.y - wind[1];
    const f3d_real uz = s->velocity.z - wind[2];
    const f3d_real u = f3d_sqrt(ux * ux + uy * uy + uz * uz);
    const f3d_real t = skin_of(h);
    conductance = h->surface *
                  (convection(u) + m->emissivity * F3D_STEFAN_BOLTZMANN *
                                       (t * t + ta * ta) * (t + ta));
  }
  f3d_real next = (capacity * l->temperature +
                   dt * (power - conductance * (inner * (F3D_R(1.0) - gain) - ta))) /
                  (capacity + dt * conductance * gain);
  /* Water on it holds its surface at the boiling point: what would heat
   * the surface past it boils water off instead, and only once the water
   * has gone does it heat on. */
  const f3d_real boiling_mean = inner + (F3D_WATER_BOILS - inner) / gain;
  int boiling = 0;
  if (l->water > F3D_R(0.0) && next > boiling_mean) {
    const f3d_real excess = (next - boiling_mean) * capacity;
    const f3d_real boils = excess / F3D_WATER_LATENT;
    if (boils < l->water) {
      l->water -= boils;
      next = boiling_mean;
      boiling = 1;
    } else {
      const f3d_real left = excess - l->water * F3D_WATER_LATENT;
      l->water = F3D_R(0.0);
      next = dry > F3D_R(0.0) ? boiling_mean + left / dry : boiling_mean;
    }
  }
  l->temperature = f3d_max(next, F3D_R(1e-3));
  settle_heat(world, h, dt);
  l->skin = boiling ? F3D_WATER_BOILS : f3d_max(skin_of(h), F3D_R(1e-3));
  /* Alight when its surface reaches the ignition temperature, at the start
   * of the step or its end, or where something hot enough touches it; and
   * out when it ends below it with nothing hot enough touching. A wet one
   * is held at boiling, below any ignition temperature here, so water puts
   * a fire out and keeps a wet body from catching. */
  const f3d_real ignition = m->ignition_temperature;
  if (ignition <= F3D_R(0.0)) return said;
  const f3d_real spot = l->water > F3D_R(0.0) ? F3D_R(0.0) : h->spot;
  if (l->burning) {
    if (l->skin < ignition && spot < ignition) {
      l->burning = 0;
      said |= WENT_OUT;
    }
  } else if (l->fuel > F3D_R(0.0) && l->water <= F3D_R(0.0) &&
             f3d_max(f3d_max(was, l->skin), spot) >= ignition) {
    l->burning = 1;
    said |= CAUGHT;
  }
  return said;
}

/* Every live body's entries for the step: a body's own, or a compound's
 * parts', where they stand, with the heat laid in them grown by [dt]; heat
 * the body was given as a whole shared out by what each part holds. */
static int gather(F3dWorld *world, Heats *hs, f3d_real dt) {
  const uint32_t used = world->s.used;
  uint32_t total = 0;
  for (uint32_t i = 0; i < used; i++) {
    const F3dSlot *s = &world->slots[i];
    if (!s->live) continue;
    total += s->lumps != 0 ? s->lump_count : 1u;
  }
  hs->count = total;
  hs->h = (Heat *)f3d_alloc((size_t)total * sizeof(Heat) + 8u);
  hs->first = (uint32_t *)f3d_alloc((size_t)used * 2u * sizeof(uint32_t) + 8u);
  if (hs->h == NULL || hs->first == NULL) return 0;
  hs->many = hs->first + used;
  uint32_t at = 0;
  for (uint32_t i = 0; i < used; i++) {
    F3dSlot *s = &world->slots[i];
    hs->first[i] = at;
    hs->many[i] = 0;
    if (!s->live) continue;
    if (s->lumps == 0) {
      Heat *h = &hs->h[at++];
      f3d_zero(h, sizeof *h);
      h->l.temperature = s->temperature;
      h->l.interior = s->interior;
      h->l.reached = s->reached;
      h->l.skin = s->skin;
      h->l.heat = s->heat;
      h->l.water = s->water;
      h->l.fuel = s->fuel;
      h->l.mass = s->mass;
      h->l.heat_release = s->heat_release;
      h->l.burning = (s->flags & F3D_FLAG_BURNING) != 0;
      h->slot = i;
      h->at = s->position;
      h->surface = s->surface;
      h->touch = touch_radius(s->shape, s->size);
      h->volume = s->shape == F3D_SHAPE_MESH
                      ? F3D_R(0.0)
                      : f3d_shape_volume(world, s->shape, s->size, s->rounding, s->hull);
      lay_heat(world, h, dt);
      hs->many[i] = 1;
      continue;
    }
    const F3dCompound *c = compound_of(world, s);
    const F3dPlaced whole = f3d_placed_of(world, s);
    f3d_real held = F3D_R(0.0);
    for (uint32_t k = 0; k < s->lump_count; k++) {
      const F3dLump *l = &world->lumps[s->lumps - 1u + k];
      held += l->mass * s->material.specific_heat + l->water * F3D_WATER_HEAT;
    }
    for (uint32_t k = 0; k < s->lump_count; k++) {
      const F3dCompoundPart *part = part_of(world, c, k);
      Heat *h = &hs->h[at++];
      f3d_zero(h, sizeof *h);
      h->l = world->lumps[s->lumps - 1u + k];
      const f3d_real mine = h->l.mass * s->material.specific_heat +
                            h->l.water * F3D_WATER_HEAT;
      if (held > F3D_R(0.0)) h->l.heat += s->heat * mine / held;
      h->slot = i;
      h->at = f3d_placed_part(&whole, k).at;
      h->surface = part_surface(world, part);
      h->touch = touch_radius(part->kind, part->size);
      h->reach = part->reach;
      h->volume = part_volume(world, part);
      lay_heat(world, h, dt);
    }
    s->heat = F3D_R(0.0);
    hs->many[i] = s->lump_count;
  }
  return 1;
}

void f3d_step_heat(F3dWorld *world, f3d_real dt) {
  if (!ensure_lumps(world)) return;
  Heats hs;
  f3d_zero(&hs, sizeof hs);
  if (!gather(world, &hs, dt)) {
    f3d_free(hs.h);
    f3d_free(hs.first);
    return;
  }
  conduct(world, &hs, dt);
  conduct_within(world, &hs, dt);
  radiate(world, &hs, dt);
  for (uint32_t i = 0; i < world->s.used; i++) {
    F3dSlot *s = &world->slots[i];
    if (!s->live || hs.many[i] == 0) continue;
    const F3dBody handle = f3d_handle_of(world, s);
    const int was = (s->flags & F3D_FLAG_BURNING) != 0;
    uint32_t said = 0;
    for (uint32_t k = 0; k < hs.many[i]; k++) {
      said |= step_entry(world, s, &hs.h[hs.first[i] + k], dt);
    }
    if (s->lumps == 0) {
      /* A body: its fields back, and what happened, in the order it did. */
      const F3dLump *l = &hs.h[hs.first[i]].l;
      s->temperature = l->temperature;
      s->interior = l->interior;
      s->reached = l->reached;
      s->skin = l->skin;
      s->heat = F3D_R(0.0);
      s->water = l->water;
      s->fuel = l->fuel;
      s->heat_release = l->heat_release;
      if (l->mass != s->mass) {
        s->mass = l->mass;
        f3d_refresh_mass(world, s);
      }
      if (l->burning) {
        s->flags |= F3D_FLAG_BURNING;
      } else {
        s->flags &= (uint8_t)~F3D_FLAG_BURNING;
      }
      if (said & BURNT_OUT) f3d_push_event(world, handle, F3D_EVENT_BURNT_OUT);
      if (said & WENT_OUT) f3d_push_event(world, handle, F3D_EVENT_EXTINGUISHED);
      if (said & CAUGHT) f3d_push_event(world, handle, F3D_EVENT_IGNITED);
      continue;
    }
    /* A compound: its parts back, the body from them, and what happened to
     * the body as a whole — alight when its first part catches, out when
     * its last goes out, burnt out when no fuel is left in any. */
    for (uint32_t k = 0; k < hs.many[i]; k++) {
      world->lumps[s->lumps - 1u + k] = hs.h[hs.first[i] + k].l;
    }
    body_from_lumps(world, s);
    const int is = (s->flags & F3D_FLAG_BURNING) != 0;
    if (!was && is) {
      f3d_push_event(world, handle, F3D_EVENT_IGNITED);
    } else if (was && !is) {
      f3d_push_event(world, handle, s->fuel <= F3D_R(0.0)
                                        ? F3D_EVENT_BURNT_OUT
                                        : F3D_EVENT_EXTINGUISHED);
    }
  }
  f3d_free(hs.h);
  f3d_free(hs.first);
}
