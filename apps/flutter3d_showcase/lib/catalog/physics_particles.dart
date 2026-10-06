/// The pages of the `physics_particles` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> physicsParticlesFeatures = <Feature>[
  Feature(
    id: 'particle-pool',
    title: 'A particle pool in one draw call',
    category: Category.physicsParticles,
    summary:
        'One pool of particles, drawn in one instanced call however many '
        'effects are bursting out of it.',
    since: '0.2.0',
    evidence:
        'A pool, emitters, modifiers and a contributor that draws every '
        'live particle in one instanced call, on any backend the engine has.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['particle pool'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/particle_system.dart',
    ],
  ),
  Feature(
    id: 'particle-emitters',
    title: 'Emitter shapes',
    category: Category.physicsParticles,
    summary:
        'Sphere, cone, box and drift: where a particle starts and which '
        'way it leaves.',
    since: '0.2.0',
    evidence:
        'emitters, modifiers and a contributor that draws every live '
        'particle in one instanced call, on any backend the engine has.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['emitter shapes'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/particle_emitter.dart',
    ],
  ),
  Feature(
    id: 'particle-modifiers',
    title: 'Forces',
    category: Category.physicsParticles,
    summary:
        'Gravity, drag, wind, turbulence and spin, stacked on the same '
        'burst.',
    since: '0.2.0',
    evidence:
        'modifiers and a contributor that draws every live particle in one '
        'instanced call, on any backend the engine has.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['modifier stack'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/particle_affector.dart',
      'packages/flutter3d_particles/lib/src/curve_affectors.dart',
    ],
  ),
  Feature(
    id: 'particle-curves',
    title: 'Over-life curves',
    category: Category.physicsParticles,
    summary:
        'Size and colour described as a handful of keys over a particle\'s '
        'life, instead of one number turning into another.',
    since: '0.5.0',
    evidence: 'An ease carries its curve.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['curve', 'gradient'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/particle_curve.dart',
      'packages/flutter3d_particles/lib/src/particle_gradient.dart',
      'packages/flutter3d_particles/lib/src/key_ease.dart',
    ],
  ),
  Feature(
    id: 'particle-lights',
    title: 'Particles that light',
    category: Category.physicsParticles,
    summary:
        'A torch measured from its own particles, so the light it casts '
        'cannot disagree with the flame that is supposed to be making it.',
    since: '0.2.0',
    evidence: 'A particle can be a light source and can carry a texture.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['light source'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/light_emitter.dart',
    ],
  ),
  Feature(
    id: 'burst-light',
    title: 'A burst that lights the room',
    category: Category.physicsParticles,
    summary:
        'ParticleSystem.burst takes a light source, so an explosion or a '
        'muzzle flash lights whatever is standing near it.',
    since: '0.7.0',
    evidence: 'A burst can light something.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['glow fed'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/particle_system.dart',
    ],
  ),
  Feature(
    id: 'six-way-smoke',
    title: 'Smoke lit by the scene',
    category: Category.physicsParticles,
    summary:
        'Puffs of smoke lit from each side by the lights around them, '
        'through six pictures of one puff.',
    since: '0.8.0',
    evidence: 'Lit particle sheets.',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['ContributorLights', 'SixWayMaterial'],
    packages: <String>['flutter3d_particles', 'flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/six_way.dart',
      'packages/flutter3d_particles/lib/src/particle_contributor.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_contributor_lights.dart',
    ],
  ),
  Feature(
    id: 'textured-particles',
    title: 'Textured billboards',
    category: Category.physicsParticles,
    summary:
        'A sprite on every billboard instead of the procedural disc, which '
        'is what turns a particle into any shape you can paint.',
    since: '0.2.0',
    evidence: 'A particle can be a light source and can carry a texture.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['carry a texture'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/particle_contributor.dart',
    ],
  ),
  Feature(
    id: 'flipbook',
    title: 'Sprite-sheet animation',
    category: Category.physicsParticles,
    summary:
        'A grid of frames played across a particle\'s life, driven by how '
        'far through it is rather than by a clock.',
    since: '0.2.0',
    approximate: true,
    evidence:
        'no explicit origin; the record never names Flipbook or '
        'FlipbookCell, and the earliest mention of a particle carrying a '
        'texture at all is this heading.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['texture'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>['packages/flutter3d_particles/lib/src/flipbook.dart'],
  ),
  Feature(
    id: 'mesh-particles',
    title: 'Mesh particles',
    category: Category.physicsParticles,
    summary:
        'Every live particle drawn as a copy of a real mesh instead of a '
        'camera-facing quad, in one instanced call.',
    since: '0.2.0',
    approximate: true,
    evidence:
        'no explicit origin; the record names "a contributor" for the '
        'billboard path but never MeshParticleContributor by name.',
    evidenceFile: 'packages/flutter3d_particles/CHANGELOG.md',
    keywords: <String>['contributor'],
    packages: <String>['flutter3d_particles'],
    engineFiles: <String>[
      'packages/flutter3d_particles/lib/src/mesh_particle_contributor.dart',
    ],
  ),
  Feature(
    id: 'collision-shapes',
    title: 'Collision shapes',
    category: Category.physicsParticles,
    summary:
        'Five shapes, box, sphere, capsule, wedge and heightfield, each with '
        'a closed-form overlap test against every other one.',
    since: '0.5.1',
    evidence:
        'A field of samples a body walks on: the fifth shape, and the first '
        'that is not one convex solid.',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    keywords: <String>['heightfield'],
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/collision_shape.dart',
    ],
  ),
  Feature(
    id: 'collision-queries',
    title: 'Raycast, sweep and overlap',
    category: Category.physicsParticles,
    summary:
        'A ray, a moving shape and a still one, all answered by the same '
        'broadphase grid.',
    since: '0.5.0',
    evidence: 'A function type is frozen the day it is published',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    keywords: <String>['ContactFilter'],
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/collision_world.dart',
      'packages/flutter3d_physics/lib/src/spatial_grid.dart',
    ],
  ),
  Feature(
    id: 'collision-layers',
    title: 'Layers and contact callbacks',
    category: Category.physicsParticles,
    summary:
        'Two colliders are tested against each other only when each is in '
        'the other\'s mask.',
    since: '0.2.0',
    approximate: true,
    evidence:
        'no explicit origin; the record names collision shapes and queries '
        'at this heading but never Layers, Collider or CollisionListener.',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    keywords: <String>['overlap queries'],
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>['packages/flutter3d_physics/lib/src/collider.dart'],
  ),
  Feature(
    id: 'character-controller',
    title: 'A character controller',
    category: Category.physicsParticles,
    summary:
        'A kinematic walker that slides along what it meets instead of '
        'bouncing off it, and reports the ground it lands on.',
    since: '0.5.0',
    evidence:
        'The probe that decides whether a body is standing on something '
        'reads a normal to do it and discarded it',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/character_controller.dart',
    ],
    changes: <Change>[
      Change(
        version: '0.9.0',
        note:
            'The walker\'s sliding, stepping and slope are worked out by the run\'s physics, the native core by default, while its speed, gravity and jump stay the controller\'s.',
        evidence: 'A world can say who moves its characters.',
        evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
      ),
    ],
  ),
  Feature(
    id: 'rigid-bodies',
    title: 'Rigid bodies',
    category: Category.physicsParticles,
    summary:
        'Mass, gravity, impulses and rest, with no rotation unless asked '
        'for: a box that never tips stays cheap to test against another box.',
    since: '0.2.0',
    evidence: 'Rigid bodies with mass, gravity, impulses, pushing and rest',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/rigid_body.dart',
      'packages/flutter3d_physics/lib/src/dynamics.dart',
    ],
    changes: <Change>[
      Change(
        version: '0.9.0',
        note:
            'The crates fall on the run\'s physics, the native core by default and the Dart reference where it will not start, and a body can now be built to turn.',
        evidence: '`PhysicsBackend`, one for the whole run.',
        evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
      ),
    ],
  ),
  Feature(
    id: 'physics-core',
    title: 'The physics core',
    category: Category.physicsParticles,
    summary:
        'The same crates dropped twice, one pile stepped in Dart and one by '
        'the physics core in C, ending in the same place.',
    since: '0.9.0',
    evidence:
        'The core is the default, and the Dart reference is the fallback.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['NativePhysics'],
    packages: <String>['flutter3d_physics', 'flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/physics_backend.dart',
      'packages/flutter3d_physics_native/lib/src/native_physics.dart',
      'packages/flutter3d_physics_native/lib/src/native_dynamics.dart',
    ],
  ),
  Feature(
    id: 'heightfield-collision',
    title: 'Walking on terrain',
    category: Category.physicsParticles,
    summary:
        'Ground as a grid of sampled heights, walked by the same character '
        'controller that walks a flat floor.',
    since: '0.5.1',
    evidence: 'which is what makes it walkable',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    keywords: <String>['partSeams'],
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/collision_heightfield.dart',
    ],
  ),
  Feature(
    id: 'xpbd-cloth',
    title: 'Cloth',
    category: Category.physicsParticles,
    summary:
        'A pinned grid of particles, solved with XPBD, draped around '
        'whatever collision shapes it is told not to pass through.',
    since: '0.7.0',
    evidence:
        'the structural and bending constraints are solved against it with '
        'multipliers reset each substep',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    keywords: <String>['xpbd'],
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/cloth/cloth_mesh.dart',
      'packages/flutter3d_physics/lib/src/cloth/xpbd_solver.dart',
    ],
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'Cloth meets a ball as a ball, stays calm when draped, feels wind as a force and holds on with friction.',
        evidence: 'Cloth meets a sphere and a capsule as themselves.',
        evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
      ),
      Change(
        version: '0.8.1',
        note:
            'A sheet resists shear, so a quad no longer folds flat into a rhombus, and one part of it no longer passes through another.',
        evidence: 'A sheet no longer passes through itself.',
        evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
      ),
      Change(
        version: '0.8.2',
        note:
            'The ball\'s facets no longer show through the sheet draped over it: the flat triangles between the particles stay clear of the surface too.',
        evidence: 'A ball no longer shows through the cloth draped over it.',
        evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
      ),
      Change(
        version: '0.9.0',
        note:
            'The sheet is stepped on the run\'s physics, the native core by default, which moves the same particle arrays the Dart reference does.',
        evidence: 'Cloth comes from the run\'s backend.',
        evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
      ),
    ],
  ),
  Feature(
    id: 'compound-shapes',
    title: 'Several shapes on one body',
    category: Category.physicsParticles,
    summary:
        'A table, a dumbbell and a hammer, each one body built from several shapes, landing and resting on their parts.',
    since: '0.9.0',
    evidence: 'Several shapes on one body.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['createCompound'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
      'packages/flutter3d_physics_native/csrc/src/f3d_compound.c',
    ],
  ),
  Feature(
    id: 'breakable-joints',
    title: 'Joints that break',
    category: Category.physicsParticles,
    summary:
        'A shelf on two brackets that let go when a crate lands past their limit, and say so with an event.',
    since: '0.9.0',
    evidence: 'Joints that break.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['setJointBreak'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
      'packages/flutter3d_physics_native/csrc/src/f3d_joint.c',
    ],
  ),
  Feature(
    id: 'vehicle',
    title: 'A car on four springs',
    category: Category.physicsParticles,
    summary:
        'A box chassis on four ray wheels driving a loop over a plank, steered and braked, gripping on tarmac and sliding on ice.',
    since: '0.9.0',
    evidence: 'Vehicles on wheels that hang from springs.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['createVehicle'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
      'packages/flutter3d_physics_native/csrc/src/f3d_vehicle.c',
    ],
  ),
  Feature(
    id: 'multibody-chain',
    title: 'A chain that does not stretch',
    category: Category.physicsParticles,
    summary:
        'The same heavy-ended chain twice: on ordinary hinges it stretches, as a multibody in reduced coordinates every joint stays shut.',
    since: '0.9.0',
    evidence: 'Chains whose joints cannot come apart.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['createMultibody'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
      'packages/flutter3d_physics_native/csrc/src/f3d_multibody.c',
    ],
  ),
  Feature(
    id: 'joints-and-motors',
    title: 'Joints and motors',
    category: Category.physicsParticles,
    summary:
        'A hinge with limits, a slider on a motor, a ball joint in a cone, and a distance joint as a rod, a spring and a rope.',
    since: '0.9.0',
    evidence:
        'Fixed, spherical, revolute (a hinge), prismatic (a slider) and distance joints',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['NativeJoint'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
    ],
  ),
  Feature(
    id: 'ragdoll',
    title: 'A ragdoll',
    category: Category.physicsParticles,
    summary:
        'Eleven capsules on ten joints, pushed down a flight of stairs until they come to rest.',
    since: '0.9.0',
    evidence:
        'A ragdoll of eleven bodies on ten joints falls to a floor and sleeps within two seconds.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['NativeRagdoll'],
    packages: <String>['flutter3d_physics', 'flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_ragdoll.dart',
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
    ],
  ),
  Feature(
    id: 'convex-shapes',
    title: 'Convex shapes and mesh floors',
    category: Category.physicsParticles,
    summary:
        'A cylinder rolling down a triangle-mesh ramp, a cone, a hull of six points and a rounded box coming to rest.',
    since: '0.9.0',
    evidence:
        'Cylinders, cones and convex hulls, and any shape rounded by a radius',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['NativeHull'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
    ],
  ),
  Feature(
    id: 'continuous-collision',
    title: 'Fast bodies and thin walls',
    category: Category.physicsParticles,
    summary:
        'Balls fired at a wall a centimetre thick: speculative contacts and a bullet stop them, and with neither one goes through.',
    since: '0.9.0',
    evidence: 'Continuous collision, phase 8.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['setBullet', 'speculative'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
      'packages/flutter3d_physics_native/csrc/src/f3d_ccd.c',
    ],
  ),
  Feature(
    id: 'heat-and-fire',
    title: 'Heat and fire',
    category: Category.physicsParticles,
    summary:
        'A wooden board catches beside a hot block, burns lighter and is put out with water; a steel one only warms.',
    since: '0.9.0',
    evidence: 'Wind, heat and fire are the world\'s.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['NativeMaterial', 'setWindGrid'],
    packages: <String>['flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_world.dart',
      'packages/flutter3d_physics_native/csrc/src/f3d_heat.c',
    ],
  ),
  Feature(
    id: 'liquids',
    title: 'Liquids on the core',
    category: Category.physicsParticles,
    summary:
        'A U-tube that levels out, a floating block and a pour between test tubes, stepped by the physics core.',
    since: '0.9.0',
    evidence: 'Pipes and floating bodies run on the core.',
    evidenceFile: 'packages/flutter3d_physics_native/CHANGELOG.md',
    keywords: <String>['NativeLiquid'],
    packages: <String>['flutter3d_physics', 'flutter3d_physics_native'],
    engineFiles: <String>[
      'packages/flutter3d_physics_native/lib/src/native_liquid.dart',
      'packages/flutter3d_physics/lib/src/fluid/fluid_world.dart',
      'packages/flutter3d_physics/lib/src/fluid/pipe.dart',
      'packages/flutter3d_physics/lib/src/fluid/buoyancy.dart',
    ],
  ),
];
