#include "include/pointer_lock/pointer_lock_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "pointer_lock_plugin.h"

void PointerLockPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pointer_lock::PointerLockPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
