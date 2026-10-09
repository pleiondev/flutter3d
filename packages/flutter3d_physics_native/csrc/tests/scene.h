/*
 * A world of every kind of shape, for the C tests that step one world
 * several ways and compare: a mesh for ground, a hull, boxes, balls,
 * capsules, cylinders and a chain on hinges, some filtered.
 */
#ifndef F3D_TEST_SCENE_H_
#define F3D_TEST_SCENE_H_

#include "f3d_internal.h"
#include "f3d_physics.h"

static F3dWorld *scene(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_set_gravity(w, 0, -F3D_STANDARD_GRAVITY, 0);
  /* Ground: a mesh of a gentle bowl, twelve metres across. */
  enum { SIDE = 13 };
  f3d_real v[SIDE * SIDE * 3];
  uint32_t t[(SIDE - 1) * (SIDE - 1) * 6];
  for (int j = 0; j < SIDE; j++) {
    for (int i = 0; i < SIDE; i++) {
      const f3d_real x = (f3d_real)(i - 6), z = (f3d_real)(j - 6);
      v[(j * SIDE + i) * 3] = x;
      v[(j * SIDE + i) * 3 + 1] = (x * x + z * z) * F3D_R(0.02);
      v[(j * SIDE + i) * 3 + 2] = z;
    }
  }
  uint32_t n = 0;
  for (int j = 0; j + 1 < SIDE; j++) {
    for (int i = 0; i + 1 < SIDE; i++) {
      const uint32_t a = (uint32_t)(j * SIDE + i);
      const uint32_t q[6] = {a, a + SIDE, a + 1, a + 1, a + SIDE, a + SIDE + 1};
      for (int k = 0; k < 6; k++) t[n++] = q[k];
    }
  }
  const uint32_t mesh = f3d_world_create_mesh(w, v, SIDE * SIDE, t, n / 3);
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, 0, 0, 0, 0);
  f3d_body_set_mesh(w, ground, mesh);
  const f3d_real rock[18] = {F3D_R(0.3), 0, 0, F3D_R(-0.3), 0, 0, 0, F3D_R(0.4), 0,
                             0, F3D_R(-0.2), 0, 0, 0, F3D_R(0.3), 0, 0, F3D_R(-0.3)};
  const uint32_t hull = f3d_world_create_hull(w, rock, 6);
  /* Three hundred bodies of five kinds in a loose block above it. */
  for (int i = 0; i < 300; i++) {
    const f3d_real x = (f3d_real)(i % 10) * F3D_R(0.7) - F3D_R(3.2);
    const f3d_real z = (f3d_real)((i / 10) % 10) * F3D_R(0.7) - F3D_R(3.2);
    const f3d_real y = F3D_R(1.5) + (f3d_real)(i / 100) * F3D_R(0.8);
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, x + (f3d_real)(i % 3) * F3D_R(0.05), y, z, 1);
    switch (i % 5) {
      case 0: f3d_body_set_shape(w, b, F3D_SHAPE_BOX, F3D_R(0.25), F3D_R(0.2), F3D_R(0.3)); break;
      case 1: f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.25), 0, 0); break;
      case 2: f3d_body_set_shape(w, b, F3D_SHAPE_CAPSULE, F3D_R(0.15), F3D_R(0.2), 0); break;
      case 3: f3d_body_set_shape(w, b, F3D_SHAPE_CYLINDER, F3D_R(0.2), F3D_R(0.2), 0); break;
      default: f3d_body_set_hull(w, b, hull); break;
    }
    f3d_body_set_angular_velocity(w, b, (f3d_real)(i % 7) * F3D_R(0.3), 0, (f3d_real)(i % 4) * F3D_R(0.2));
    if (i % 11 == 0) f3d_body_set_collision_filter(w, b, 2u, ~1u);
  }
  /* A chain of eight links on hinges hanging from a fixed post. */
  F3dBody last = f3d_body_create(w, F3D_BODY_FIXED, 4, 5, 0, 0);
  f3d_body_set_shape(w, last, F3D_SHAPE_BOX, F3D_R(0.1), F3D_R(0.1), F3D_R(0.1));
  for (int k = 0; k < 8; k++) {
    const F3dBody link = f3d_body_create(w, F3D_BODY_DYNAMIC, 4 + (f3d_real)(k + 1) * F3D_R(0.4), 5, 0, F3D_R(0.5));
    f3d_body_set_shape(w, link, F3D_SHAPE_BOX, F3D_R(0.18), F3D_R(0.05), F3D_R(0.05));
    f3d_joint_create(w, F3D_JOINT_REVOLUTE, last, link, 4 + (f3d_real)k * F3D_R(0.4) + F3D_R(0.2), 5, 0, 0, 0, 1);
    last = link;
  }
  return w;
}

#endif /* F3D_TEST_SCENE_H_ */
