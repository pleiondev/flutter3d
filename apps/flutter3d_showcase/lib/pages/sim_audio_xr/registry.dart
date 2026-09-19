/// What runs on each page of the `sim_audio_xr` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/src/demo/demo.dart';

import 'actors.dart';
import 'audio_buses.dart';
import 'audio_occlusion.dart';
import 'audio_rolloff.dart';
import 'automap.dart';
import 'baked_visibility.dart';
import 'blended_engine_loop.dart';
import 'camera_shake.dart';
import 'difficulty.dart';
import 'ecs_world.dart';
import 'fixed_step.dart';
import 'flow_field.dart';
import 'head_tracking.dart';
import 'headless_run.dart';
import 'level_format.dart';
import 'level_mechanisms.dart';
import 'light_fixtures.dart';
import 'lightmap_bake.dart';
import 'nav_grid.dart';
import 'pendulum_lab.dart';
import 'portable_math.dart';
import 'positional_audio.dart';
import 'replay_digest.dart';
import 'rewind.dart';
import 'splines.dart';
import 'step_systems.dart';
import 'stereo_lesson.dart';
import 'stereo_rig.dart';
import 'terrain_tiles.dart';
import 'viewer_profiles.dart';
import 'voice_limit.dart';

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
  'positional-audio': PositionalAudioDemo.new,
  'audio-rolloff': AudioRolloffDemo.new,
  'audio-buses': AudioBusesDemo.new,
  'voice-limit': VoiceLimitDemo.new,
  'audio-occlusion': AudioOcclusionDemo.new,
  'blended-engine-loop': BlendedEngineLoopDemo.new,
  'pendulum-lab': PendulumLabDemo.new,
  'stereo-rig': StereoRigDemo.new,
  'viewer-profiles': ViewerProfilesDemo.new,
  'stereo-lesson': StereoLessonDemo.new,
  'head-tracking': HeadTrackingDemo.new,
};
