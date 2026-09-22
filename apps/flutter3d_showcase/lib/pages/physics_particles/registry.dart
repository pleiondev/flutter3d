/// What runs on each page of the `physics_particles` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/physics_particles/burst_light.dart';
import 'package:flutter3d_showcase/pages/physics_particles/character_controller.dart';
import 'package:flutter3d_showcase/pages/physics_particles/collision_layers.dart';
import 'package:flutter3d_showcase/pages/physics_particles/collision_queries.dart';
import 'package:flutter3d_showcase/pages/physics_particles/collision_shapes.dart';
import 'package:flutter3d_showcase/pages/physics_particles/flipbook.dart';
import 'package:flutter3d_showcase/pages/physics_particles/heightfield_collision.dart';
import 'package:flutter3d_showcase/pages/physics_particles/mesh_particles.dart';
import 'package:flutter3d_showcase/pages/physics_particles/particle_curves.dart';
import 'package:flutter3d_showcase/pages/physics_particles/particle_emitters.dart';
import 'package:flutter3d_showcase/pages/physics_particles/particle_lights.dart';
import 'package:flutter3d_showcase/pages/physics_particles/particle_modifiers.dart';
import 'package:flutter3d_showcase/pages/physics_particles/particle_pool.dart';
import 'package:flutter3d_showcase/pages/physics_particles/rigid_bodies.dart';
import 'package:flutter3d_showcase/pages/physics_particles/textured_particles.dart';
import 'package:flutter3d_showcase/pages/physics_particles/xpbd_cloth.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> physicsParticlesDemos = <String, DemoBuilder>{
  'particle-pool': ParticlePoolDemo.new,
  'particle-emitters': ParticleEmittersDemo.new,
  'particle-modifiers': ParticleModifiersDemo.new,
  'particle-curves': ParticleCurvesDemo.new,
  'particle-lights': ParticleLightsDemo.new,
  'burst-light': BurstLightDemo.new,
  'textured-particles': TexturedParticlesDemo.new,
  'flipbook': FlipbookDemo.new,
  'mesh-particles': MeshParticlesDemo.new,
  'collision-shapes': CollisionShapesDemo.new,
  'collision-queries': CollisionQueriesDemo.new,
  'collision-layers': CollisionLayersDemo.new,
  'character-controller': CharacterControllerDemo.new,
  'rigid-bodies': RigidBodiesDemo.new,
  'heightfield-collision': HeightfieldCollisionDemo.new,
  'xpbd-cloth': XpbdClothDemo.new,
};
