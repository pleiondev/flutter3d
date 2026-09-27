/// What runs on each page of the `shading` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/shading/alpha_modes.dart';
import 'package:flutter3d_showcase/pages/shading/ambient_light.dart';
import 'package:flutter3d_showcase/pages/shading/anisotropic_highlights.dart';
import 'package:flutter3d_showcase/pages/shading/area_lights.dart';
import 'package:flutter3d_showcase/pages/shading/clear_coat.dart';
import 'package:flutter3d_showcase/pages/shading/draw_batching.dart';
import 'package:flutter3d_showcase/pages/shading/draw_state.dart';
import 'package:flutter3d_showcase/pages/shading/exposure.dart';
import 'package:flutter3d_showcase/pages/shading/fmat_files.dart';
import 'package:flutter3d_showcase/pages/shading/light_channels.dart';
import 'package:flutter3d_showcase/pages/shading/lighting_models.dart';
import 'package:flutter3d_showcase/pages/shading/many_lights.dart';
import 'package:flutter3d_showcase/pages/shading/material_language.dart';
import 'package:flutter3d_showcase/pages/shading/normal_mapping.dart';
import 'package:flutter3d_showcase/pages/shading/order_independent_transparency.dart';
import 'package:flutter3d_showcase/pages/shading/pbr_lighting.dart';
import 'package:flutter3d_showcase/pages/shading/photometric_units.dart';
import 'package:flutter3d_showcase/pages/shading/punctual_lights.dart';
import 'package:flutter3d_showcase/pages/shading/rough_surfaces.dart';
import 'package:flutter3d_showcase/pages/shading/sheen.dart';
import 'package:flutter3d_showcase/pages/shading/specular_scale.dart';
import 'package:flutter3d_showcase/pages/shading/texture_filtering.dart';
import 'package:flutter3d_showcase/pages/shading/texture_transforms.dart';
import 'package:flutter3d_showcase/pages/shading/transmission.dart';
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
  'many-lights': ManyLightsDemo.new,
  'ambient-light': AmbientLightDemo.new,
  'fmat-files': FmatFilesDemo.new,
  'material-language': MaterialLanguageDemo.new,
  'clear-coat': ClearCoatDemo.new,
  'sheen': SheenDemo.new,
  'anisotropic-highlights': AnisotropicHighlightsDemo.new,
  'transmission': TransmissionDemo.new,
  'order-independent-transparency': OrderIndependentTransparencyDemo.new,
  'texture-transforms': TextureTransformsDemo.new,
  'rough-surfaces': RoughSurfacesDemo.new,
};
