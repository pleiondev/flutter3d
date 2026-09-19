/// What runs on each page of the `environment` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/environment/distance_fog.dart';
import 'package:flutter3d_showcase/pages/environment/image_based_lighting.dart';
import 'package:flutter3d_showcase/pages/environment/irradiance_field.dart';
import 'package:flutter3d_showcase/pages/environment/lightmaps.dart';
import 'package:flutter3d_showcase/pages/environment/procedural_sky.dart';
import 'package:flutter3d_showcase/pages/environment/reflection_probes.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> environmentDemos = <String, DemoBuilder>{
  'procedural-sky': ProceduralSkyDemo.new,
  'distance-fog': DistanceFogDemo.new,
  'image-based-lighting': ImageBasedLightingDemo.new,
  'reflection-probes': ReflectionProbesDemo.new,
  'irradiance-field': IrradianceFieldDemo.new,
  'lightmaps': LightmapsDemo.new,
};
