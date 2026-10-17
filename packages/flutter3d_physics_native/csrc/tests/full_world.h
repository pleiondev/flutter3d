/*
 * A world of every subsystem the core holds, for the C tests that need
 * one: test_snapshot.c reads it field by field, and test_snapshot_fixture.c
 * minted the committed 1.0 snapshots from it.
 */
#ifndef F3D_TEST_FULL_WORLD_H_
#define F3D_TEST_FULL_WORLD_H_

#include <math.h>
#include <stdlib.h>

#include "check.h"

/* A stream off a cliff into a pond, [nx] × 24 cells of a quarter metre
 * from (ox, 0, 0): spray in the air and bubbles under the falls. */
static F3dShallow falls(F3dWorld *w, f3d_real ox, int nx) {
  f3d_real *ground = (f3d_real *)malloc((size_t)nx * 24 * sizeof(f3d_real));
  for (int j = 0; j < 24; j++) {
    for (int i = 0; i < nx; i++) {
      const double x = i * 0.25;
      const double channel = 0.4 * fabs((j - 12) * 0.25);
      ground[i + j * nx] = (f3d_real)(x < 6 ? 4.0 - 0.1 * x + channel
                                            : 0.02 * fabs(x - 9) + 0.2 * channel);
    }
  }
  const F3dShallow water =
      f3d_shallow_create(w, (uint32_t)nx, 24, F3D_R(0.25), ox, 0, 0, ground);
  free(ground);
  f3d_shallow_fill(w, water, ox + F3D_R(6.2), 0, ox + 12, 6, F3D_R(0.8));
  f3d_shallow_set_source(w, water, 0, ox + 1, 3, F3D_R(0.5), F3D_R(0.05));
  f3d_shallow_set_outlet(w, water, 0, ox + F3D_R(11.5), 3, F3D_R(0.75), 1, 0);
  return water;
}

/* Every subsystem the world holds at once: shapes of every kind on a
 * floor, a hull, a mesh and a compound, joints, a car, a chain of links,
 * fire and a burner, a stream with its spray and bubbles, and the water's
 * rest set. Stepped until each has something to say. */
static F3dWorld *full_world(void) {
  F3dWorld *w = f3d_world_create();
  f3d_world_shift_origin(w, -77.25, 3.5, 2e4);
  const f3d_real grid[12] = {1, 0, 0, 0, 0, 2, -1, 0, 0, 0, 3, 0};
  f3d_world_set_wind_grid(w, -20, 0, -5, 20, 2, 1, 2, grid);
  f3d_world_set_water_rest(w, F3D_R(1e-3), F3D_R(2.0));
  F3dMaterial wood;
  f3d_material_preset(F3D_MATERIAL_WOOD, &wood);

  const F3dBody floor = f3d_body_create(w, F3D_BODY_FIXED, -10, F3D_R(-0.5), 0, 0);
  f3d_body_set_shape(w, floor, F3D_SHAPE_BOX, 15, F3D_R(0.5), 15);
  for (int i = 0; i < 6; i++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(-6.0) + i,
                                      F3D_R(0.5) + F3D_R(0.3) * i, 4, 1);
    f3d_body_set_shape(w, b, (F3dShapeKind)(1 + i % 3), F3D_R(0.2),
                       F3D_R(0.3), F3D_R(0.1));
    f3d_body_set_angular_velocity(w, b, F3D_R(0.3) * i, 1, F3D_R(-0.7));
    f3d_body_set_material(w, b, &wood);
    if (i == 1) f3d_body_set_temperature(w, b, 700);
    if (i == 2) f3d_body_add_water(w, b, F3D_R(0.02));
    if (i == 3) f3d_body_set_burner(w, b, F3D_R(0.001), NULL);
  }

  const f3d_real corners[18] = {F3D_R(0.3), 0, 0, F3D_R(-0.3), 0, 0,
                                0, F3D_R(0.4), 0, 0, F3D_R(-0.2), 0,
                                0, 0, F3D_R(0.3), 0, 0, F3D_R(-0.3)};
  const uint32_t hull = f3d_world_create_hull(w, corners, 6);
  CHECK(hull != 0);
  const F3dBody gem = f3d_body_create(w, F3D_BODY_DYNAMIC, -2, 1, -2, 2);
  f3d_body_set_hull(w, gem, hull);

  const f3d_real ramp[12] = {-24, 0, -4, -18, 1, -4, -18, 1, 4, -24, 0, 4};
  const uint32_t tris[6] = {0, 2, 1, 0, 3, 2};
  const uint32_t mesh = f3d_world_create_mesh(w, ramp, 4, tris, 2);
  CHECK(mesh != 0);
  const F3dBody ground = f3d_body_create(w, F3D_BODY_FIXED, 0, F3D_R(0.1), 0, 0);
  f3d_body_set_mesh(w, ground, mesh);
  const F3dBody slider = f3d_body_create(w, F3D_BODY_DYNAMIC, -20, 2, 0, 1);
  f3d_body_set_shape(w, slider, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.2), F3D_R(0.2));

  const uint32_t kinds[2] = {F3D_SHAPE_BOX, F3D_SHAPE_HULL};
  const uint32_t hulls[2] = {0, hull};
  const f3d_real parts[22] = {F3D_R(0.3), F3D_R(0.1), F3D_R(0.1), 0, 0, 0, 0, 0, 0, 0, 1,
                              0, 0, 0, 0, F3D_R(0.4), 0, 0, 0, 0, 0, 1};
  const uint32_t compound = f3d_world_create_compound(w, kinds, hulls, parts, 2);
  CHECK(compound != 0);
  const F3dBody beam = f3d_body_create(w, F3D_BODY_DYNAMIC, -3, 2, 2, 3);
  f3d_body_set_compound(w, beam, compound);
  f3d_body_set_material(w, beam, &wood);
  f3d_body_set_temperature(w, beam, 650);

  const F3dBody pa = f3d_body_create(w, F3D_BODY_DYNAMIC, -8, 2, -3, 1);
  const F3dBody pb = f3d_body_create(w, F3D_BODY_DYNAMIC, F3D_R(-7.5), 2, -3, 1);
  f3d_body_set_shape(w, pa, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.1), F3D_R(0.1));
  f3d_body_set_shape(w, pb, F3D_SHAPE_BOX, F3D_R(0.2), F3D_R(0.1), F3D_R(0.1));
  CHECK(f3d_joint_create(w, F3D_JOINT_REVOLUTE, pa, pb, F3D_R(-7.75), 2, -3, 0, 0, 1) != 0);
  CHECK(f3d_joint_create_distance(w, pa, floor, -8, 2, -3, -8, 3, -3) != 0);

  const F3dBody chassis = f3d_body_create(w, F3D_BODY_DYNAMIC, -12, 1, 6, 1200);
  f3d_body_set_shape(w, chassis, F3D_SHAPE_BOX, F3D_R(0.9), F3D_R(0.3), F3D_R(2.0));
  const F3dVehicle car = f3d_vehicle_create(w, chassis, 0, 1, 0, 0, 0, 1);
  CHECK(car != 0);
  for (int i = 0; i < 4; i++) {
    const f3d_real wheel[F3D_WHEEL_FLOATS] = {
        i % 2 ? F3D_R(0.8) : F3D_R(-0.8), F3D_R(-0.2), i < 2 ? F3D_R(1.3) : F3D_R(-1.3),
        F3D_R(0.4), F3D_R(0.35), F3D_R(40000.0), F3D_R(3000.0), 1};
    CHECK(f3d_vehicle_add_wheel(w, car, wheel) == i);
  }
  f3d_vehicle_set_wheel(w, car, 0, F3D_R(0.2), 800, 0);

  const F3dBody top = f3d_body_create(w, F3D_BODY_FIXED, -14, 5, -6, 0);
  const F3dMultibody chain = f3d_multibody_create(w, top);
  CHECK(chain != 0);
  for (int k = 1; k <= 3; k++) {
    const F3dBody b = f3d_body_create(w, F3D_BODY_DYNAMIC,
                                      F3D_R(-14.0) + (f3d_real)k * F3D_R(0.4), 5, -6, 1);
    f3d_body_set_shape(w, b, F3D_SHAPE_SPHERE, F3D_R(0.1), 0, 0);
    CHECK(f3d_multibody_add_link(w, chain, (uint32_t)(k - 1), b,
                                 k % 2 ? F3D_JOINT_REVOLUTE : F3D_JOINT_SPHERICAL,
                                 F3D_R(-14.0) + (f3d_real)(k - 1) * F3D_R(0.4), 5,
                                 -6, 0, 0, 1) == k);
  }

  falls(w, 10, 48);
  const F3dBody cork = f3d_body_create(w, F3D_BODY_DYNAMIC, 19, 2, 3, F3D_R(0.5));
  f3d_body_set_shape(w, cork, F3D_SHAPE_SPHERE, F3D_R(0.08), 0, 0);

  for (int i = 0; i < 600; i++) {
    f3d_world_step(w, F3D_R(1.0 / 60.0));
    if (i > 120 && w->s.spray_count > 0 && w->s.bubble_count > 0) break;
  }
  return w;
}

#endif  /* F3D_TEST_FULL_WORLD_H_ */
