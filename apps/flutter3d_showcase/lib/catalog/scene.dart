/// The pages of the `scene` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> sceneFeatures = <Feature>[
  Feature(
    id: 'scene-graph',
    title: 'The scene graph',
    category: Category.scene,
    summary: 'Arrange an orbiting planet and moon with inherited transforms.',
    since: '0.1.0',
    evidence:
        'A scene graph whose transforms are held by version counters rather '
        'than dirty flags',
    keywords: <String>['scene graph', 'version counters'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/scene.dart',
      'packages/flutter3d_core/lib/src/engine/scene/scene_node.dart',
    ],
  ),
  Feature(
    id: 'tangents',
    title: 'Generate tangent frames',
    category: Category.scene,
    summary:
        'Derive render-ready tangents and handedness from positions, normals, and UVs.',
    since: '0.7.0',
    evidence: 'They are `package:flutter3d_core/geometry.dart`',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['withGeneratedTangents'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/mesh_tangents.dart',
      'packages/flutter3d_core/lib/src/geometry/vertex_layout.dart',
    ],
  ),
  Feature(
    id: 'vertex-cache',
    title: 'Vertex cache ordering',
    category: Category.scene,
    summary: 'Reorder triangles and vertices so the GPU can reuse recent work.',
    since: '0.7.0',
    evidence: 'vertex cache reordering and `EXT_meshopt_compression`',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['vertex cache reordering'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/vertex_cache_optimizer.dart',
    ],
  ),
  Feature(
    id: 'culling',
    title: 'BVH and frustum culling',
    category: Category.scene,
    summary:
        'Skip hundreds of meshes whose world-space boxes miss the current view.',
    since: '0.7.0',
    evidence:
        'The render list culls by the mesh\'s world box where it used the '
        'sphere around it',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['world box', 'SceneBvh'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/bvh.dart',
      'packages/flutter3d_core/lib/src/engine/render/render_list.dart',
    ],
  ),
  Feature(
    id: 'debug-draw',
    title: 'Debug drawing',
    category: Category.scene,
    summary:
        'Inspect bounds, normals, axes, lights, and a skeleton over the scene.',
    since: '0.7.0',
    evidence: '`DebugDrawOptions.skeletons` draws every skinned mesh\'s joints',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['DebugDrawOptions.skeletons'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/debug_draw.dart',
      'packages/flutter3d_core/lib/src/engine/render/debug_draw_gizmos.dart',
    ],
  ),
  Feature(
    id: 'instancing',
    title: 'Many copies in one draw',
    category: Category.scene,
    summary:
        'Draw a field of coloured meshes from one instanced vertex buffer.',
    since: '0.2.0',
    evidence: 'Instancing and CPU-built mip chains',
    keywords: <String>['Instancing'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/instanced_mesh_node.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer_scene_pass.dart',
    ],
  ),
  Feature(
    id: 'level-of-detail',
    title: 'Levels of detail',
    category: Category.scene,
    summary:
        'Choose a finer or coarser mesh from how much of the view it covers.',
    since: '0.7.0',
    evidence: 'A model\'s levels of detail pick themselves',
    keywords: <String>['levels of detail', 'LodGroup'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/lod_group.dart',
      'packages/flutter3d/lib/src/engine/assets/model_instance.dart',
    ],
  ),
  Feature(
    id: 'mesh-overlay',
    title: 'Mesh editing overlays',
    category: Category.scene,
    summary:
        'Draw edges, vertex handles, a face wash, and a through-mesh gizmo.',
    since: '0.7.0',
    evidence:
        '`MeshOverlay` draws edges, vertex handles and a face wash in three batches',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['MeshOverlay'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/mesh_overlay.dart',
    ],
  ),
  Feature(
    id: 'mesh-builder',
    title: 'Build a mesh in code',
    category: Category.scene,
    summary:
        'Write a coloured pyramid as vertices and indexed triangles in Dart.',
    since: '0.7.0',
    evidence: 'They are `package:flutter3d_core/geometry.dart`',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['MeshBuilder'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/mesh_builder.dart',
      'packages/flutter3d_core/lib/src/geometry/mesh_data.dart',
      'packages/flutter3d_core/lib/src/geometry/vertex_layout.dart',
    ],
  ),
  Feature(
    id: 'polylines',
    title: 'Polylines in screen pixels',
    category: Category.scene,
    summary: 'Draw joined routes whose width stays steady as the camera moves.',
    since: '0.7.0',
    evidence: '`buildPolyline` writes each point twice with its neighbours',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['buildPolyline', 'Material.polyline', 'PolylineShape'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/polyline_shape.dart',
      'packages/flutter3d_core/lib/src/engine/render/material.dart',
    ],
  ),
  Feature(
    id: 'gaussian-splats',
    title: 'Gaussian splats',
    category: Category.scene,
    summary:
        'Decode a binary PLY cloud and draw its translucent ellipses back to front.',
    since: '0.7.0',
    evidence: 'A captured cloud of Gaussians loads, sorts and draws',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['parseSplatPly', 'SplatCloud', 'SplatContributor'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/splat/splat_ply.dart',
      'packages/flutter3d_core/lib/src/formats/splat/splat_cloud.dart',
      'packages/flutter3d_core/lib/src/engine/render/splat_contributor.dart',
    ],
  ),
  Feature(
    id: 'procedural-shapes',
    title: 'Procedural shapes',
    category: Category.scene,
    summary:
        'Build a cuboid, sphere, torus, capsule, and disc directly in Dart.',
    since: '0.1.0',
    evidence:
        'surfaces of revolution generate the sphere, cylinder, cone, torus, '
        'capsule and disc',
    keywords: <String>['surfaces of revolution', 'sphere', 'torus', 'capsule'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/box_shapes.dart',
      'packages/flutter3d_core/lib/src/geometry/revolved_shapes.dart',
    ],
  ),
  Feature(
    id: 'lathe-shape',
    title: 'Surfaces of revolution',
    category: Category.scene,
    summary: 'Sweep a two-dimensional profile around an axis to make a vessel.',
    since: '0.1.0',
    evidence:
        'surfaces of revolution generate the sphere, cylinder, cone, torus, '
        'capsule and disc',
    keywords: <String>['surfaces of revolution'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/geometry/lathe_shape.dart',
    ],
  ),
  Feature(
    id: 'procedural-textures',
    title: 'Procedural textures',
    category: Category.scene,
    summary: 'Generate a solid colour and checkerboard as RGBA pixels in code.',
    since: '0.5.0',
    evidence: 'Eleven shapes and two procedural textures become `final`',
    keywords: <String>['procedural textures'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/procedural_texture.dart',
    ],
  ),
  Feature(
    id: 'frame-stats',
    title: 'What a frame reports',
    category: Category.scene,
    summary:
        'Read draw, triangle, instance, culling, and per-pass counts after a frame.',
    since: '0.7.0',
    evidence:
        '`FrameResult.passes` is one `FramePass` per node the compiled graph '
        'ran',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['FrameResult.passes', 'FramePass'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/frame_result.dart',
    ],
  ),
  Feature(
    id: 'frame-graph',
    title: 'Plan a frame before drawing',
    category: Category.scene,
    summary:
        'Compile the render graph without drawing and compare it with the frame.',
    since: '0.7.0',
    evidence:
        '`Renderer.planFrame` compiles the graph for a frame without drawing it',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['Renderer.planFrame'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/frame_graph.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer.dart',
    ],
  ),
  Feature(
    id: 'view-model',
    title: 'The held item\'s own pass',
    category: Category.scene,
    summary: 'Draw a held item over the finished world, with its own depth.',
    since: '0.4.0',
    evidence:
        'a view-model studio\'s two lights were never uploaded, every held '
        'weapon drew near-black',
    keywords: <String>['view-model', 'held weapon'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/view_model_node.dart',
    ],
  ),
  Feature(
    id: 'multi-view',
    title: 'Several views in one frame',
    category: Category.scene,
    summary:
        'Crop a view to a rectangle and combine two of them in one render call.',
    since: '0.7.0',
    evidence: 'RenderSettings.forStereo()',
    keywords: <String>['forStereo'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/render_view.dart',
    ],
  ),
  Feature(
    id: 'frame-capture',
    title: 'Capturing a frame',
    category: Category.scene,
    summary: 'Record every pass of one frame, with the pixels each pass wrote.',
    since: '0.7.0',
    evidence:
        '`Renderer.captureNextFrame()` is a one-shot that answers a '
        '`FrameCapture`',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    keywords: <String>['captureNextFrame'],
    packages: <String>['flutter3d_core'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/frame_capture.dart',
      'packages/flutter3d_core/lib/src/engine/render/renderer.dart',
    ],
  ),
];
