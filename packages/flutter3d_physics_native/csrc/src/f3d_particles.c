/*
 * Particles on the CPU — P9, phase 10: the reference for the GPU's, and
 * the fallback where there is none. See f3d_physics.h for what they do;
 * the WGSL in f3d_gpu.c does the same, line for line.
 */
#include "f3d_internal.h"

typedef struct Particle {
  F3dVec3 position;
  f3d_real life;
  F3dVec3 velocity;
  f3d_real reserved;
} Particle;

struct F3dParticles {
  Particle *slots;
  uint32_t capacity;
  /* The slot the next particle takes. */
  uint32_t next;
};

F3dParticles *f3d_particles_create(uint32_t capacity) {
  if (capacity == 0 || capacity > (1u << 26)) return NULL;
  F3dParticles *p = (F3dParticles *)f3d_alloc(sizeof(F3dParticles));
  if (p == NULL) return NULL;
  p->slots = (Particle *)f3d_alloc((size_t)capacity * sizeof(Particle));
  if (p->slots == NULL) {
    f3d_free(p);
    return NULL;
  }
  f3d_zero(p->slots, (size_t)capacity * sizeof(Particle));
  p->capacity = capacity;
  p->next = 0;
  return p;
}

void f3d_particles_destroy(F3dParticles *particles) {
  if (particles == NULL) return;
  f3d_free(particles->slots);
  f3d_free(particles);
}

uint32_t f3d_particles_capacity(const F3dParticles *particles) {
  return particles->capacity;
}

uint32_t f3d_particles_emit(F3dParticles *particles, const f3d_real *data,
                            uint32_t count) {
  const uint32_t first = particles->next;
  for (uint32_t i = 0; i < count; i++) {
    Particle *s = &particles->slots[particles->next];
    const f3d_real *d = data + (size_t)i * 7u;
    s->position = f3d_v3(d[0], d[1], d[2]);
    s->velocity = f3d_v3(d[3], d[4], d[5]);
    s->life = d[6];
    particles->next = (particles->next + 1u) % particles->capacity;
  }
  return first;
}

void f3d_particles_step(F3dParticles *particles, const F3dParticleForces *f,
                        f3d_real dt) {
  if (!(f3d_finite(dt) && dt > F3D_R(0.0))) return;
  const F3dVec3 g = f3d_v3(f->gravity[0], f->gravity[1], f->gravity[2]);
  const F3dVec3 w = f3d_v3(f->wind[0], f->wind[1], f->wind[2]);
  const f3d_real keep = F3D_R(1.0) / (F3D_R(1.0) + f->drag * dt);
  for (uint32_t i = 0; i < particles->capacity; i++) {
    Particle *s = &particles->slots[i];
    if (!(s->life > F3D_R(0.0))) continue;
    F3dVec3 v = f3d_madd(s->velocity, g, dt);
    v = f3d_add(w, f3d_scale(f3d_sub(v, w), keep));
    F3dVec3 x = f3d_madd(s->position, v, dt);
    if (x.y < f->floor_y) {
      x.y = f->floor_y;
      if (v.y < F3D_R(0.0)) v.y = -v.y * f->restitution;
      const f3d_real slide = F3D_R(1.0) - f->friction;
      v.x *= slide;
      v.z *= slide;
    }
    s->position = x;
    s->velocity = v;
    s->life -= dt;
  }
}

uint32_t f3d_particles_read(const F3dParticles *particles, f3d_real *out,
                            uint32_t capacity) {
  const uint32_t n = capacity < particles->capacity ? capacity : particles->capacity;
  for (uint32_t i = 0; i < n; i++) {
    const Particle *s = &particles->slots[i];
    out[i * 4u] = s->position.x;
    out[i * 4u + 1u] = s->position.y;
    out[i * 4u + 2u] = s->position.z;
    out[i * 4u + 3u] = s->life;
  }
  return n;
}
