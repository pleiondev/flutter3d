/// The account behind `Renderer.memoryReport` — `A5.24`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **Walked, not tracked.** Nothing counts allocations as they happen: the
/// device is an interface four backends and an application's own may
/// implement, and a counter on it would be a member every one of them
/// owes. So the report asks what the renderer holds now — its targets, its
/// pool, its caches — and what the scene it is given draws: the meshes on
/// its nodes and the textures on their materials. A texture is counted
/// once, under the first category that finds it.
part of 'renderer.dart';

extension _MemoryAccount on Renderer {
  MemoryReport _buildMemoryReport(Scene? scene) {
    final seen = Set<Object>.identity();
    final entries = <MemoryEntry>[];

    void texture(MemoryCategory category, String label, TextureHandle? t) {
      if (t == null || !seen.add(t)) return;
      entries.add(
        MemoryEntry(
          category: category,
          label: label,
          count: 1,
          bytes: t.estimatedBytes,
        ),
      );
    }

    // Textures: what the scene's materials sample, the environment, and the
    // engine's own stand-ins.
    final meshes = <DrawableGeometry, String>{};
    if (scene != null) {
      texture(MemoryCategory.textures, 'environment', scene.environment);
      scene.root.traverse((SceneNode node) {
        if (node is! MeshNode) return;
        final material = node.material;
        final owner = material.name ?? node.name ?? 'unnamed material';
        for (final (map, handle) in <(String, TextureHandle?)>[
          ('albedo', material.albedo),
          ('normal', material.normal),
          ('metallicRoughness', material.metallicRoughness),
          ('occlusion', material.occlusion),
          ('emissive', material.emissiveTexture),
          ('lightmap', material.lightmap),
          ('coat', material.coatMap),
          ('sheen', material.sheenMap),
          for (final MapEntry(:key, :value) in material.extraTextures.entries)
            (key, value),
        ]) {
          texture(MemoryCategory.textures, '$owner.$map', handle);
        }
        if (node.mesh case final DrawableGeometry geometry) {
          meshes.putIfAbsent(geometry, () => node.name ?? 'unnamed mesh');
        }
      });
    }
    texture(MemoryCategory.textures, 'fallback albedo', _fallbackAlbedo);
    texture(MemoryCategory.textures, 'fallback normal', _fallbackNormal);
    texture(MemoryCategory.textures, 'fallback black', _fallbackBlack);
    texture(
      MemoryCategory.textures,
      'fallback environment',
      _fallbackEnvironment,
    );

    // Buffers: the CPU copies a mesh keeps beside its upload, for picking and
    // physics — the one buffer the renderer can see that is not a mesh's own
    // on the device.
    for (final MapEntry(key: geometry, value: label) in meshes.entries) {
      if (geometry case DeviceMesh(source: final MeshData source)) {
        entries.add(
          MemoryEntry(
            category: MemoryCategory.buffers,
            label: '$label (kept on the CPU)',
            count: 1,
            bytes:
                source.vertexBytes.lengthInBytes + source.indices.lengthInBytes,
          ),
        );
      }
    }

    // Render targets: the renderer's own, then the pool's.
    const target = MemoryCategory.renderTargets;
    for (final (label, handle) in <(String, TextureHandle?)>[
      ('hdrColor', _hdrColor),
      ('hdrMsaa', _hdrMsaa),
      ('reflectionColor', _reflectionColor),
      ('surfaceColor', _surfaceColor),
      ('albedoColor', _albedoColor),
      ('surfaceMsaa', _surfaceMsaa),
      ('depthStencil', _depthStencil),
      ('depthStencilSingle', _depthStencilSingle),
      ('wboitAccumulation', _wboitAccumulation),
      ('wboitRevealage', _wboitRevealage),
      ('wboitDepth', _wboitDepth),
      ('shadow atlas', _shadowMap),
      ('shadow atlas, static', _shadowMapStatic),
      ('shadow atlas, static spare', _shadowMapStaticSpare),
      ('shadow depth', _shadowDepth),
      ('shadow moments', _shadowMoments),
      ('shadow moments scratch', _shadowMomentsScratch),
      ('point shadow cube', _cubeShadow),
      ('point shadow cube, static', _cubeShadowStatic),
      ('point shadow depth', _cubeShadowDepth),
      ('irradiance atlas', _irradianceAtlas),
      ('light list', _lightListTexture),
      ('fog cells', _fogCells),
      for (final (i, frame) in _ldrFrames.indexed) ('ldr frame $i', frame),
      for (final (i, history) in _history.indexed) ('history $i', history),
      for (final MapEntry(:key, :value) in _effectHistories.entries)
        for (final (i, history) in value.textures.indexed)
          ('${key.name} history $i', history),
      for (final MapEntry(:key, :value) in _probeStates.entries) ...[
        ('probe ${key.name ?? 'unnamed'} capture', value.capture),
        ('probe ${key.name ?? 'unnamed'} filtered', value.filtered),
      ],
      for (final MapEntry(:key, :value) in _planarStates.entries)
        for (final (i, picture) in value.textures.indexed)
          ('reflector ${key.name ?? 'unnamed'} $i', picture),
    ]) {
      texture(target, label, handle);
    }
    entries
      ..add(
        MemoryEntry(
          category: target,
          label: 'transient pool, lent',
          count: targetPool.lentCount,
          bytes: targetPool.lentBytes,
        ),
      )
      ..add(
        MemoryEntry(
          category: target,
          label: 'transient pool, free',
          count: targetPool.pooledCount,
          bytes: targetPool.pooledBytes,
        ),
      );

    // Meshes: each upload once, however many nodes draw it.
    for (final MapEntry(key: geometry, value: label) in meshes.entries) {
      entries.add(
        MemoryEntry(
          category: MemoryCategory.meshes,
          label: label,
          count: 1,
          bytes:
              geometry.vertices.lengthInBytes + geometry.indices.lengthInBytes,
        ),
      );
    }

    // Shaders and pipelines: counted.
    entries.addAll(<MemoryEntry>[
      MemoryEntry(
        category: MemoryCategory.shaders,
        label: 'fragment stages',
        count: _fragmentShaders.length,
      ),
      MemoryEntry(
        category: MemoryCategory.shaders,
        label: 'material vertex stages',
        count: _materialVertexShaders.length,
      ),
      MemoryEntry(
        category: MemoryCategory.shaders,
        label: 'pipelines',
        count:
            _pipelineCache.length +
            _predrawPipelines.length +
            _fullscreenPipelines.length +
            (_debugLinePipeline == null ? 0 : 1),
      ),
    ]);
    return MemoryReport(entries);
  }
}
