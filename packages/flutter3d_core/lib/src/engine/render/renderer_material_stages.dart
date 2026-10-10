/// What a stage written in the material language's version 2 asks of the
/// renderer — item 9 of `tasks/1.0-scope-additions.md`: its vertex stage in
/// the depth and shadow passes, the scene behind a translucent surface, the
/// depth layer, the blend modes and the effects depth.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
part of 'renderer.dart';

/// `MaterialVertexInfo`: the view-projection alone, for a `vertex` block
/// that says where in the world a vertex is rather than where in its mesh —
/// `emitMaterialVertex`. Hand-written rather than generated, because no
/// stage of the engine's declares it; only the language's do.
final class _MaterialVertexInfoBlock extends UniformBlock {
  _MaterialVertexInfoBlock() : super('MaterialVertexInfo');

  /// `view_projection`: the matrix the pass draws through.
  final Float32List viewProjection = Float32List(16);

  @override
  late final Map<String, Float32List> members = <String, Float32List>{
    'view_projection': viewProjection,
  };
}

/// `SceneDepthInfo`: where a fragment finds itself in the surface buffer a
/// translucent material reads the scene behind it from — `particle_soft`'s
/// `target`, under the material language's name.
final class _SceneDepthInfoBlock extends UniformBlock {
  _SceneDepthInfoBlock() : super('SceneDepthInfo');

  /// xy: one over the buffer's size. z: its rows when row zero is the
  /// bottom, nought when it is the top. w unused.
  final Float32List target = Float32List(4);

  @override
  late final Map<String, Float32List> members = <String, Float32List>{
    'target': target,
  };
}

/// How far one depth layer pulls a surface towards the eye: four of the
/// depth format's smallest steps, and one of its slope. Small enough that a
/// layer never reaches through a surface a centimetre in front of it at a
/// few metres, large enough that two coplanar faces never trade a pixel.
const int _kDepthLayerConstant = 4;
const double _kDepthLayerSlope = 1.0;

extension _MaterialStages on Renderer {
  /// Whether [material]'s depth and shadow are drawn through its own vertex
  /// stage — `LightingModel.vertexStageInDepthPasses`, a `vertex` block.
  bool _movesInDepthPasses(RenderMaterial material) =>
      material.lighting.vertexShaderName != null &&
      material.lighting.vertexStageInDepthPasses;

  /// [material]'s vertex stage for a depth or shadow draw, or null for the
  /// engine's. Never for an instanced draw, which keeps the engine's
  /// instanced stage as the scene pass keeps it.
  ShaderHandle? _depthPassVertexStage(
    RenderMaterial material, {
    required bool skinned,
  }) => _movesInDepthPasses(material)
      ? _vertexShaderFor(
          material.lighting,
          skinned: skinned,
          lightmapped: false,
        )
      : null;

  /// Binds the pipeline of [node]'s material's vertex stage and [fragment] —
  /// a depth pre-draw or a shadow pass drawing a caster whose material moves
  /// its geometry — and returns the stage, or null, binding nothing, for a
  /// caster drawn through the engine's stage: every other one, and every
  /// instanced one.
  ShaderHandle? _bindDepthPassStage(
    PassEncoder pass,
    MeshNode node,
    ShaderHandle fragment,
  ) {
    if (node is InstancedMeshNode) return null;
    final own = _depthPassVertexStage(
      node.material,
      skinned: node.skeleton != null,
    );
    if (own == null) return null;
    pass.bindPipeline(
      _pipelineCache.putIfAbsent(
        'depth/${own.name}+${fragment.name}',
        () => device.createPipeline(own, fragment),
      ),
    );
    return own;
  }

  /// Binds what a material's own vertex stage reads besides `FrameInfo`:
  /// `MaterialVertexInfo` — [viewProjection], the matrix the pass draws
  /// through — and the material's parameters. Every pass that draws through
  /// such a stage calls this, the scene, the pre-draw and the shadows alike,
  /// so a stage moves its geometry the same in all of them.
  ///
  /// The block is reported absent rather than bound to a stage that does
  /// not declare it — one whose block writes `position` rather than
  /// `world`, or one written by hand — which costs nothing.
  void _bindMaterialVertex(
    PassEncoder pass,
    ShaderHandle stage,
    RenderMaterial material,
    vm.Matrix4 viewProjection, {
    bool parameters = true,
  }) {
    if (material.lighting.vertexShaderName == null) return;
    if (material.lighting.vertexStageInDepthPasses) {
      _materialVertexInfo.viewProjection.setAll(0, viewProjection.storage);
      pass.bindBlock(stage, _materialVertexInfo);
    }
    if (parameters && material.parameters.isNotEmpty) {
      pass.bindUniformBlock(
        stage,
        material.parameterBlock,
        material.parameters,
      );
    }
  }

  /// Binds the scene behind a translucent surface to [fragmentShader] — the
  /// surface buffer, while [_sceneDepthRead] lends it, and a black texel
  /// everywhere else, which reads as nothing behind. Only for a stage that
  /// declares them: binding a sampler a stage has not got is a native
  /// crash on Metal, and so is leaving one it has unbound.
  void _bindSceneDepth(PassEncoder pass, ShaderHandle fragmentShader) {
    final surface = _sceneDepthRead;
    final width = surface?.width ?? 1;
    final height = surface?.height ?? 1;
    _sceneDepthInfo.target
      ..[0] = 1.0 / width
      ..[1] = 1.0 / height
      ..[2] = device.framebufferOrigin == FramebufferOrigin.bottomLeft
          ? height.toDouble()
          : 0.0
      ..[3] = 0.0;
    pass
      ..bindBlock(fragmentShader, _sceneDepthInfo)
      ..bindTexture(
        fragmentShader,
        'scene_depth_texture',
        surface ?? fallbackBlack,
        sampler: SamplerDescriptor.nearestClamp,
      );
  }

  /// The bias that puts [layer] above the layers under it — see
  /// `RenderMaterial.depthLayer`. In the engine's own depth, nearer is smaller;
  /// the reversed-depth encoder turns it round with every other bias.
  DepthBias _depthLayerBias(int layer) {
    final clamped = layer.clamp(
      -materialDepthLayerLimit,
      materialDepthLayerLimit,
    );
    return DepthBias(
      constant: -_kDepthLayerConstant * clamped,
      slopeScale: -_kDepthLayerSlope * clamped,
    );
  }

  /// [indices] with the layered surfaces after the rest, lowest layer
  /// first and in their own order within a layer — the half of
  /// `RenderMaterial.depthLayer` that holds where the device has no depth bias.
  /// The list itself when nothing in it is layered, which is every scene
  /// written before there were layers: nothing allocates, and nothing moves.
  List<int> _layeredLast(List<int> indices) {
    var layered = false;
    for (final index in indices) {
      if (_renderList.itemAt(index).requireNode.material.depthLayer != 0) {
        layered = true;
        break;
      }
    }
    if (!layered) return indices;
    int layerOf(int index) =>
        _renderList.itemAt(index).requireNode.material.depthLayer;
    final layers = <int>{for (final index in indices) layerOf(index)}.toList()
      ..sort();
    // Layer nought keeps its place at the front, below everything above it
    // and above everything below it — a negative layer sinks under the
    // surfaces it lies on as a positive one rises over them.
    return <int>[
      for (final layer in layers)
        for (final index in indices)
          if (layerOf(index) == layer) index,
    ];
  }

  /// The blend a translucent [material] draws with — `RenderMaterial.blendMode`.
  static BlendState _blendFor(RenderMaterial material) =>
      material.blendMode == MaterialBlendMode.additive
      ? BlendState.additive
      : BlendState.alphaBlend;

  /// Whether this frame has a surface reading the scene behind it for any
  /// of [views] — the question that splits the frame for it, as a
  /// contributor reading the scene's depth splits it.
  static bool _holdsSceneReaders(Scene scene, List<RenderView> views) {
    final mask = views.fold<int>(0, (all, view) => all | view.layerMask);
    return scene.meshes.any(
      (node) =>
          node.material.lighting.usesSceneDepth &&
          node.isVisibleInHierarchy &&
          node.shadowCasting.drawsColor &&
          (node.layerMask & mask) != 0,
    );
  }
}
