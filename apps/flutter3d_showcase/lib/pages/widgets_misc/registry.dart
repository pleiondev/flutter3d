/// What runs on each page of the `widgets_misc` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/src/demo/demo.dart';

import 'level_loader.dart';
import 'scene_semantics.dart';
import 'scene_surface.dart';
import 'widget_surface.dart';

final Map<String, DemoBuilder> widgetsMiscDemos = <String, DemoBuilder>{
  'widget-surface': WidgetSurfaceDemo.new,
  'scene-semantics': SceneSemanticsDemo.new,
  'scene-surface': SceneSurfaceDemo.new,
  'level-loader': LevelLoaderDemo.new,
};
