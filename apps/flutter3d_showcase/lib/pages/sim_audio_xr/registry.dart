/// What runs on each page of the `sim_audio_xr` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/src/demo/demo.dart';

import 'ecs_world.dart';
import 'fixed_step.dart';
import 'headless_run.dart';
import 'portable_math.dart';
import 'replay_digest.dart';
import 'rewind.dart';
import 'step_systems.dart';

final Map<String, DemoBuilder> simAudioXrDemos = <String, DemoBuilder>{
  'fixed-step': FixedStepDemo.new,
  'ecs-world': EcsWorldDemo.new,
  'step-systems': StepSystemsDemo.new,
  'replay-digest': ReplayDigestDemo.new,
  'portable-math': PortableMathDemo.new,
  'rewind': RewindDemo.new,
  'headless-run': HeadlessRunDemo.new,
};
