//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <file_selector_windows/file_selector_windows.h>
#include <flutter3d_pointer_lock/flutter3d_pointer_lock_plugin_c_api.h>
#include <pad_input/pad_input_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  Flutter3dPointerLockPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("Flutter3dPointerLockPluginCApi"));
  PadInputPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PadInputPluginCApi"));
}
