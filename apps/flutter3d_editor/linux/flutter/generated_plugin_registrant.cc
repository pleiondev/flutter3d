//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <file_selector_linux/file_selector_plugin.h>
#include <flutter3d_pointer_lock/flutter3d_pointer_lock_plugin.h>
#include <pad_input/pad_input_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) file_selector_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSelectorPlugin");
  file_selector_plugin_register_with_registrar(file_selector_linux_registrar);
  g_autoptr(FlPluginRegistrar) flutter3d_pointer_lock_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "Flutter3dPointerLockPlugin");
  flutter3d_pointer_lock_plugin_register_with_registrar(flutter3d_pointer_lock_registrar);
  g_autoptr(FlPluginRegistrar) pad_input_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PadInputPlugin");
  pad_input_plugin_register_with_registrar(pad_input_registrar);
}
