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
#define F3D_GPU_ABI_VERSION 1u

typedef struct F3dGpu F3dGpu;
typedef struct F3dGpuParticles F3dGpuParticles;

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

#ifdef __cplusplus
}
#endif

#endif /* F3D_GPU_H_ */
