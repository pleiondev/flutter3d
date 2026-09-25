/// The temporal resolve: this frame's jittered scene blended into a history
/// at the output's size — `R2`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why these
/// are extensions on `Renderer` rather than files of their own. The shader is
/// `post/temporal_resolve.frag`, which says what each step is for.
part of 'renderer.dart';

/// One noisy effect's history — `R3`: two textures of the effect's size, one
/// read and one written, swapped each frame.
final class _EffectHistory {
  final List<TextureHandle?> textures = <TextureHandle?>[null, null];
  int read = 0;

  /// Whether [textures] holds a frame worth blending.
  bool valid = false;
}

extension _TemporalPass on Renderer {
  /// Blends [current] into the history kept for [resource] and returns the
  /// blend, which is the effect's answer from here on — `R3`.
  ///
  /// Nine tenths history: an effect drawn with half its samples and a new
  /// offset each frame has, after a dozen frames, the samples of several
  /// frames' worth of full passes. The clamp to this frame's neighbourhood
  /// is what stops that from lagging behind anything that moves.
  TextureHandle _encodeAccumulate({
    required ResourceId resource,
    required TextureHandle current,
    required TextureHandle velocity,
    required RenderView view,
  }) {
    developer.Timeline.startSync('Renderer.accumulate');
    final history = _effectHistories.putIfAbsent(resource, _EffectHistory.new);
    final existing = history.textures[0];
    if (existing == null ||
        existing.width != current.width ||
        existing.height != current.height) {
      for (var i = 0; i < 2; i++) {
        _destroyAfterFrame(history.textures[i]);
        history.textures[i] = device.createTexture(
          RenderTargetSpec(
            width: current.width,
            height: current.height,
            format: current.format,
            storageMode: StorageMode.devicePrivate,
          ),
        );
      }
      history.valid = false;
    }
    final previous = history.textures[history.read]!;
    final next = history.textures[1 - history.read]!;

    _accumulateInfo.params
      ..[0] = 0.9
      ..[1] = history.valid && !view.cut ? 1.0 : 0.0
      ..[2] = 1.0 / current.width
      ..[3] = 1.0 / current.height;
    drawFullscreen(
      FullscreenDraw(
        target: next,
        fragment: temporalAccumulateShader,
        textures: <String, TextureHandle>{
          'current_texture': current,
          'history_texture': previous,
          'velocity_texture': velocity,
        },
        uniforms: <String, Map<String, Float32List>>{
          _accumulateInfo.name: _accumulateInfo.members,
        },
        samplers: const <String, SamplerOptions>{
          'velocity_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    history
      ..read = 1 - history.read
      ..valid = true;
    developer.Timeline.finishSync();
    return next;
  }

  /// Makes the two histories [width] × [height], or keeps them if they are.
  void _ensureHistory(int width, int height) {
    final current = _history[0];
    if (current != null && current.width == width && current.height == height) {
      return;
    }
    for (var i = 0; i < 2; i++) {
      _destroyAfterFrame(_history[i]);
      _history[i] = device.createTexture(
        RenderTargetSpec(
          width: width,
          height: height,
          format: hdrFormat,
          storageMode: StorageMode.devicePrivate,
        ),
      );
    }
    _historyValid = false;
  }

  /// Resolves [scene] into the next history and returns it; it is this
  /// frame's lit colour from here on.
  TextureHandle _encodeTemporalResolve({
    required TextureHandle scene,
    required TextureHandle velocity,
    required TextureHandle surface,
    required RenderView view,
    required RenderSettings settings,
    required int outputWidth,
    required int outputHeight,
  }) {
    developer.Timeline.startSync('Renderer.temporalResolve');
    _ensureHistory(outputWidth, outputHeight);
    final previous = _history[_historyRead]!;
    final next = _history[1 - _historyRead]!;
    final temporal = settings.antiAlias.temporal;

    // The jitter the scene pass drew with this frame, as an offset in the
    // UV the textures are read by: the same NDC shift `JitteredProjection`
    // applied, carried through the framebuffer origin the way every
    // reconstruction here carries a matrix.
    final (jx, jy) = jitterOffset(_frameIndex, temporal.sequenceLength);
    final flip = toFramebufferOrigin(
      vm.Matrix4.identity(),
      device.framebufferOrigin,
    );
    final shifted = flip.transform(
      vm.Vector4(2.0 * jx / scene.width, 2.0 * jy / scene.height, 0.0, 1.0),
    );
    final origin = flip.transform(vm.Vector4(0.0, 0.0, 0.0, 1.0));

    _temporalInfo.sceneTexel
      ..[0] = 1.0 / scene.width
      ..[1] = 1.0 / scene.height
      ..[2] = scene.width.toDouble()
      ..[3] = scene.height.toDouble();
    _temporalInfo.jitter
      ..[0] = (shifted.x - origin.x) * 0.5
      ..[1] = -(shifted.y - origin.y) * 0.5
      ..[2] = temporal.historyWeight.clamp(0.0, 0.98)
      ..[3] = _historyValid && !view.cut ? 1.0 : 0.0;
    _temporalInfo.params
      ..[0] = _exposureFor(settings)
      // A tenth: two surfaces a tenth apart in depth are two surfaces, and a
      // camera walking forward changes one surface's depth by far less than
      // that in a frame.
      ..[1] = 0.1
      ..[2] = outputWidth.toDouble()
      ..[3] = outputHeight.toDouble();
    // The k-DOP's axes — `N4`; with none, the shader clips to its box.
    final clip = temporal.clip;
    _temporalInfo.clip[0] = clip.axisCount.toDouble();
    for (final (i, (x, y, z)) in clip.axes.indexed) {
      _temporalInfo.clipAxes
        ..[i * 4] = x
        ..[i * 4 + 1] = y
        ..[i * 4 + 2] = z;
    }

    drawFullscreen(
      FullscreenDraw(
        target: next,
        fragment: temporalResolveShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'history_texture': previous,
          'velocity_texture': velocity,
          'surface_texture': surface,
        },
        uniforms: <String, Map<String, Float32List>>{
          _temporalInfo.name: _temporalInfo.members,
        },
        // Filtered for the colour, which is read between texels on purpose;
        // not for the two buffers, where a filtered read across a silhouette
        // is a depth and a motion that belong to nothing.
        samplers: const <String, SamplerOptions>{
          'velocity_texture': SamplerOptions.nearestClamp,
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    _historyRead = 1 - _historyRead;
    _historyValid = true;
    developer.Timeline.finishSync();
    return next;
  }
}
