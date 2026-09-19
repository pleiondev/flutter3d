/// What runs on each page of the `view_input` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/view_input/free_look.dart';
import 'package:flutter3d_showcase/pages/view_input/gamepad.dart';
import 'package:flutter3d_showcase/pages/view_input/input_bindings.dart';
import 'package:flutter3d_showcase/pages/view_input/off_axis_projection.dart';
import 'package:flutter3d_showcase/pages/view_input/orbit_controller.dart';
import 'package:flutter3d_showcase/pages/view_input/pixel_picking.dart';
import 'package:flutter3d_showcase/pages/view_input/pointer_lock.dart';
import 'package:flutter3d_showcase/pages/view_input/projections.dart';
import 'package:flutter3d_showcase/pages/view_input/raycast.dart';
import 'package:flutter3d_showcase/pages/view_input/screen_bounds.dart';
import 'package:flutter3d_showcase/pages/view_input/tiled_render.dart';
import 'package:flutter3d_showcase/pages/view_input/touch_controls.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> viewInputDemos = <String, DemoBuilder>{
  'projections': ProjectionsDemo.new,
  'off-axis-projection': OffAxisProjectionDemo.new,
  'tiled-render': TiledRenderDemo.new,
  'orbit-controller': OrbitControllerDemo.new,
  'free-look': FreeLookDemo.new,
  'raycast': RaycastDemo.new,
  'pixel-picking': PixelPickingDemo.new,
  'screen-bounds': ScreenBoundsDemo.new,
  'gamepad': GamepadDemo.new,
  'pointer-lock': PointerLockDemo.new,
  'input-bindings': InputBindingsDemo.new,
  'touch-controls': TouchControlsDemo.new,
};
