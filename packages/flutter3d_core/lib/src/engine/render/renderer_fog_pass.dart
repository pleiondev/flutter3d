/// Volumetric fog: a half-resolution march through the air and a depth-aware
/// pass that lays it over the scene — `S4`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why. The
/// shaders are `post/volumetric_fog.frag` and
/// `post/volumetric_fog_upsample.frag`, which say what each step is for.
part of 'renderer.dart';

extension _FogPass on Renderer {
  /// Marches the air in front of [scene] at half its size and returns the
  /// scene seen through it.
  ///
  /// [shadow] is the directional map when the sun casts one, and null
  /// otherwise: the march then treats every point as lit by [radiance], which
  /// is nought when there is no directional light at all. The cells are the
  /// ones the scene pass left in [_fogCells], read only when it left any.
  ///
  /// Reuses the shadow pass's matrices and splits, for the reason
  /// `_encodeLightShafts` does: a second derivation is a second thing to
  /// disagree with the map.
  TextureHandle _encodeVolumetricFog({
    required TextureHandle scene,
    required TextureHandle surface,
    required TextureHandle? shadow,
    required VolumetricFogSettings settings,
    required RenderView view,
    required FrameResources resources,
    required int width,
    required int height,
    required vm.Vector3? toLight,
    required vm.Vector3? radiance,
  }) {
    developer.Timeline.startSync('Renderer.volumetricFog');
    // Half the scene's size, rounded up so an odd edge keeps its last
    // column. The format is the scene's: the in-scatter is HDR light.
    final half = resources.transient(
      RenderTargetSpec(
        width: math.max(1, (scene.width + 1) ~/ 2),
        height: math.max(1, (scene.height + 1) ~/ 2),
        format: scene.format,
      ),
    );
    final target = resources.transient(
      RenderTargetSpec(
        width: scene.width,
        height: scene.height,
        format: scene.format,
      ),
    );

    final aspect = height == 0 ? 1.0 : width / height;
    // Origin-adjusted and not depth-range adjusted, as the shafts' is.
    final viewProjection = toFramebufferOrigin(
      view.camera.viewProjection(aspect),
      device.framebufferOrigin,
    );
    final inverse = vm.Matrix4.copy(viewProjection)..invert();
    final info = _volumeFogInfo;
    info.inverseViewProjection.setAll(0, inverse.storage);

    final eye = vm.Vector3.zero();
    view.camera.readWorldPosition(eye);
    info.camera
      ..[0] = eye.x
      ..[1] = eye.y
      ..[2] = eye.z
      ..[3] = math.max(settings.distance, 0.0);
    final forward = vm.Vector3.zero();
    view.camera.readForward(forward);
    info.forward
      ..[0] = forward.x
      ..[1] = forward.y
      ..[2] = forward.z
      ..[3] = settings.steps.clamp(0, 64).toDouble();

    final albedo = settings.color ?? vm.Vector3.all(1.0);
    final sun = toLight ?? vm.Vector3(0.0, 1.0, 0.0);
    final sunLight = toLight == null || radiance == null
        ? vm.Vector3.zero()
        : radiance;
    info.sun
      ..[0] = sun.x
      ..[1] = sun.y
      ..[2] = sun.z
      ..[3] = settings.anisotropy.clamp(-0.95, 0.95);
    info.sunRadiance
      ..[0] = sunLight.x * albedo.x
      ..[1] = sunLight.y * albedo.y
      ..[2] = sunLight.z * albedo.z
      ..[3] = 0.0;

    // The cascades only with a map to read; a count of nought makes every
    // point lit, which is the unshadowed sun a caster-less scene has.
    info.shadowMatrix.setAll(0, _shadowMatrix.storage);
    info.shadowMatrixFar.setAll(0, _shadowMatrixFar.storage);
    info.shadowMatrixFarthest.setAll(0, _shadowMatrixFarthest.storage);
    info.cascades
      ..[0] = _shadowCascades[0]
      ..[1] = _shadowCascades[1]
      ..[2] = shadow == null ? 0.0 : _shadowCascades[2]
      ..[3] = 0.0;
    info.bias.setAll(0, _shadowCascadeBias);

    info.medium
      ..[0] = math.max(settings.density, 0.0)
      ..[1] = settings.heightFalloff
      ..[2] = settings.baseHeight
      ..[3] = 0.0;
    // The flag the march reads the cells by: set only when the scene pass
    // left some, so a view without `L6` never samples the stand-in.
    final cells = _fogCells;
    info.albedo
      ..[0] = albedo.x
      ..[1] = albedo.y
      ..[2] = albedo.z
      ..[3] = cells == null ? 0.0 : 1.0;
    final ambient = settings.ambient ?? vm.Vector3.zero();
    info.ambient
      ..[0] = ambient.x * albedo.x
      ..[1] = ambient.y * albedo.y
      ..[2] = ambient.z * albedo.z
      ..[3] = 0.0;

    // `L6`'s cells as the scene pass cut them, and where in the texture it
    // wrote them. Left as they are when there are none: the albedo's flag keeps
    // the shader from reading them.
    info.clusterViewProjection.setAll(0, _lightClusters.viewProjection.storage);
    info.clusterGrid
      ..[0] = LightClusters.tilesX.toDouble()
      ..[1] = LightClusters.tilesY.toDouble()
      ..[2] = LightClusters.slices.toDouble()
      ..[3] = 0.0;
    info.clusterDepth
      ..[0] = _lightClusters.near
      ..[1] = _lightClusters.sliceScale
      ..[2] = _clusterHeaderRow.toDouble()
      ..[3] = _clusterEntryRow.toDouble();
    info.list
      ..[0] = 0.25
      ..[1] = cells == null ? 0.0 : 1.0 / math.max(_fogCellRows, 1)
      ..[2] = 0.0
      ..[3] = 0.0;

    drawFullscreen(
      FullscreenDraw(
        target: half,
        fragment: volumetricFogShader,
        textures: <String, TextureHandle>{
          'surface_texture': surface,
          'shadow_texture': shadow ?? fallbackBlack,
          'light_list_texture': cells ?? fallbackBlack,
          'blue_noise_texture': _blueNoise,
        },
        uniforms: <String, Map<String, Float32List>>{
          info.name: info.members,
          _noiseInfo.name: _noiseInfo.members,
        },
        // Nearest on everything that holds numbers rather than colour: a
        // filtered depth at a silhouette stops the march at a depth nothing
        // stands at, and a filtered light row is a light nobody placed.
        samplers: const <String, SamplerOptions>{
          'surface_texture': SamplerOptions.nearestClamp,
          'light_list_texture': SamplerOptions.nearestClamp,
        },
      ),
    );

    _fogUpsampleInfo.size
      ..[0] = half.width.toDouble()
      ..[1] = half.height.toDouble()
      ..[2] = 0.0
      ..[3] = 0.0;
    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: volumetricFogUpsampleShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'fog_texture': half,
          'surface_texture': surface,
        },
        uniforms: <String, Map<String, Float32List>>{
          _fogUpsampleInfo.name: _fogUpsampleInfo.members,
        },
        // The fog texels are weighed by hand, four of them at their centres,
        // so each is read as it is; a filtered read would blend across the
        // very edge the weights are there to respect.
        samplers: const <String, SamplerOptions>{
          'fog_texture': SamplerOptions.nearestClamp,
          'surface_texture': SamplerOptions.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
    return target;
  }
}
