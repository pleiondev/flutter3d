/// What runs on each page of the `post` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/post/adaptive_resolution.dart';
import 'package:flutter3d_showcase/pages/post/ambient_occlusion.dart';
import 'package:flutter3d_showcase/pages/post/anti_aliasing.dart';
import 'package:flutter3d_showcase/pages/post/auto_exposure.dart';
import 'package:flutter3d_showcase/pages/post/bloom.dart';
import 'package:flutter3d_showcase/pages/post/color_grading.dart';
import 'package:flutter3d_showcase/pages/post/depth_of_field.dart';
import 'package:flutter3d_showcase/pages/post/disabled_passes.dart';
import 'package:flutter3d_showcase/pages/post/light_shafts.dart';
import 'package:flutter3d_showcase/pages/post/lut_grading.dart';
import 'package:flutter3d_showcase/pages/post/msaa.dart';
import 'package:flutter3d_showcase/pages/post/render_post.dart';
import 'package:flutter3d_showcase/pages/post/screen_space_reflections.dart';
import 'package:flutter3d_showcase/pages/post/surface_buffer.dart';
import 'package:flutter3d_showcase/pages/post/tone_mapping.dart';
import 'package:flutter3d_showcase/pages/post/viewport_shading.dart';
import 'package:flutter3d_showcase/pages/post/xray.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> postDemos = <String, DemoBuilder>{
  'bloom': BloomDemo.new,
  'ambient-occlusion': AmbientOcclusionDemo.new,
  'adaptive-resolution': AdaptiveResolutionDemo.new,
  'anti-aliasing': AntiAliasingDemo.new,
  'auto-exposure': AutoExposureDemo.new,
  'tone-mapping': ToneMappingDemo.new,
  'surface-buffer': SurfaceBufferDemo.new,
  'color-grading': ColorGradingDemo.new,
  'lut-grading': LutGradingDemo.new,
  'light-shafts': LightShaftsDemo.new,
  'msaa': MsaaDemo.new,
  'render-post': RenderPostDemo.new,
  'screen-space-reflections': ScreenSpaceReflectionsDemo.new,
  'disabled-passes': DisabledPassesDemo.new,
  'depth-of-field': DepthOfFieldDemo.new,
  'viewport-shading': ViewportShadingDemo.new,
  'xray': XrayDemo.new,
};
