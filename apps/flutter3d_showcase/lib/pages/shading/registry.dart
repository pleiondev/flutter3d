/// What runs on each page of the `shading` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/shading/alpha_modes.dart';
import 'package:flutter3d_showcase/pages/shading/area_lights.dart';
import 'package:flutter3d_showcase/pages/shading/draw_batching.dart';
import 'package:flutter3d_showcase/pages/shading/draw_state.dart';
import 'package:flutter3d_showcase/pages/shading/exposure.dart';
import 'package:flutter3d_showcase/pages/shading/light_channels.dart';
import 'package:flutter3d_showcase/pages/shading/lighting_models.dart';
import 'package:flutter3d_showcase/pages/shading/normal_mapping.dart';
import 'package:flutter3d_showcase/pages/shading/pbr_lighting.dart';
import 'package:flutter3d_showcase/pages/shading/photometric_units.dart';
import 'package:flutter3d_showcase/pages/shading/punctual_lights.dart';
import 'package:flutter3d_showcase/pages/shading/specular_scale.dart';
import 'package:flutter3d_showcase/pages/shading/texture_filtering.dart';
import 'package:flutter3d_showcase/pages/shading/wireframe.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> shadingDemos = <String, DemoBuilder>{
  'lighting-models': LightingModelsDemo.new,
  'pbr-lighting': PbrLightingDemo.new,
  'normal-mapping': NormalMappingDemo.new,
  'alpha-modes': AlphaModesDemo.new,
  'draw-state': DrawStateDemo.new,
  'texture-filtering': TextureFilteringDemo.new,
  'specular-scale': SpecularScaleDemo.new,
  'exposure': ExposureDemo.new,
  'wireframe': WireframeDemo.new,
  'draw-batching': DrawBatchingDemo.new,
  'punctual-lights': PunctualLightsDemo.new,
  'area-lights': AreaLightsDemo.new,
  'photometric-units': PhotometricUnitsDemo.new,
  'light-channels': LightChannelsDemo.new,
};
