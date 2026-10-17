#include "include/pad_input/pad_input_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "pad_input_plugin.h"

void PadInputPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pad_input::PadInputPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
