/// Pictures of the scene taken before the scene: a [RenderTexture]'s camera
/// and a planar reflector's mirrored one — `P4`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
/// Both draw every mesh through `_encodeNode`, as a probe's capture does, so
/// a picture of the world has the world's materials, lights and shadows.
///
/// **One way of drawing a view into a texture, and two things pointed
/// through it.** [_captureView] is the probe face's pass with a 2D target, a
/// frustum to cull by and a layer mask: the opaque half, the sky, the
/// blended half. A render texture points it through its own camera and then
/// encodes the light into sRGB bytes for a material to read; a reflector
/// points it through the view's camera mirrored in its plane, with the near
/// plane moved onto the plane, and keeps the light as it is for its
/// surfaces to lay over themselves in the scene pass.
part of 'renderer.dart';

/// What the renderer holds for one planar reflector between frames: a
/// picture per view, kept so a frame does not allocate one.
final class _PlanarState {
  /// Indexed by the view's place in the frame's priority order.
  final List<TextureHandle?> textures = <TextureHandle?>[];

  /// Which of [textures] this frame drew. A view seeing the plane from
  /// behind draws nothing, and the picture kept from an earlier frame must
  /// not be laid on.
  final List<bool> drawn = <bool>[];

  /// The frame [drawn] describes, so a frame whose pass was culled lays
  /// nothing on either.
  int frame = -1;
}

extension _PlanarPasses on Renderer {
  /// Lets go of the pictures of every reflector no longer in [scene].
  void _retireReflectorsNotIn(Scene scene) {
    if (_planarStates.isEmpty) return;
    final live = scene.reflectors.toSet();
    _planarStates.removeWhere((reflector, state) {
      if (live.contains(reflector)) return false;
      state.textures.forEach(_destroyAfterFrame);
      return true;
    });
  }

  /// Draws [scene] into [color] through [viewProjection], as a camera at
  /// [eye] sees it.
  ///
  /// [skyViewProjection] is the same view without anything done to its depth,
  /// which is what the sky's rays are taken from: a reflector's near plane
  /// tilts the depth and leaves every ray where it was, and the rays are all
  /// the sky reads. [mirrored] says the matrix reverses the winding.
  void _captureView({
    required FrameResources resources,
    required Scene scene,
    required TextureHandle color,
    required vm.Matrix4 viewProjection,
    required vm.Matrix4 skyViewProjection,
    required vm.Vector3 eye,
    required int layerMask,
    required Set<SceneNode> excluded,
    required bool mirrored,
    required RenderSettings settings,
    required SceneShadows shadows,
    required FramePassState passState,
    required vm.Vector4 clearColor,
  }) {
    final rect = ScreenRect.of(color);
    final depth = resources.transient(
      RenderTargetDescriptor(
        width: rect.width,
        height: rect.height,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(
            texture: color,
            clearValue: Renderer._srgbToLinear(clearColor),
          ),
        ],
        depth: DepthTarget(texture: depth),
      ),
    );
    // Every lane the scene pass sets, set here too: the capture runs before
    // it, and a lane left as the last frame's scene pass wrote it is a
    // picture that depends on what was drawn a frame ago.
    _targetOrigin[0] = _rowsFromBottom(color);
    _targetOrigin[1] = 0.0;
    _targetOrigin[2] = settings.energyCompensation ? 1.0 : 0.0;
    _targetOrigin[3] = -1.0;
    // A reflection shows the light, whatever the frame's debug view: the
    // mirror is part of the picture being debugged, not a material in it.
    _suppressDebugViews();
    pass.setState(
      Renderer._kSceneViewState.copyWith(
        viewport: rect,
        scissor: rect,
        polygonMode: PolygonMode.fill,
      ),
    );
    passState
      ..depthCompare = CompareFunction.less
      ..invalidatePipeline();

    _cameraData[0] = eye.x;
    _cameraData[1] = eye.y;
    _cameraData[2] = eye.z;
    viewAxisOf(skyViewProjection, _forward);
    _forwardData[0] = _forward.x;
    _forwardData[1] = _forward.y;
    _forwardData[2] = _forward.z;
    // A mirror of an orthographic view is orthographic too.
    _fogInfo.projection[0] = isOrthographic(skyViewProjection) ? 1.0 : 0.0;

    final frustum = _DepthConvention._viewFrustum(viewProjection);
    void encodeHalf({required bool blended}) {
      for (final node in scene.meshes) {
        if (!node.isVisibleInHierarchy || !node.shadowCasting.drawsColor) {
          continue;
        }
        if (node.drawsTransparent != blended) continue;
        if ((node.layerMask & layerMask) == 0) continue;
        if (excluded.contains(node)) continue;
        if (node.frustumCulled &&
            !frustum.intersectsWithAabb3(node.worldBounds)) {
          continue;
        }
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
        _encodeNode(
          encoder: pass,
          node: node,
          scene: scene,
          settings: settings,
          viewProjection: viewProjection,
          shadows: shadows,
          lights: _frameLights,
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
      viewProjection: skyViewProjection,
      state: passState,
    );
    encodeHalf(blended: true);

    pass.submit();
    passState.invalidatePipeline();
  }

  /// Draws [texture]'s camera into it: the light into a picture of the
  /// frame's own, and that picture encoded into the texture's bytes.
  void _drawRenderTexture({
    required FrameResources resources,
    required Scene scene,
    required RenderView texture,
    required RenderSettings settings,
    required SceneShadows shadows,
    required FramePassState passState,
  }) {
    final light = resources.transient(
      RenderTargetDescriptor(
        width: texture.width,
        height: texture.height,
        format: hdrFormat,
      ),
    );
    final camera = texture.camera;
    final eye = camera.readViewOrigin();
    final viewProjection = _viewProjection(
      camera,
      texture.width / texture.height,
    );
    _captureView(
      resources: resources,
      scene: scene,
      color: light,
      viewProjection: viewProjection,
      skyViewProjection: viewProjection,
      eye: eye,
      layerMask: texture.layerMask,
      excluded: texture.excluded,
      mirrored: false,
      settings: settings,
      shadows: shadows,
      passState: passState,
      clearColor: texture.clearColorSrgb,
    );
    final encode = shaders['RenderTextureEncode'];
    if (encode == null) {
      throw StateError(
        'the scene holds a texture view but the bundle has no '
        '"RenderTextureEncode" entry. Rebuild the backend\'s shader bundle — '
        'for the web backends that means re-running tool/generate_shaders.dart.',
      );
    }
    _renderTextureInfo.params
      ..[0] = texture.options.exposure
      ..[1] = device.framebufferOrigin == FramebufferOrigin.bottomLeft
          ? 1.0
          : 0.0;
    drawFullscreen(
      FullscreenDraw(
        target: texture.texture!,
        fragment: encode,
        textures: <String, TextureHandle>{'source_texture': light},
        uniforms: <String, Map<String, Float32List>>{
          _renderTextureInfo.name: _renderTextureInfo.members,
        },
      ),
    );
    texture.markDrawn();
  }

  /// Draws [reflector]'s mirrored picture for every view in [views] that
  /// sees the front of its plane, into [state]'s textures.
  ///
  /// The view's own camera and projection, reflected in the plane: a world
  /// point is mirrored first and then seen as the view sees it, so the
  /// picture lines up texel for pixel with the view and a surface in the
  /// plane reads it by where it is on screen. The near plane is moved onto
  /// the plane (see `obliqueNearPlane`), so what is below it — the floor's
  /// underside, the pool's bed — is cut away rather than reflected up
  /// through it.
  void _drawPlanarReflection({
    required FrameResources resources,
    required Scene scene,
    required PlanarReflectorNode reflector,
    required _PlanarState state,
    required List<RenderView> views,
    required int width,
    required int height,
    required RenderSettings settings,
    required SceneShadows shadows,
    required FramePassState passState,
  }) {
    final normal = reflector.readPlaneNormal();
    final point = reflector.readWorldPosition();
    final mirror = mirrorAcrossPlane(normal, point);
    final excluded = <SceneNode>{...reflector.surfaces, ...reflector.excluded};
    while (state.textures.length < views.length) {
      state.textures.add(null);
      state.drawn.add(false);
    }
    state.frame = _frameIndex;
    for (var i = 0; i < views.length; i++) {
      state.drawn[i] = false;
      final view = views[i];
      final camera = view.camera;
      final eye = camera.readViewOrigin();
      // From behind, or level with it: no reflection to see.
      if (normal.dot(eye - point) <= 0.0) continue;

      final rect = Renderer._viewportPixels(
        view.viewportFraction,
        width,
        height,
      );
      final pictureWidth = math.max(
        1,
        (rect.width * reflector.resolution).round(),
      );
      final pictureHeight = math.max(
        1,
        (rect.height * reflector.resolution).round(),
      );
      final kept = state.textures[i];
      final TextureHandle picture;
      if (kept != null &&
          kept.width == pictureWidth &&
          kept.height == pictureHeight) {
        picture = kept;
      } else {
        _destroyAfterFrame(kept);
        picture = device.createTexture(
          RenderTargetDescriptor(
            width: pictureWidth,
            height: pictureHeight,
            format: hdrFormat,
          ),
        );
        state.textures[i] = picture;
      }

      final vm.Matrix4 mirroredView = camera.viewMatrix * mirror;
      // A finite far plane for the mirror, whatever the camera's: the oblique
      // near plane leans the far one through the frustum's far corner, and an
      // infinite projection has no corner there to lean it through.
      final lens = camera.projection;
      final aspect = rect.width / rect.height;
      final projection = lens.far.isFinite
          ? lens.toMatrix(aspect)
          : (withDepthPlanes(
                  lens.toMatrix(aspect),
                  near: lens.near,
                  far: _DepthConvention._finiteFar(lens),
                ) ??
                lens.toMatrix(aspect));
      final clipped =
          obliqueNearPlane(
            projection,
            planeInEyeSpace(
              mirroredView,
              normal,
              point,
              offset: reflector.clipOffset,
            ),
          ) ??
          projection;
      _captureView(
        resources: resources,
        scene: scene,
        color: picture,
        viewProjection: toDepthRange(clipped * mirroredView, device.depthRange),
        skyViewProjection: toDepthRange(
          projection * mirroredView,
          device.depthRange,
        ),
        eye: mirror.transform3(eye),
        layerMask: view.layerMask & reflector.reflectedLayers,
        excluded: excluded,
        mirrored: true,
        settings: settings,
        shadows: shadows,
        passState: passState,
        clearColor: view.clearColorSrgb,
      );
      state.drawn[i] = true;
    }
  }

  /// Lays every reflector's picture for view [viewNumber] over the surfaces
  /// that show it, inside the scene pass and straight after its opaque half.
  ///
  /// After the opaque half because the test is `lessEqual` against what the
  /// surface itself wrote: a fragment of the second draw passes exactly
  /// where the surface was not hidden. A blended surface writes no depth and
  /// is drawn after this, so on water that blends its picture lies under the
  /// water rather than on it.
  void _encodePlanarReflections({
    required PassEncoder encoder,
    required Scene scene,
    required RenderView view,
    required int viewNumber,
    required ScreenRect rect,
    required vm.Frustum frustum,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required SceneShadows shadows,
    required FramePassState state,
  }) {
    if (!settings.planarReflections.enabled || _planarStates.isEmpty) return;
    for (final reflector in scene.reflectors) {
      final planar = _planarStates[reflector];
      if (planar == null ||
          planar.frame != _frameIndex ||
          viewNumber >= planar.drawn.length ||
          !planar.drawn[viewNumber]) {
        continue;
      }
      final picture = planar.textures[viewNumber]!;
      _planarInfo.view
        ..[0] = rect.x.toDouble()
        ..[1] = rect.y.toDouble()
        ..[2] = rect.width.toDouble()
        ..[3] = rect.height.toDouble();
      _planarInfo.params
        ..[0] = reflector.reflectance
        ..[1] = reflector.strength
        // The rows the scene pass set for its own target, which is this one.
        ..[2] = _targetOrigin[0];
      _planarInfo.tint
        ..[0] = reflector.tint.r
        ..[1] = reflector.tint.g
        ..[2] = reflector.tint.b;
      _planarMaterial.extraTextures['reflection_texture'] = picture;
      for (final surface in reflector.surfaces) {
        if (!surface.isVisibleInHierarchy ||
            !surface.shadowCasting.drawsColor ||
            (surface.layerMask & view.layerMask) == 0) {
          continue;
        }
        if (surface.frustumCulled &&
            !frustum.intersectsWithAabb3(surface.worldBounds)) {
          continue;
        }
        final mesh = surface.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
        // The surface's own answer to which faces exist, as the x-ray's
        // marks take it.
        _planarMaterial.doubleSided = surface.material.doubleSided;
        _encodeNode(
          encoder: encoder,
          node: surface,
          scene: scene,
          settings: settings,
          viewProjection: viewProjection,
          shadows: shadows,
          lights: _frameLights,
          shadowSlots: _shadowSlots,
          state: state,
          override: _DrawOverride(
            material: _planarMaterial,
            blend: BlendState.alphaBlend,
            fogged: surface.material.fogged,
          ),
        );
      }
    }
  }
}
