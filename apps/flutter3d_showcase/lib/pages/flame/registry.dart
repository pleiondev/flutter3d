/// What runs on each page of the `flame` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/src/demo/demo.dart';

import 'flame_camera_bridge.dart';
import 'flame_ecs_bridge.dart';
import 'flame_input_bridge.dart';
import 'flame_overview.dart';
import 'flame_physics_bridge.dart';
import 'flame_transform_bridge.dart';

final Map<String, DemoBuilder> flameDemos = <String, DemoBuilder>{
  'flame-overview': FlameOverviewDemo.new,
  'flame-transform-bridge': FlameTransformBridgeDemo.new,
  'flame-ecs-bridge': FlameEcsBridgeDemo.new,
  'flame-physics-bridge': FlamePhysicsBridgeDemo.new,
  'flame-input-bridge': FlameInputBridgeDemo.new,
  'flame-camera-bridge': FlameCameraBridgeDemo.new,
};
