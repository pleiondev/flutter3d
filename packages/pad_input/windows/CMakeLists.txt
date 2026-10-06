# The Windows side of pad_input: XInput, polled, forwarded untouched — what
# the numbers mean is `lib/src/desktop_mapping.dart`'s.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "pad_input")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "pad_input_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/pad_input/pad_input_plugin_c_api.h"
  "pad_input_plugin_c_api.cpp"
  "pad_input_plugin.cpp"
  "pad_input_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# XInput 1.4, in the system since Windows 8: nothing to bundle.
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin xinput)

set(pad_input_bundled_libraries "" PARENT_SCOPE)
