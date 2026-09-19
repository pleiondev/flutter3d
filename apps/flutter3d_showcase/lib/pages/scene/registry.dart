/// What runs on each page of the `scene` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/scene/culling.dart';
import 'package:flutter3d_showcase/pages/scene/debug_draw.dart';
import 'package:flutter3d_showcase/pages/scene/frame_capture.dart';
import 'package:flutter3d_showcase/pages/scene/frame_graph.dart';
import 'package:flutter3d_showcase/pages/scene/frame_stats.dart';
import 'package:flutter3d_showcase/pages/scene/gaussian_splats.dart';
import 'package:flutter3d_showcase/pages/scene/instancing.dart';
import 'package:flutter3d_showcase/pages/scene/lathe_shape.dart';
import 'package:flutter3d_showcase/pages/scene/level_of_detail.dart';
import 'package:flutter3d_showcase/pages/scene/mesh_builder.dart';
import 'package:flutter3d_showcase/pages/scene/mesh_overlay.dart';
import 'package:flutter3d_showcase/pages/scene/multi_view.dart';
import 'package:flutter3d_showcase/pages/scene/polylines.dart';
import 'package:flutter3d_showcase/pages/scene/procedural_shapes.dart';
import 'package:flutter3d_showcase/pages/scene/procedural_textures.dart';
import 'package:flutter3d_showcase/pages/scene/scene_graph.dart';
import 'package:flutter3d_showcase/pages/scene/tangents.dart';
import 'package:flutter3d_showcase/pages/scene/vertex_cache.dart';
import 'package:flutter3d_showcase/pages/scene/view_model.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> sceneDemos = <String, DemoBuilder>{
  'culling': CullingDemo.new,
  'debug-draw': DebugDrawDemo.new,
  'frame-capture': FrameCaptureDemo.new,
  'frame-graph': FrameGraphDemo.new,
  'frame-stats': FrameStatsDemo.new,
  'gaussian-splats': GaussianSplatsDemo.new,
  'instancing': InstancingDemo.new,
  'lathe-shape': LatheShapeDemo.new,
  'level-of-detail': LevelOfDetailDemo.new,
  'mesh-overlay': MeshOverlayDemo.new,
  'mesh-builder': MeshBuilderDemo.new,
  'multi-view': MultiViewDemo.new,
  'polylines': PolylinesDemo.new,
  'procedural-shapes': ProceduralShapesDemo.new,
  'procedural-textures': ProceduralTexturesDemo.new,
  'scene-graph': SceneGraphDemo.new,
  'tangents': TangentsDemo.new,
  'vertex-cache': VertexCacheDemo.new,
  'view-model': ViewModelDemo.new,
};
