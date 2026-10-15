/*
 * The compute sidecar over wgpu-native v29: what f3d_wgpu.h declares.
 *
 * Written against webgpu.h as the physics core's GPU passes are: string
 * views, callbacks given as info structs and fired from
 * wgpuInstanceProcessEvents, wgpuDevicePoll to wait. Every call that can
 * fail validation runs inside an error scope, so a kernel that does not
 * compile is a NULL and a sentence rather than a device error that ends the
 * process; an error nobody scoped lands in the device's uncaptured
 * callback, which keeps it for f3d_wgpu_take_error.
 */
#include "f3d_wgpu.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "webgpu/webgpu.h"
#include "webgpu/wgpu.h"

#define F3D_WGPU_MAX_BINDINGS 16u
/* Bind groups a kernel keeps; the least recently used goes first. */
#define F3D_WGPU_GROUPS 8u
/* Staging buffers kept for readback between reads. */
#define F3D_WGPU_STAGING 8u

typedef struct Staging {
  WGPUBuffer buffer;
  uint64_t size;
} Staging;

struct F3dWgpu {
  WGPUInstance instance;
  WGPUAdapter adapter;
  WGPUDevice device;
  WGPUQueue queue;
  char name[256];
  char error[1024];
  /* Every resource's id, never reused: what a kept bind group is keyed
   * by, so a buffer freed and another made at its address never matches. */
  uint64_t next_id;
  uint64_t tick;
  /* Every live kernel, so a released buffer leaves no group behind. */
  F3dWgpuKernel *kernels;
  Staging staging[F3D_WGPU_STAGING];
};

struct F3dWgpuBuffer {
  F3dWgpu *gpu;
  WGPUBuffer buffer;
  uint64_t size;
  uint64_t id;
};

struct F3dWgpuTexture {
  F3dWgpu *gpu;
  WGPUTexture texture;
  WGPUTextureView view;
  uint32_t width;
  uint32_t height;
  uint64_t id;
};

/* A bind group a kernel made, and what it binds. */
typedef struct Group {
  WGPUBindGroup group;
  uint64_t used;
  uint64_t ids[F3D_WGPU_MAX_BINDINGS];
  uint64_t offsets[F3D_WGPU_MAX_BINDINGS];
  uint64_t sizes[F3D_WGPU_MAX_BINDINGS];
} Group;

struct F3dWgpuKernel {
  F3dWgpu *gpu;
  WGPUShaderModule module;
  WGPUBindGroupLayout layout;
  WGPUPipelineLayout pipeline_layout;
  WGPUComputePipeline pipeline;
  uint32_t count;
  uint32_t kinds[F3D_WGPU_MAX_BINDINGS];
  Group groups[F3D_WGPU_GROUPS];
  F3dWgpuKernel *next;
};

struct F3dWgpuRead {
  F3dWgpu *gpu;
  WGPUBuffer staging;
  uint64_t capacity;
  uint64_t lead;
  uint64_t size;
  int done;
  int ok;
};

struct F3dWgpuPass {
  F3dWgpu *gpu;
  WGPUCommandEncoder encoder;
  WGPUComputePassEncoder pass;
  int failed;
};

static WGPUStringView view_of(const char *s) {
  WGPUStringView v;
  v.data = s;
  v.length = WGPU_STRLEN;
  return v;
}

static void copy_message(char *out, size_t capacity, WGPUStringView message) {
  if (capacity == 0) return;
  size_t n = 0;
  if (message.data != NULL) {
    n = message.length == WGPU_STRLEN ? strlen(message.data) : message.length;
  }
  if (n >= capacity) n = capacity - 1u;
  if (n > 0) memcpy(out, message.data, n);
  out[n] = '\0';
}

uint32_t f3d_wgpu_abi_version(void) { return F3D_WGPU_ABI_VERSION; }

typedef struct Waiting {
  int done;
  void *result;
} Waiting;

static void got_adapter(WGPURequestAdapterStatus status, WGPUAdapter adapter,
                        WGPUStringView message, void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPURequestAdapterStatus_Success ? (void *)adapter : NULL;
  w->done = 1;
}

static void got_device(WGPURequestDeviceStatus status, WGPUDevice device,
                       WGPUStringView message, void *userdata1, void *userdata2) {
  (void)message;
  (void)userdata2;
  Waiting *w = (Waiting *)userdata1;
  w->result = status == WGPURequestDeviceStatus_Success ? (void *)device : NULL;
  w->done = 1;
}

static void uncaptured(WGPUDevice const *device, WGPUErrorType type, WGPUStringView message,
                       void *userdata1, void *userdata2) {
  (void)device;
  (void)type;
  (void)userdata2;
  F3dWgpu *gpu = (F3dWgpu *)userdata1;
  copy_message(gpu->error, sizeof gpu->error, message);
}

/* Turns the instance's events over until [done] is set, or gives up. */
static void wait_for(WGPUInstance instance, const int *done) {
  for (int i = 0; i < 100000 && !*done; i++) wgpuInstanceProcessEvents(instance);
}

F3dWgpu *f3d_wgpu_open(void) {
  F3dWgpu *gpu = (F3dWgpu *)calloc(1, sizeof(F3dWgpu));
  if (gpu == NULL) return NULL;
  gpu->instance = wgpuCreateInstance(NULL);
  if (gpu->instance == NULL) {
    free(gpu);
    return NULL;
  }
  WGPURequestAdapterOptions options;
  memset(&options, 0, sizeof options);
  options.powerPreference = WGPUPowerPreference_HighPerformance;
  WGPURequestAdapterCallbackInfo adapter_info;
  memset(&adapter_info, 0, sizeof adapter_info);
  Waiting wa = {0, NULL};
  adapter_info.mode = WGPUCallbackMode_AllowProcessEvents;
  adapter_info.callback = got_adapter;
  adapter_info.userdata1 = &wa;
  wgpuInstanceRequestAdapter(gpu->instance, &options, adapter_info);
  wait_for(gpu->instance, &wa.done);
  gpu->adapter = (WGPUAdapter)wa.result;
  if (gpu->adapter == NULL) {
    f3d_wgpu_close(gpu);
    return NULL;
  }
  WGPUDeviceDescriptor descriptor;
  memset(&descriptor, 0, sizeof descriptor);
  descriptor.uncapturedErrorCallbackInfo.callback = uncaptured;
  descriptor.uncapturedErrorCallbackInfo.userdata1 = gpu;
  WGPURequestDeviceCallbackInfo device_info;
  memset(&device_info, 0, sizeof device_info);
  Waiting wd = {0, NULL};
  device_info.mode = WGPUCallbackMode_AllowProcessEvents;
  device_info.callback = got_device;
  device_info.userdata1 = &wd;
  wgpuAdapterRequestDevice(gpu->adapter, &descriptor, device_info);
  wait_for(gpu->instance, &wd.done);
  gpu->device = (WGPUDevice)wd.result;
  if (gpu->device == NULL) {
    f3d_wgpu_close(gpu);
    return NULL;
  }
  gpu->queue = wgpuDeviceGetQueue(gpu->device);
  WGPUAdapterInfo info;
  memset(&info, 0, sizeof info);
  if (wgpuAdapterGetInfo(gpu->adapter, &info) == WGPUStatus_Success) {
    copy_message(gpu->name, sizeof gpu->name, info.device);
    wgpuAdapterInfoFreeMembers(info);
  }
  return gpu;
}

void f3d_wgpu_close(F3dWgpu *gpu) {
  if (gpu == NULL) return;
  for (uint32_t i = 0; i < F3D_WGPU_STAGING; i++) {
    if (gpu->staging[i].buffer != NULL) wgpuBufferRelease(gpu->staging[i].buffer);
  }
  if (gpu->queue != NULL) wgpuQueueRelease(gpu->queue);
  if (gpu->device != NULL) wgpuDeviceRelease(gpu->device);
  if (gpu->adapter != NULL) wgpuAdapterRelease(gpu->adapter);
  if (gpu->instance != NULL) wgpuInstanceRelease(gpu->instance);
  free(gpu);
}

uint32_t f3d_wgpu_adapter_name(const F3dWgpu *gpu, char *out, uint32_t capacity) {
  const size_t n = strlen(gpu->name);
  if (capacity > 0) {
    const size_t k = n < capacity - 1u ? n : capacity - 1u;
    memcpy(out, gpu->name, k);
    out[k] = '\0';
  }
  return (uint32_t)n;
}

uint32_t f3d_wgpu_take_error(F3dWgpu *gpu, char *out, uint32_t capacity) {
  const size_t n = strlen(gpu->error);
  if (capacity > 0) {
    const size_t k = n < capacity - 1u ? n : capacity - 1u;
    memcpy(out, gpu->error, k);
    out[k] = '\0';
  }
  gpu->error[0] = '\0';
  return (uint32_t)n;
}

typedef struct Scope {
  int done;
  int failed;
  char message[512];
} Scope;

static void scope_popped(WGPUPopErrorScopeStatus status, WGPUErrorType type,
                         WGPUStringView message, void *userdata1, void *userdata2) {
  (void)userdata2;
  Scope *scope = (Scope *)userdata1;
  scope->failed = status != WGPUPopErrorScopeStatus_Success || type != WGPUErrorType_NoError;
  if (scope->failed) copy_message(scope->message, sizeof scope->message, message);
  scope->done = 1;
}

static void push_scope(F3dWgpu *gpu) {
  wgpuDevicePushErrorScope(gpu->device, WGPUErrorFilter_Validation);
}

/* Whether anything since the matching push failed validation, the message
 * kept in [scope]. */
static int pop_failed(F3dWgpu *gpu, Scope *scope) {
  memset(scope, 0, sizeof *scope);
  WGPUPopErrorScopeCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_AllowProcessEvents;
  info.callback = scope_popped;
  info.userdata1 = scope;
  wgpuDevicePopErrorScope(gpu->device, info);
  wait_for(gpu->instance, &scope->done);
  return !scope->done || scope->failed;
}

static uint64_t padded(uint64_t size) { return size < 16u ? 16u : (size + 3u) & ~(uint64_t)3u; }

F3dWgpuBuffer *f3d_wgpu_buffer_create(F3dWgpu *gpu, uint64_t size) {
  F3dWgpuBuffer *b = (F3dWgpuBuffer *)calloc(1, sizeof(F3dWgpuBuffer));
  if (b == NULL) return NULL;
  WGPUBufferDescriptor d;
  memset(&d, 0, sizeof d);
  d.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopySrc | WGPUBufferUsage_CopyDst;
  /* wgpu refuses a binding of nought bytes, and copies in fours. */
  d.size = padded(size);
  b->gpu = gpu;
  b->size = size;
  b->id = ++gpu->next_id;
  b->buffer = wgpuDeviceCreateBuffer(gpu->device, &d);
  if (b->buffer == NULL) {
    free(b);
    return NULL;
  }
  return b;
}

void f3d_wgpu_buffer_write(F3dWgpu *gpu, F3dWgpuBuffer *buffer, uint64_t offset,
                           const void *data, uint64_t size) {
  if (size == 0) return;
  /* The queue writes in fours: the tail is padded with what follows. */
  if ((offset & 3u) == 0 && (size & 3u) == 0) {
    wgpuQueueWriteBuffer(gpu->queue, buffer->buffer, offset, data, (size_t)size);
    return;
  }
  const uint64_t start = offset & ~(uint64_t)3u;
  const uint64_t end = (offset + size + 3u) & ~(uint64_t)3u;
  uint8_t *staged = (uint8_t *)calloc(1, (size_t)(end - start));
  if (staged == NULL) return;
  f3d_wgpu_buffer_read(gpu, buffer, start, staged, end - start);
  memcpy(staged + (offset - start), data, (size_t)size);
  wgpuQueueWriteBuffer(gpu->queue, buffer->buffer, start, staged, (size_t)(end - start));
  free(staged);
}

typedef struct Mapping {
  int done;
  int ok;
} Mapping;

static void mapped(WGPUMapAsyncStatus status, WGPUStringView message, void *userdata1,
                   void *userdata2) {
  (void)message;
  (void)userdata2;
  Mapping *m = (Mapping *)userdata1;
  m->ok = status == WGPUMapAsyncStatus_Success;
  m->done = 1;
}

/* A staging buffer of at least [size] bytes for reading back: one kept
 * from an earlier read when one is big enough, a new one otherwise. */
static Staging take_staging(F3dWgpu *gpu, uint64_t size) {
  int best = -1;
  for (uint32_t i = 0; i < F3D_WGPU_STAGING; i++) {
    const Staging s = gpu->staging[i];
    if (s.buffer == NULL || s.size < size) continue;
    if (best < 0 || s.size < gpu->staging[best].size) best = (int)i;
  }
  if (best >= 0) {
    Staging s = gpu->staging[best];
    gpu->staging[best].buffer = NULL;
    gpu->staging[best].size = 0;
    return s;
  }
  uint64_t capacity = 4096u;
  while (capacity < size) capacity *= 2u;
  WGPUBufferDescriptor d;
  memset(&d, 0, sizeof d);
  d.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst;
  d.size = capacity;
  Staging made = {wgpuDeviceCreateBuffer(gpu->device, &d), capacity};
  if (made.buffer == NULL) made.size = 0;
  return made;
}

/* Keeps [s] for the next read, in place of the smallest kept one when
 * every slot is taken. */
static void give_staging(F3dWgpu *gpu, Staging s) {
  int slot = 0;
  for (uint32_t i = 0; i < F3D_WGPU_STAGING; i++) {
    if (gpu->staging[i].buffer == NULL) {
      slot = (int)i;
      break;
    }
    if (gpu->staging[i].size < gpu->staging[slot].size) slot = (int)i;
  }
  if (gpu->staging[slot].buffer != NULL) {
    if (gpu->staging[slot].size >= s.size) {
      wgpuBufferRelease(s.buffer);
      return;
    }
    wgpuBufferRelease(gpu->staging[slot].buffer);
  }
  gpu->staging[slot] = s;
}

/* Maps [staging] for reading and waits; 1 when it is mapped. */
static int map_wait(F3dWgpu *gpu, WGPUBuffer staging, uint64_t size) {
  Mapping m = {0, 0};
  WGPUBufferMapCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_AllowProcessEvents;
  info.callback = mapped;
  info.userdata1 = &m;
  wgpuBufferMapAsync(staging, WGPUMapMode_Read, 0, (size_t)size, info);
  for (int i = 0; i < 100000 && !m.done; i++) {
    wgpuDevicePoll(gpu->device, 1, NULL);
    wgpuInstanceProcessEvents(gpu->instance);
  }
  return m.done && m.ok;
}

int f3d_wgpu_buffer_read(F3dWgpu *gpu, F3dWgpuBuffer *buffer, uint64_t offset, void *out,
                         uint64_t size) {
  if (size == 0) return 1;
  const uint64_t start = offset & ~(uint64_t)3u;
  const uint64_t span = ((offset + size + 3u) & ~(uint64_t)3u) - start;
  Staging staging = take_staging(gpu, span);
  if (staging.buffer == NULL) return 0;
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(gpu->device, NULL);
  wgpuCommandEncoderCopyBufferToBuffer(encoder, buffer->buffer, start, staging.buffer, 0, span);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  int ok = map_wait(gpu, staging.buffer, span);
  if (ok) {
    const uint8_t *data =
        (const uint8_t *)wgpuBufferGetConstMappedRange(staging.buffer, 0, (size_t)span);
    if (data == NULL) {
      ok = 0;
    } else {
      memcpy(out, data + (offset - start), (size_t)size);
    }
    wgpuBufferUnmap(staging.buffer);
  }
  give_staging(gpu, staging);
  return ok;
}

static void read_mapped(WGPUMapAsyncStatus status, WGPUStringView message, void *userdata1,
                        void *userdata2) {
  (void)message;
  (void)userdata2;
  F3dWgpuRead *r = (F3dWgpuRead *)userdata1;
  r->ok = status == WGPUMapAsyncStatus_Success;
  r->done = 1;
}

F3dWgpuRead *f3d_wgpu_read_begin(F3dWgpu *gpu, F3dWgpuBuffer *buffer, uint64_t offset,
                                 uint64_t size) {
  F3dWgpuRead *r = (F3dWgpuRead *)calloc(1, sizeof(F3dWgpuRead));
  if (r == NULL) return NULL;
  r->gpu = gpu;
  r->size = size;
  if (size == 0) {
    r->done = 1;
    r->ok = 1;
    return r;
  }
  const uint64_t start = offset & ~(uint64_t)3u;
  const uint64_t span = ((offset + size + 3u) & ~(uint64_t)3u) - start;
  r->lead = offset - start;
  Staging staging = take_staging(gpu, span);
  if (staging.buffer == NULL) {
    free(r);
    return NULL;
  }
  r->staging = staging.buffer;
  r->capacity = staging.size;
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(gpu->device, NULL);
  wgpuCommandEncoderCopyBufferToBuffer(encoder, buffer->buffer, start, staging.buffer, 0, span);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  WGPUBufferMapCallbackInfo info;
  memset(&info, 0, sizeof info);
  info.mode = WGPUCallbackMode_AllowProcessEvents;
  info.callback = read_mapped;
  info.userdata1 = r;
  wgpuBufferMapAsync(staging.buffer, WGPUMapMode_Read, 0, (size_t)span, info);
  return r;
}

int f3d_wgpu_read_poll(F3dWgpuRead *read, void *out, int wait) {
  F3dWgpu *gpu = read->gpu;
  for (int i = 0; !read->done && (i == 0 || (wait && i < 100000)); i++) {
    wgpuDevicePoll(gpu->device, wait ? 1 : 0, NULL);
    wgpuInstanceProcessEvents(gpu->instance);
  }
  if (!read->done) return 0;
  int ok = read->ok;
  if (read->staging != NULL) {
    if (ok) {
      const size_t span = (size_t)((read->lead + read->size + 3u) & ~(uint64_t)3u);
      const uint8_t *data =
          (const uint8_t *)wgpuBufferGetConstMappedRange(read->staging, 0, span);
      if (data == NULL) {
        ok = 0;
      } else if (out != NULL) {
        memcpy(out, data + read->lead, (size_t)read->size);
      }
      wgpuBufferUnmap(read->staging);
    }
    Staging back = {read->staging, read->capacity};
    give_staging(gpu, back);
  }
  free(read);
  return ok ? 1 : -1;
}

/* Lets go of every kept group that binds the resource [id]. */
static void forget_groups_of(F3dWgpu *gpu, uint64_t id) {
  for (F3dWgpuKernel *k = gpu->kernels; k != NULL; k = k->next) {
    for (uint32_t g = 0; g < F3D_WGPU_GROUPS; g++) {
      Group *group = &k->groups[g];
      if (group->group == NULL) continue;
      for (uint32_t i = 0; i < k->count; i++) {
        if (group->ids[i] != id) continue;
        wgpuBindGroupRelease(group->group);
        memset(group, 0, sizeof *group);
        break;
      }
    }
  }
}

void f3d_wgpu_buffer_release(F3dWgpuBuffer *buffer) {
  if (buffer == NULL) return;
  forget_groups_of(buffer->gpu, buffer->id);
  if (buffer->buffer != NULL) wgpuBufferRelease(buffer->buffer);
  free(buffer);
}

F3dWgpuTexture *f3d_wgpu_texture_create(F3dWgpu *gpu, uint32_t width, uint32_t height,
                                        int storage) {
  F3dWgpuTexture *t = (F3dWgpuTexture *)calloc(1, sizeof(F3dWgpuTexture));
  if (t == NULL) return NULL;
  WGPUTextureDescriptor d;
  memset(&d, 0, sizeof d);
  d.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc | WGPUTextureUsage_CopyDst |
            (storage ? WGPUTextureUsage_StorageBinding : 0);
  d.dimension = WGPUTextureDimension_2D;
  d.size.width = width;
  d.size.height = height;
  d.size.depthOrArrayLayers = 1;
  d.format = WGPUTextureFormat_RGBA8Unorm;
  d.mipLevelCount = 1;
  d.sampleCount = 1;
  t->gpu = gpu;
  t->width = width;
  t->height = height;
  t->id = ++gpu->next_id;
  t->texture = wgpuDeviceCreateTexture(gpu->device, &d);
  if (t->texture == NULL) {
    free(t);
    return NULL;
  }
  t->view = wgpuTextureCreateView(t->texture, NULL);
  return t;
}

void f3d_wgpu_texture_write(F3dWgpu *gpu, F3dWgpuTexture *texture, const void *rgba) {
  WGPUTexelCopyTextureInfo destination;
  memset(&destination, 0, sizeof destination);
  destination.texture = texture->texture;
  destination.aspect = WGPUTextureAspect_All;
  WGPUTexelCopyBufferLayout layout;
  memset(&layout, 0, sizeof layout);
  layout.bytesPerRow = texture->width * 4u;
  layout.rowsPerImage = texture->height;
  WGPUExtent3D size = {texture->width, texture->height, 1};
  wgpuQueueWriteTexture(gpu->queue, &destination, rgba,
                        (size_t)texture->width * texture->height * 4u, &layout, &size);
}

int f3d_wgpu_texture_read(F3dWgpu *gpu, F3dWgpuTexture *texture, void *rgba) {
  /* A copy to a buffer takes rows 256 bytes apart. */
  const uint32_t row = texture->width * 4u;
  const uint32_t stride = (row + 255u) & ~255u;
  const uint64_t span = (uint64_t)stride * texture->height;
  WGPUBufferDescriptor d;
  memset(&d, 0, sizeof d);
  d.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst;
  d.size = span;
  WGPUBuffer staging = wgpuDeviceCreateBuffer(gpu->device, &d);
  if (staging == NULL) return 0;
  WGPUTexelCopyTextureInfo source;
  memset(&source, 0, sizeof source);
  source.texture = texture->texture;
  source.aspect = WGPUTextureAspect_All;
  WGPUTexelCopyBufferInfo destination;
  memset(&destination, 0, sizeof destination);
  destination.buffer = staging;
  destination.layout.bytesPerRow = stride;
  destination.layout.rowsPerImage = texture->height;
  WGPUExtent3D size = {texture->width, texture->height, 1};
  WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(gpu->device, NULL);
  wgpuCommandEncoderCopyTextureToBuffer(encoder, &source, &destination, &size);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
  wgpuQueueSubmit(gpu->queue, 1, &commands);
  wgpuCommandBufferRelease(commands);
  wgpuCommandEncoderRelease(encoder);
  int ok = map_wait(gpu, staging, span);
  if (ok) {
    const uint8_t *data = (const uint8_t *)wgpuBufferGetConstMappedRange(staging, 0, (size_t)span);
    if (data == NULL) {
      ok = 0;
    } else {
      for (uint32_t y = 0; y < texture->height; y++) {
        memcpy((uint8_t *)rgba + (size_t)y * row, data + (size_t)y * stride, row);
      }
    }
    wgpuBufferUnmap(staging);
  }
  wgpuBufferRelease(staging);
  return ok;
}

void *f3d_wgpu_texture_native_metal(F3dWgpuTexture *texture) {
#if defined(__APPLE__)
  return wgpuTextureGetNativeMetalTexture(texture->texture);
#else
  (void)texture;
  return NULL;
#endif
}

void f3d_wgpu_texture_release(F3dWgpuTexture *texture) {
  if (texture == NULL) return;
  forget_groups_of(texture->gpu, texture->id);
  if (texture->view != NULL) wgpuTextureViewRelease(texture->view);
  if (texture->texture != NULL) wgpuTextureRelease(texture->texture);
  free(texture);
}

static void kernel_free(F3dWgpuKernel *k) {
  for (F3dWgpuKernel **at = &k->gpu->kernels; *at != NULL; at = &(*at)->next) {
    if (*at == k) {
      *at = k->next;
      break;
    }
  }
  for (uint32_t g = 0; g < F3D_WGPU_GROUPS; g++) {
    if (k->groups[g].group != NULL) wgpuBindGroupRelease(k->groups[g].group);
  }
  if (k->pipeline != NULL) wgpuComputePipelineRelease(k->pipeline);
  if (k->pipeline_layout != NULL) wgpuPipelineLayoutRelease(k->pipeline_layout);
  if (k->layout != NULL) wgpuBindGroupLayoutRelease(k->layout);
  if (k->module != NULL) wgpuShaderModuleRelease(k->module);
  free(k);
}

F3dWgpuKernel *f3d_wgpu_kernel_create(F3dWgpu *gpu, const char *wgsl, const char *entry,
                                      const uint32_t *kinds, uint32_t count, char *error,
                                      uint32_t capacity) {
  if (capacity > 0) error[0] = '\0';
  if (count > F3D_WGPU_MAX_BINDINGS) {
    if (capacity > 0) snprintf(error, capacity, "more than %u bindings", F3D_WGPU_MAX_BINDINGS);
    return NULL;
  }
  F3dWgpuKernel *k = (F3dWgpuKernel *)calloc(1, sizeof(F3dWgpuKernel));
  if (k == NULL) return NULL;
  k->gpu = gpu;
  k->count = count;
  push_scope(gpu);
  WGPUShaderSourceWGSL source;
  memset(&source, 0, sizeof source);
  source.chain.sType = WGPUSType_ShaderSourceWGSL;
  source.code = view_of(wgsl);
  WGPUShaderModuleDescriptor md;
  memset(&md, 0, sizeof md);
  md.nextInChain = &source.chain;
  k->module = wgpuDeviceCreateShaderModule(gpu->device, &md);
  WGPUBindGroupLayoutEntry entries[F3D_WGPU_MAX_BINDINGS];
  memset(entries, 0, sizeof entries);
  for (uint32_t i = 0; i < count; i++) {
    k->kinds[i] = kinds[i];
    entries[i].binding = i;
    entries[i].visibility = WGPUShaderStage_Compute;
    switch (kinds[i]) {
      case F3D_WGPU_STORAGE:
        entries[i].buffer.type = WGPUBufferBindingType_Storage;
        break;
      case F3D_WGPU_READ_ONLY:
        entries[i].buffer.type = WGPUBufferBindingType_ReadOnlyStorage;
        break;
      case F3D_WGPU_TEXTURE:
        entries[i].texture.sampleType = WGPUTextureSampleType_Float;
        entries[i].texture.viewDimension = WGPUTextureViewDimension_2D;
        break;
      default:
        entries[i].storageTexture.access = WGPUStorageTextureAccess_WriteOnly;
        entries[i].storageTexture.format = WGPUTextureFormat_RGBA8Unorm;
        entries[i].storageTexture.viewDimension = WGPUTextureViewDimension_2D;
        break;
    }
  }
  WGPUBindGroupLayoutDescriptor ld;
  memset(&ld, 0, sizeof ld);
  ld.entryCount = count;
  ld.entries = entries;
  k->layout = wgpuDeviceCreateBindGroupLayout(gpu->device, &ld);
  WGPUPipelineLayoutDescriptor pld;
  memset(&pld, 0, sizeof pld);
  pld.bindGroupLayoutCount = 1;
  pld.bindGroupLayouts = &k->layout;
  k->pipeline_layout = wgpuDeviceCreatePipelineLayout(gpu->device, &pld);
  WGPUComputePipelineDescriptor pd;
  memset(&pd, 0, sizeof pd);
  pd.layout = k->pipeline_layout;
  pd.compute.module = k->module;
  pd.compute.entryPoint = view_of(entry);
  k->pipeline = wgpuDeviceCreateComputePipeline(gpu->device, &pd);
  Scope scope;
  const int failed = pop_failed(gpu, &scope);
  if (failed || k->module == NULL || k->layout == NULL || k->pipeline_layout == NULL ||
      k->pipeline == NULL) {
    if (capacity > 0) {
      snprintf(error, capacity, "%s",
               scope.message[0] != '\0' ? scope.message : "the kernel did not validate");
    }
    kernel_free(k);
    return NULL;
  }
  k->next = gpu->kernels;
  gpu->kernels = k;
  return k;
}

void f3d_wgpu_kernel_release(F3dWgpuKernel *kernel) {
  if (kernel != NULL) kernel_free(kernel);
}

F3dWgpuPass *f3d_wgpu_pass_begin(F3dWgpu *gpu) {
  F3dWgpuPass *p = (F3dWgpuPass *)calloc(1, sizeof(F3dWgpuPass));
  if (p == NULL) return NULL;
  p->gpu = gpu;
  push_scope(gpu);
  p->encoder = wgpuDeviceCreateCommandEncoder(gpu->device, NULL);
  p->pass = wgpuCommandEncoderBeginComputePass(p->encoder, NULL);
  return p;
}

int f3d_wgpu_pass_dispatch(F3dWgpuPass *pass, F3dWgpuKernel *kernel, void *const *resources,
                           const uint64_t *offsets, const uint64_t *sizes, uint32_t count,
                           uint32_t x, uint32_t y, uint32_t z) {
  if (count != kernel->count) {
    pass->failed = 1;
    return 0;
  }
  F3dWgpu *gpu = pass->gpu;
  Group key;
  memset(&key, 0, sizeof key);
  WGPUBindGroupEntry entries[F3D_WGPU_MAX_BINDINGS];
  memset(entries, 0, sizeof entries);
  for (uint32_t i = 0; i < count; i++) {
    entries[i].binding = i;
    if (kernel->kinds[i] == F3D_WGPU_STORAGE || kernel->kinds[i] == F3D_WGPU_READ_ONLY) {
      const F3dWgpuBuffer *b = (const F3dWgpuBuffer *)resources[i];
      entries[i].buffer = b->buffer;
      entries[i].offset = offsets[i];
      const uint64_t whole = padded(b->size) - offsets[i];
      entries[i].size = sizes[i] == 0 ? whole : sizes[i];
      key.ids[i] = b->id;
      key.offsets[i] = entries[i].offset;
      key.sizes[i] = entries[i].size;
    } else {
      const F3dWgpuTexture *t = (const F3dWgpuTexture *)resources[i];
      entries[i].textureView = t->view;
      key.ids[i] = t->id;
    }
  }
  /* The same resources and ranges as a group the kernel kept: that group,
   * rather than a new one each dispatch. */
  WGPUBindGroup group = NULL;
  uint32_t slot = 0;
  for (uint32_t g = 0; g < F3D_WGPU_GROUPS; g++) {
    Group *kept = &kernel->groups[g];
    if (kept->group != NULL && memcmp(kept->ids, key.ids, sizeof key.ids) == 0 &&
        memcmp(kept->offsets, key.offsets, sizeof key.offsets) == 0 &&
        memcmp(kept->sizes, key.sizes, sizeof key.sizes) == 0) {
      kept->used = ++gpu->tick;
      group = kept->group;
      break;
    }
    /* An empty slot first, else the least recently used. */
    if (kernel->groups[slot].group != NULL &&
        (kept->group == NULL || kept->used < kernel->groups[slot].used)) {
      slot = g;
    }
  }
  if (group == NULL) {
    WGPUBindGroupDescriptor bd;
    memset(&bd, 0, sizeof bd);
    bd.layout = kernel->layout;
    bd.entryCount = count;
    bd.entries = entries;
    group = wgpuDeviceCreateBindGroup(gpu->device, &bd);
    if (group == NULL) {
      pass->failed = 1;
      return 0;
    }
    Group *into = &kernel->groups[slot];
    if (into->group != NULL) wgpuBindGroupRelease(into->group);
    *into = key;
    into->group = group;
    into->used = ++gpu->tick;
  }
  wgpuComputePassEncoderSetPipeline(pass->pass, kernel->pipeline);
  wgpuComputePassEncoderSetBindGroup(pass->pass, 0, group, 0, NULL);
  wgpuComputePassEncoderDispatchWorkgroups(pass->pass, x, y, z);
  return 1;
}

int f3d_wgpu_pass_submit(F3dWgpuPass *pass) {
  F3dWgpu *gpu = pass->gpu;
  wgpuComputePassEncoderEnd(pass->pass);
  wgpuComputePassEncoderRelease(pass->pass);
  WGPUCommandBuffer commands = wgpuCommandEncoderFinish(pass->encoder, NULL);
  if (commands != NULL) {
    wgpuQueueSubmit(gpu->queue, 1, &commands);
    wgpuCommandBufferRelease(commands);
  }
  wgpuCommandEncoderRelease(pass->encoder);
  Scope scope;
  const int failed = pop_failed(gpu, &scope) || pass->failed;
  if (failed && scope.message[0] != '\0') {
    snprintf(gpu->error, sizeof gpu->error, "%s", scope.message);
  }
  free(pass);
  return !failed;
}

void f3d_wgpu_finish(F3dWgpu *gpu) { wgpuDevicePoll(gpu->device, 1, NULL); }
