/// What runs on each page of the `widgets_misc` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/widgets_misc/hot_swap.dart';
import 'package:flutter3d_showcase/pages/widgets_misc/parties.dart';
import 'package:flutter3d_showcase/pages/widgets_misc/render_inspection.dart';
import 'package:flutter3d_showcase/pages/widgets_misc/saves.dart';
import 'package:flutter3d_showcase/pages/widgets_misc/scene_widgets.dart';
import 'package:flutter3d_showcase/pages/widgets_misc/time_travel.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

import 'accommodations.dart';
import 'diagnostics.dart';
import 'game_settings.dart';
import 'level_loader.dart';
import 'rollback_netcode.dart';
import 'run_timeline.dart';
import 'scene_semantics.dart';
import 'scene_surface.dart';
import 'storage.dart';
import 'widget_surface.dart';

final Map<String, DemoBuilder> widgetsMiscDemos = <String, DemoBuilder>{
  'widget-surface': WidgetSurfaceDemo.new,
  'scene-semantics': SceneSemanticsDemo.new,
  'scene-surface': SceneSurfaceDemo.new,
  'level-loader': LevelLoaderDemo.new,
  'storage': StorageDemo.new,
  'diagnostics': DiagnosticsDemo.new,
  'accommodations': AccommodationsDemo.new,
  'game-settings': GameSettingsDemo.new,
  'run-timeline': RunTimelineDemo.new,
  'rollback-netcode': RollbackNetcodeDemo.new,
  'time-travel': TimeTravelDemo.new,
  'saves': SavesDemo.new,
  'parties': PartiesDemo.new,
  'scene-widgets': SceneWidgetsDemo.new,
  'render-inspection': RenderInspectionDemo.new,
  'hot-swap': HotSwapDemo.new,
};
