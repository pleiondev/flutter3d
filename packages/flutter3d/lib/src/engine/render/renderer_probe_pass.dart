/// Reflection probes: the scene captured into a cube from a point, and the
/// cube convolved into a roughness chain on the device.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
/// The capture draws every mesh through `_encodeNode`, which is the whole
/// argument for it living here: a probe's picture is the world's picture, with
/// the same materials, lights and shadows, seen from somewhere else.
///
/// Two cubes per probe and not one. The capture holds the six views at their
/// base level; the filtered cube holds the chain the lit shaders read, mirror
/// at the top and irradiance at the bottom. Filtering from one texture into
/// another level of *itself* is a read and a write of the same image in one
/// pass, which one backend forbids outright and another orders wrongly, so the
/// convolution reads the capture and writes the chain, six faces a level.
part of 'renderer.dart';

/// What the renderer holds for one probe between frames.
final class _ProbeState {
  _ProbeState({
    required this.capture,
    required this.filtered,
    required this.faceSize,
    required this.levels,
  });

  /// The six views, base level only. Sampled by the prefilter and nothing else.
  final TextureHandle capture;

  /// The chain the lit shaders sample: [levels] levels below the base.
  final TextureHandle filtered;

  final int faceSize;
  final int levels;

  /// Whether all six faces have been drawn at least once. A cube with faces
  /// nobody has drawn holds whatever the allocation held, and a probe that
  /// rolls one face a frame has to start from a whole one.
  bool whole = false;

  /// The face the rolling refresh draws next.
  int nextFace = 0;

  /// The probe generation the kept faces were drawn at, so `invalidate()`
  /// redraws them once and only once.
  int generation = -1;
}

/// One probe as a draw chooses between them: where it is, how far it reaches,
/// and what to bind.
final class _ProbeBinding {
  const _ProbeBinding({
    required this.position,
    required this.radius,
    required this.texture,
    required this.levels,
  });

  final vm.Vector3 position;
  final double radius;
  final TextureHandle texture;
  final int levels;
}

/// The probes a scene draw may reflect, as the frame answered for them.
///
/// The counterpart of [SceneShadows]: built by the node that declared the
/// reads, out of the frame's resources, and handed down to the mesh encoder so
/// which probe a draw gets is a decision made at the call site. A capture pass
/// hands [none] down — a probe drawn into another probe would sample a cube
/// that may not have been filled yet, and the first iteration does not chase
/// its own tail.
final class _SceneProbes {
  const _SceneProbes(this.bindings);

  static const _SceneProbes none = _SceneProbes(<_ProbeBinding>[]);

  final List<_ProbeBinding> bindings;

  /// The nearest probe whose radius reaches [at], or null.
  ///
  /// Nearest by the distance to the probe rather than by any blend: one probe
  /// per object, chosen where the object is, which is what the plan asked for
  /// first and what a car and a mirror ball both want.
  _ProbeBinding? nearest(vm.Vector3 at) {
    _ProbeBinding? best;
    var bestDistance = double.infinity;
    for (final probe in bindings) {
      final distance = probe.position.distanceToSquared(at);
      if (probe.radius > 0.0 && distance > probe.radius * probe.radius) {
        continue;
      }
      if (distance < bestDistance) {
        bestDistance = distance;
        best = probe;
      }
    }
    return best;
  }
}

extension _ProbePasses on Renderer {
  /// The state for [probe], allocated on first sight and reallocated when
  /// the probe's shape changed.
  ///
  /// Levels are clamped to what every backend allocates for [faceSize] — the
  /// chain flutter_gpu will hold stops one short of one-by-one, and a shader
  /// told the chain is longer than the texture reads past its last level.
  _ProbeState _probeStateFor(ReflectionProbeNode probe) {
    final levels = math.min(
      probe.levels,
      math.max(1, probe.faceSize.bitLength - 2),
    );
    final existing = _probeStates[probe];
    if (existing != null &&
        existing.faceSize == probe.faceSize &&
        existing.levels == levels) {
      return existing;
    }
    if (existing != null) {
      _destroyAfterFrame(existing.capture);
      _destroyAfterFrame(existing.filtered);
    }
    final capture = device.createCubeRenderTarget(
      size: probe.faceSize,
      format: hdrFormat,
    );
    final filtered = device.createCubeRenderTarget(
      size: probe.faceSize,
      format: hdrFormat,
      mipLevels: levels + 1,
    );
    if (capture == null || filtered == null) {
      throw StateError(
        'the device answered true to supportsCubeTextures and then made no '
        'cube for a reflection probe',
      );
    }
    final state = _ProbeState(
      capture: capture,
      filtered: filtered,
      faceSize: probe.faceSize,
      levels: levels,
    );
    _probeStates[probe] = state;
    return state;
  }

  /// Lets go of every probe that is no longer in [scene].
  ///
  /// A probe removed from a scene is two cubes nobody will sample again, and
  /// on the backend where dropping a handle frees nothing they would sit in
  /// the driver until the renderer went.
  void _retireProbesNotIn(Scene scene) {
    if (_probeStates.isEmpty) return;
    final live = scene.probes.toSet();
    _probeStates.removeWhere((probe, state) {
      if (live.contains(probe)) return false;
      _destroyAfterFrame(state.capture);
      _destroyAfterFrame(state.filtered);
      return true;
    });
  }

  /// Draws [scene] from [probe]'s position into [face] of its capture cube.
  ///
  /// Every mesh the world would draw, minus the probe's own exclusions, with
  /// the frame's lights and shadows and the sky behind them. Opaque first and
  /// blended last, the order the scene pass keeps, and no contributors: a
  /// particle system reflected in a car door is a thing to want later.
  void _captureProbeFace({
    required FrameResources resources,
    required Scene scene,
    required ReflectionProbeNode probe,
    required _ProbeState state,
    required int face,
    required RenderSettings settings,
    required SceneShadows shadows,
    required FramePassState passState,
    required vm.Vector4 clearColor,
  }) {
    final size = state.faceSize;
    final depth = resources.transient(
      RenderTargetSpec(
        width: size,
        height: size,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: state.capture,
            face: face,
            clearValue: Renderer._srgbToLinear(clearColor),
          ),
        ],
        depth: DepthTarget(texture: depth),
      ),
    );

    final rect = ScreenRect(width: size, height: size);
    pass.setState(
      Renderer._kSceneViewState.copyWith(
        viewport: rect,
        scissor: rect,
        polygonMode: PolygonMode.fill,
      ),
    );
    // A fresh pass has nothing bound, whatever the tracker remembers from the
    // pass before it; and the scene pass after this one trusts the tracker
    // too, so it is reset on both sides.
    passState
      ..depthCompare = CompareFunction.less
      ..invalidatePipeline();

    final position = probe.readWorldPosition(_probePosition);
    final origin = device.framebufferOrigin;
    final viewProjection = probeFaceViewProjection(
      face,
      position,
      near: probe.near,
      far: probe.far,
      origin: origin,
      depthRange: device.depthRange,
    );
    // Whether that view reverses the winding — a mirror on one origin, a half
    // turn on the other. See `probeFaceIsMirrored`.
    final mirrored = probeFaceIsMirrored(origin);
    _cameraData[0] = position.x;
    _cameraData[1] = position.y;
    _cameraData[2] = position.z;

    void encodeHalf({required bool blended}) {
      for (final node in scene.meshes) {
        if (!node.visibleInHierarchy || !node.shadowCasting.drawsColour) {
          continue;
        }
        if (node.material.isTransparent != blended) continue;
        if (probe.excluded.contains(node)) continue;
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
        _encodeNode(
          encoder: pass,
          node: node,
          scene: scene,
          settings: settings,
          viewProjection: viewProjection,
          shadows: shadows,
          lights: lights,
          shadowSlots: _shadowSlots,
          state: passState,
          mirrored: mirrored,
        );
      }
    }

    encodeHalf(blended: false);
    _encodeSky(
      pass: pass,
      settings: settings,
      viewProjection: viewProjection,
      state: passState,
    );
    encodeHalf(blended: true);

    pass.submit();
    passState.invalidatePipeline();
  }

  /// Convolves [state]'s capture into every level of its filtered cube.
  ///
  /// Six faces times the levels plus the base, each a full-screen pass into
  /// one face of one level: the base is a one-tap copy and every level below
  /// it a lobe that widens with the roughness `level / levels` — the ramp the
  /// lit shaders' `roughness * levels` assumes, and the one
  /// `EnvironmentMap.prefilter` builds on the host.
  void _prefilterProbe(_ProbeState state) {
    final shader = shaders['ProbePrefilter'];
    if (shader == null) {
      throw StateError(
        'the scene holds a ReflectionProbeNode but the bundle has no '
        '"ProbePrefilter" entry. Rebuild the backend\'s shader bundle — for '
        'the web backend that means re-running tool/generate_shaders.dart.',
      );
    }
    final pipeline = _probePrefilterPipeline ??= device.createPipeline(
      fullscreenVertexShader,
      shader,
    );

    for (var level = 0; level <= state.levels; level++) {
      final side = math.max(1, state.faceSize >> level);
      final rect = ScreenRect(width: side, height: side);
      _probeParams[1] = level / state.levels;
      _probeParams[2] = 0.0;
      _probeParams[3] = level == 0 ? 1.0 : _kProbeTaps.toDouble();
      for (var face = 0; face < 6; face++) {
        _probeParams[0] = face.toDouble();
        final pass = device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: state.filtered,
                face: face,
                mipLevel: level,
                loadAction: LoadAction.dontCare,
              ),
            ],
          ),
        );
        pass.setState(
          Renderer._kFullscreenState.copyWith(viewport: rect, scissor: rect),
        );
        pass.bindPipeline(pipeline);
        pass.bindVertexBuffer(_fullscreenTriangle, 3);
        pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
        pass.bindTexture(
          shader,
          'capture_texture',
          state.capture,
          sampler: Renderer._clampSampler,
        );
        pass.bindUniformBlock(shader, _kProbeInfoBlock, <String, Float32List>{
          'params': _probeParams,
        });
        pass.draw();
        pass.submit();
      }
    }
  }

  /// Taps per texel below the mirror level.
  ///
  /// Sixty-four is what the host-side prefilter takes, and the two agree on
  /// the number so a level built either way is the same lobe sampled the same
  /// way. At a face of sixty-four the whole chain is thirty small passes.
  static const int _kProbeTaps = 64;
}
