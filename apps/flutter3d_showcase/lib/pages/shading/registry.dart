/// What runs on each page of the `shading` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/shading/pbr_lighting.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> shadingDemos = <String, DemoBuilder>{
  'pbr-lighting': PbrLightingDemo.new,
};
