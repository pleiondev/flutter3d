#ifndef FLUTTER_PLUGIN_FLUTTER3D_POINTER_LOCK_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER3D_POINTER_LOCK_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _PointerLockPlugin Flutter3dPointerLockPlugin;
typedef struct {
  GObjectClass parent_class;
} Flutter3dPointerLockPluginClass;

FLUTTER_PLUGIN_EXPORT GType flutter3d_pointer_lock_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void flutter3d_pointer_lock_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FLUTTER3D_POINTER_LOCK_PLUGIN_H_
