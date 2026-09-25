/// The irradiance field kept current on the GPU — `L4`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why these
/// are extensions on `Renderer` rather than files of their own.
///
/// **A few probes a frame, round robin.** Each scheduled probe draws the
/// scene into a small cube from where it stands — the lit colour and, as the
/// second attachment, the surface buffer, whose alpha is the depth along the
/// face — and `IrradianceConvolve` folds that into the probe's two tiles of
/// the atlas, blended with what they held by the field's hysteresis. The
/// atlas lives in a `FieldPass`, seeded from what the host baked and then
/// only ever stepped: `lib/irradiance.glsl` reads whichever texture it
/// currently holds.
///
/// **The capture is lit by the field itself**, since the lit stages read it:
/// each update carries one more bounce, which is how a room fills with light
/// over its first seconds. The hysteresis keeps that from flickering.
///
/// **Off unless the field asks** (`IrradianceField.gpuUpdates`), and only on
/// a device with cube textures and a second colour attachment; elsewhere the
/// field stays what was baked.
part of 'renderer.dart';

/// Faces of a probe's capture, in texels a side.
const int _kIrradianceCaptureSize = 16;

/// What the renderer keeps for one field being updated on the GPU.
final class _IrradianceGpu {
  _IrradianceGpu({
    required this.field,
    required this.atlas,
    required this.radiance,
    required this.surface,
    required this.columns,
    required this.momentsTop,
  });

  final IrradianceField field;

  /// The atlas, stepped: [FieldPass.current] is what the lit stages read.
  final FieldPass atlas;
  final TextureHandle radiance;
  final TextureHandle surface;
  final int columns;
  final int momentsTop;

  /// The field version the atlas was last seeded from.
  int seeded = -1;

  /// The next probe the schedule reaches.
  int cursor = 0;

  /// Probe updates done, for tests.
  int updates = 0;
}

extension _IrradiancePass on Renderer {
  /// The convolution kernel, resolved on first use like the probe stages: a
  /// bundle that predates it should fail to update a field, not to start.
  ShaderHandle get _irradianceConvolveShader =>
      shaders['IrradianceConvolve'] ??
      (throw StateError(
        'the scene asks for irradiance updates on the GPU but the bundle has '
        'no "IrradianceConvolve" entry',
      ));

  /// Whether [field] is updated on this device at all.
  bool _updatesIrradianceOnGpu(IrradianceField field) =>
      field.gpuUpdates > 0 &&
      device.supportsCubeTextures &&
      device.maxColorAttachments > 1;

  /// [field]'s GPU state, made the first time it is asked for.
  _IrradianceGpu _irradianceGpuFor(IrradianceField field) {
    final existing = _irradianceGpu;
    if (existing != null && identical(existing.field, field)) return existing;
    _releaseIrradianceGpu();
    final packed = field.toAtlas();
    TextureHandle cube() =>
        device.createCubeRenderTarget(
          size: _kIrradianceCaptureSize,
          format: hdrFormat,
        ) ??
        (throw StateError(
          'the device answered true to supportsCubeTextures and then made no '
          'cube for an irradiance probe',
        ));
    return _irradianceGpu = _IrradianceGpu(
      field: field,
      atlas: FieldPass(
        device,
        RenderTargetSpec(
          width: packed.width,
          height: packed.height,
          format: hdrFormat,
          storageMode: StorageMode.devicePrivate,
        ),
      ),
      radiance: cube(),
      surface: cube(),
      columns: packed.columns,
      momentsTop: packed.momentsTop,
    );
  }

  void _releaseIrradianceGpu() {
    final gpu = _irradianceGpu;
    if (gpu == null) return;
    _destroyAfterFrame(gpu.atlas.current);
    _destroyAfterFrame(gpu.radiance);
    _destroyAfterFrame(gpu.surface);
    _irradianceGpu = null;
  }

  /// Seeds the atlas when the host changed the field, then updates the
  /// scheduled probes.
  void _updateIrradiance({
    required IrradianceField field,
    required FrameResources resources,
    required Scene scene,
    required RenderSettings settings,
    required SceneShadows shadows,
    required FramePassState passState,
    required vm.Vector4 clearColor,
  }) {
    final gpu = _irradianceGpuFor(field);
    final shader = _irradianceConvolveShader;
    final info = _convolveInfo;
    info.tiles
      ..[0] = field.tile.toDouble()
      ..[1] = field.depthTile.toDouble()
      ..[2] = gpu.momentsTop.toDouble()
      ..[3] = kIrradianceReach;
    info.atlas
      ..[0] = gpu.atlas.spec.width.toDouble()
      ..[1] = gpu.atlas.spec.height.toDouble()
      ..[2] = _kIrradianceCaptureSize.toDouble();
    info.probe[3] = gpu.columns.toDouble();

    if (gpu.seeded != field.version) {
      final seed = _irradianceAtlasFor(field) ?? fallbackAlbedo;
      info.probe
        ..[0] = -1.0
        ..[1] = 1.0;
      gpu.atlas.step(
        shader,
        label: _passLabel ?? 'irradiance update',
        bind: (pass) => _bindConvolve(pass, shader, seed),
      );
      gpu.seeded = field.version;
    }

    final probes = field.probeCount;
    var done = 0;
    for (var tried = 0; tried < probes && done < field.gpuUpdates; tried++) {
      final probe = gpu.cursor;
      if (field.active[probe] == 0) {
        gpu.cursor = (gpu.cursor + 1) % probes;
        continue;
      }
      // `N3`: within the frame's allowance for work that can wait; a probe
      // refused here is the first one next frame.
      final ran = _workBudget.spend(() {
        gpu.cursor = (gpu.cursor + 1) % probes;
        final x = probe % field.countX;
        final y = (probe ~/ field.countX) % field.countY;
        final z = probe ~/ (field.countX * field.countY);
        final position = field.probePosition(x, y, z);
        for (var face = 0; face < 6; face++) {
          _captureCubeFace(
            resources: resources,
            scene: scene,
            position: position,
            near: 0.05,
            far: kIrradianceReach,
            excluded: const <SceneNode>{},
            colour: gpu.radiance,
            surface: gpu.surface,
            size: _kIrradianceCaptureSize,
            face: face,
            settings: settings,
            shadows: shadows,
            passState: passState,
            clearColor: clearColor,
          );
        }
        info.probe
          ..[0] = probe.toDouble()
          ..[1] = 0.0
          ..[2] = field.hysteresis.clamp(0.0, 0.99);
        gpu.atlas.step(
          shader,
          label: _passLabel ?? 'irradiance update',
          bind: (pass) => _bindConvolve(pass, shader, fallbackAlbedo),
        );
        gpu.updates++;
      });
      if (!ran) break;
      done++;
    }
  }

  void _bindConvolve(
    PassEncoder pass,
    ShaderHandle shader,
    TextureHandle seed,
  ) {
    final gpu = _irradianceGpu!;
    pass
      ..bindBlock(shader, _convolveInfo)
      ..bindTexture(
        shader,
        'seed_texture',
        seed,
        sampler: SamplerOptions.nearestClamp,
      )
      ..bindTexture(
        shader,
        'radiance_texture',
        gpu.radiance,
        sampler: Renderer._clampSampler,
      )
      ..bindTexture(
        shader,
        'surface_texture',
        gpu.surface,
        sampler: SamplerOptions.nearestClamp,
      );
  }
}
