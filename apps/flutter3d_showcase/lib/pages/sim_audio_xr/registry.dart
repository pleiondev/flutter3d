/// What runs on each page of the `sim_audio_xr` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/src/demo/demo.dart';

import 'actors.dart';
import 'automap.dart';
import 'baked_visibility.dart';
import 'camera_shake.dart';
import 'difficulty.dart';
import 'ecs_world.dart';
import 'fixed_step.dart';
import 'flow_field.dart';
import 'headless_run.dart';
import 'level_format.dart';
import 'level_mechanisms.dart';
import 'light_fixtures.dart';
import 'lightmap_bake.dart';
import 'nav_grid.dart';
import 'portable_math.dart';
import 'replay_digest.dart';
import 'rewind.dart';
import 'splines.dart';
import 'step_systems.dart';
import 'terrain_tiles.dart';

final Map<String, DemoBuilder> simAudioXrDemos = <String, DemoBuilder>{
  'fixed-step': FixedStepDemo.new,
  'ecs-world': EcsWorldDemo.new,
  'step-systems': StepSystemsDemo.new,
  'replay-digest': ReplayDigestDemo.new,
  'portable-math': PortableMathDemo.new,
  'rewind': RewindDemo.new,
  'headless-run': HeadlessRunDemo.new,
  'nav-grid': NavGridDemo.new,
  'flow-field': FlowFieldDemo.new,
  'automap': AutomapDemo.new,
  'lightmap-bake': LightmapBakeDemo.new,
  'baked-visibility': BakedVisibilityDemo.new,
  'terrain-tiles': TerrainTilesDemo.new,
  'splines': SplinesDemo.new,
  'level-format': LevelFormatDemo.new,
  'level-mechanisms': LevelMechanismsDemo.new,
  'light-fixtures': LightFixturesDemo.new,
  'actors': ActorsDemo.new,
  'camera-shake': CameraShakeDemo.new,
  'difficulty': DifficultyDemo.new,
};
