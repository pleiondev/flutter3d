# The Windows side of pointer_lock: Raw Input for the motion, ClipCursor and
# a hidden cursor for the lock.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "pointer_lock")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "pointer_lock_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/pointer_lock/pointer_lock_plugin_c_api.h"
  "pointer_lock_plugin_c_api.cpp"
  "pointer_lock_plugin.cpp"
  "pointer_lock_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(pointer_lock_bundled_libraries "" PARENT_SCOPE)
