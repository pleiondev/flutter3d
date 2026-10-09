//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <pad_input/pad_input_plugin_c_api.h>
#include <pointer_lock/pointer_lock_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  PadInputPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PadInputPluginCApi"));
  PointerLockPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PointerLockPluginCApi"));
}
