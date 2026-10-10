/*
 * The physics core's GPU passes, through wgpu-native — P9, phase 10.
 *
 * A library of its own, beside the core: the core has no dependencies and
 * builds for the browser as it is, and this one links wgpu-native, which a
 * build hook fetches for the target. What runs here is visual — particles
 * now, cloth and smoke and the bodies a frame late as they come — and not
 * the game's state, which stays on the CPU and the same bits everywhere: a
 * GPU's arithmetic is its own.
 *
 * Every function is synchronous to the caller. A step is queued and
 * submitted; a read waits for the GPU and copies the answer back.
 */
#ifndef F3D_GPU_H_
#define F3D_GPU_H_

#include <stdint.h>

#if defined(_WIN32)
#define F3D_GPU_API __declspec(dllexport)
#else
#define F3D_GPU_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Bumped whenever a function's meaning or signature changes. */
#define F3D_GPU_ABI_VERSION 4u

typedef struct F3dGpu F3dGpu;
typedef struct F3dGpuParticles F3dGpuParticles;
typedef struct F3dGpuDebris F3dGpuDebris;
typedef struct F3dGpuCloth F3dGpuCloth;
typedef struct F3dGpuFluid F3dGpuFluid;

/* How particles move, as f3d_particles_step reads F3dParticleForces. */
typedef struct F3dGpuParticleForces {
  float gravity[3];
  float wind[3];
  float drag;
  float floor_y;
  float restitution;
  float friction;
} F3dGpuParticleForces;

F3D_GPU_API uint32_t f3d_gpu_abi_version(void);

/* A device on the best adapter there is, headless; null where there is no
 * adapter — a machine with no GPU, or a driver wgpu cannot use. */
F3D_GPU_API F3dGpu *f3d_gpu_create(void);
F3D_GPU_API void f3d_gpu_destroy(F3dGpu *gpu);

/* The adapter's name, null-terminated, into [out]: up to [capacity] bytes;
 * returns its whole length. */
F3D_GPU_API uint32_t f3d_gpu_adapter_name(const F3dGpu *gpu, char *out,
                                          uint32_t capacity);

/* [capacity] particle slots on [gpu], all dead; null for none or no
 * memory. Freed before their GPU. */
F3D_GPU_API F3dGpuParticles *f3d_gpu_particles_create(F3dGpu *gpu,
                                                      uint32_t capacity);
F3D_GPU_API void f3d_gpu_particles_destroy(F3dGpuParticles *particles);

/* As f3d_particles_emit: [count] particles of seven floats into the next
 * slots, round and round; returns the slot the first went into. */
F3D_GPU_API uint32_t f3d_gpu_particles_emit(F3dGpuParticles *particles,
                                            const float *data, uint32_t count);

/* [steps] steps of [dt], as f3d_particles_step takes them, queued in one
 * submission. */
F3D_GPU_API void f3d_gpu_particles_step(F3dGpuParticles *particles,
                                        const F3dGpuParticleForces *forces,
                                        float dt, uint32_t steps);

/* Every slot, four floats apiece as f3d_particles_read writes them, into
 * [out], waiting for the GPU; returns how many, nought when the read
 * failed. */
F3D_GPU_API uint32_t f3d_gpu_particles_read(F3dGpuParticles *particles,
                                            float *out, uint32_t capacity);

/* Debris, as f3d_debris steps it: F3dDebrisSettings, in floats. */
typedef struct F3dGpuDebrisSettings {
  float gravity[3];
  float friction;
  float restitution;
  float linear_damping;
  float angular_damping;
  float max_speed;
  uint32_t substeps;
  uint32_t iterations;
} F3dGpuDebrisSettings;

/* [capacity] empty debris slots on [gpu]; null for none or no memory. */
F3D_GPU_API F3dGpuDebris *f3d_gpu_debris_create(F3dGpu *gpu, uint32_t capacity);
F3D_GPU_API void f3d_gpu_debris_destroy(F3dGpuDebris *debris);

/* As f3d_debris_add and f3d_debris_set_statics. */
F3D_GPU_API uint32_t f3d_gpu_debris_add(F3dGpuDebris *debris, const float *data,
                                        uint32_t count);
F3D_GPU_API int f3d_gpu_debris_set_statics(F3dGpuDebris *debris, const float *data,
                                           uint32_t count);

/* Queues a step of [dt] and, after it, the bodies' copy back. */
F3D_GPU_API void f3d_gpu_debris_step(F3dGpuDebris *debris,
                                     const F3dGpuDebrisSettings *settings, float dt);

/* The bodies as f3d_debris_read writes them, into [out], from the latest
 * step whose copy has come back and was not read yet: returns that step,
 * counted from one, and nought, leaving [out] alone, when there is none.
 * A frame late, without [wait]: the step queued last is still on the GPU.
 * With [wait], the last step's, waited for. */
F3D_GPU_API uint64_t f3d_gpu_debris_read(F3dGpuDebris *debris, float *out,
                                         uint32_t capacity, int wait);

/* Cloth, as f3d_cloth steps it: F3dClothSettings, in floats. */
typedef struct F3dGpuClothSettings {
  float gravity[3];
  float wind[3];
  float drag;
  float damping;
  float floor_y;
  float thickness;
  float friction;
  uint32_t substeps;
} F3dGpuClothSettings;

/* A cloth of [point_count] points, four floats apiece as f3d_cloth_create
 * takes them, held by the constraints f3d_cloth_edges gives for the same
 * cloth: [pairs], [rest], [compliance], [edge_count] of them, coloured as
 * [colour_start] says, [colour_count] colours. Null for no points, a pair
 * out of range, colours that do not end at the edges' count, or no
 * memory. */
F3D_GPU_API F3dGpuCloth *f3d_gpu_cloth_create(F3dGpu *gpu, const float *points,
                                              uint32_t point_count, const uint32_t *pairs,
                                              const float *rest, const float *compliance,
                                              uint32_t edge_count, const uint32_t *colour_start,
                                              uint32_t colour_count);
F3D_GPU_API void f3d_gpu_cloth_destroy(F3dGpuCloth *cloth);

/* As f3d_cloth_set_balls and f3d_cloth_move_point. */
F3D_GPU_API int f3d_gpu_cloth_set_balls(F3dGpuCloth *cloth, const float *balls, uint32_t count);
F3D_GPU_API void f3d_gpu_cloth_move_point(F3dGpuCloth *cloth, uint32_t index, float x, float y,
                                          float z);

/* Queues a step of [dt] and, after it, the points' copy back. */
F3D_GPU_API void f3d_gpu_cloth_step(F3dGpuCloth *cloth, const F3dGpuClothSettings *settings,
                                    float dt);

/* The points as f3d_cloth_read writes them, read as f3d_gpu_debris_read
 * reads: the step they are from, nought for none new. */
F3D_GPU_API uint64_t f3d_gpu_cloth_read(F3dGpuCloth *cloth, float *out, uint32_t capacity,
                                        int wait);

/* Fluid, as f3d_fluid steps it: F3dFluidSettings, in floats. */
typedef struct F3dGpuFluidSettings {
  float gravity[3];
  float tank_min[3];
  float tank_max[3];
  float viscosity;
  float relaxation;
  uint32_t substeps;
  uint32_t iterations;
} F3dGpuFluidSettings;

/* As f3d_fluid_create: room for [capacity] particles [spacing] apart at
 * rest, and the same density at rest, worked out the same way. */
F3D_GPU_API F3dGpuFluid *f3d_gpu_fluid_create(F3dGpu *gpu, uint32_t capacity, float spacing);
F3D_GPU_API void f3d_gpu_fluid_destroy(F3dGpuFluid *fluid);
F3D_GPU_API float f3d_gpu_fluid_rest_density(const F3dGpuFluid *fluid);

/* As f3d_fluid_add. */
F3D_GPU_API uint32_t f3d_gpu_fluid_add(F3dGpuFluid *fluid, const float *data, uint32_t count);

/* Queues a step of [dt] and, after it, the particles' copy back. */
F3D_GPU_API void f3d_gpu_fluid_step(F3dGpuFluid *fluid, const F3dGpuFluidSettings *settings,
                                    float dt);

/* The particles as f3d_fluid_read writes them, read as f3d_gpu_debris_read
 * reads: the step they are from, nought for none new. */
F3D_GPU_API uint64_t f3d_gpu_fluid_read(F3dGpuFluid *fluid, float *out, uint32_t capacity,
                                        int wait);

#ifdef __cplusplus
}
#endif

#endif /* F3D_GPU_H_ */
