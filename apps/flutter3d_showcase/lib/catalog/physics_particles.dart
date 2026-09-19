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
  ),
  Feature(
    id: 'rigid-bodies',
    title: 'Rigid bodies',
    category: Category.physicsParticles,
    summary:
        'Mass, gravity, impulses and rest, with no rotation: a box that '
        'never tips stays cheap to test against another box.',
    since: '0.2.0',
    evidence: 'Rigid bodies with mass, gravity, impulses, pushing and rest',
    evidenceFile: 'packages/flutter3d_physics/CHANGELOG.md',
    packages: <String>['flutter3d_physics'],
    engineFiles: <String>[
      'packages/flutter3d_physics/lib/src/rigid_body.dart',
      'packages/flutter3d_physics/lib/src/dynamics.dart',
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
  ),
];
