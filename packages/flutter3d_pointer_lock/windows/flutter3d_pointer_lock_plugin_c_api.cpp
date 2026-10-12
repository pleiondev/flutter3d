#include "include/flutter3d_pointer_lock/flutter3d_pointer_lock_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter3d_pointer_lock_plugin.h"

void Flutter3dPointerLockPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter3d_pointer_lock::Flutter3dPointerLockPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
