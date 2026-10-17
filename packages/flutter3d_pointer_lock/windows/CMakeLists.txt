# The Windows side of flutter3d_pointer_lock: Raw Input for the motion, ClipCursor and
# a hidden cursor for the lock.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flutter3d_pointer_lock")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "flutter3d_pointer_lock_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/flutter3d_pointer_lock/flutter3d_pointer_lock_plugin_c_api.h"
  "flutter3d_pointer_lock_plugin_c_api.cpp"
  "flutter3d_pointer_lock_plugin.cpp"
  "flutter3d_pointer_lock_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(flutter3d_pointer_lock_bundled_libraries "" PARENT_SCOPE)
