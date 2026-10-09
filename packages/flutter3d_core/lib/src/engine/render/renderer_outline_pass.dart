/// The high-contrast look — `N9`: the marks a game put on its nodes, and the
/// pass that flattens, tones and outlines the finished picture around them.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why these
/// are extensions on `Renderer` rather than files of their own.
///
/// **Two passes, and only the second always runs while the look is on.** The
/// marks are a scene's worth of draws at most and usually a handful — the
/// monsters and the pickups in view — drawn through the velocity vertex
/// stages into a small target of their own, and only when some node carries a
/// colour. The look itself is one full-screen draw over the finished frame,
/// reading that target, the surface buffer and the picture.
part of 'renderer.dart';

extension _OutlinePass on Renderer {
  /// Draws every visible node of [views] that has a `MeshNode.outlineColor`
  /// into [target] in that colour, dropping what the surface buffer says is
  /// hidden, and returns how many were drawn.
  ///
  /// Opaque and blended alike: a pickup made of glass is still a pickup. A
  /// blended node wrote no depth, so it is tested against what is behind it
  /// and passes — it is in front of everything the buffer knows about, which
  /// is where it is.
  int _encodeOutlineMask({
    required TextureHandle target,
    required TextureHandle surface,
    required Scene scene,
    required List<RenderView> views,
    required RenderSettings settings,
    required int width,
    required int height,
  }) {
    developer.Timeline.startSync('Renderer.outlineMask');
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          // Nought is "not marked", which is what the look reads alpha for.
          ColorTarget(texture: target, clearValue: vm.Vector4.zero()),
        ],
      ),
    );

    _outlineMaskInfo.target
      ..[0] = 1.0 / target.width
      ..[1] = 1.0 / target.height
      // Nought on every backend, for the reason the velocity pass gives: the
      // surface-buffer texel under a fragment is `gl_FragCoord` itself,
      // wherever that backend's row zero is.
      ..[2] = 0.0
      // The velocity pass's hundredth: the surface buffer holds the depth of
      // the same triangle this draws, so the two agree to rounding.
      ..[3] = 0.01;

    var drawn = 0;
    for (final view in views) {
      final rect = Renderer._viewportPixels(
        view.viewportFraction,
        width,
        height,
      );
      final camera = view.camera;
      final unjittered = camera.viewProjection(rect.width / rect.height);
      _renderList.build(
        scene,
        view,
        viewMatrix: camera.viewMatrix,
        frustum: _DepthConvention._viewFrustum(unjittered),
      );
      final marked = <MeshNode>[
        for (final index in <int>[
          ..._renderList.opaque,
          ..._renderList.transparent,
        ])
          if (_renderList.itemAt(index).requireNode case final node
              when node.outlineColor != null && node.mesh is DrawableGeometry)
            node,
      ];
      if (marked.isEmpty) continue;

      final current = toFramebufferOrigin(unjittered, device.framebufferOrigin);
      // Jittered as the scene was, so a mark lands on the pixels the scene
      // drew its node on rather than half a pixel beside them.
      final jittered = _drawViewProjection(camera, rect, settings);
      _velocityCamera(camera);
      pass.setState(
        Renderer._kSceneViewState.copyWith(
          viewport: rect,
          scissor: rect,
          polygonMode: PolygonMode.fill,
          blend: null,
          depthWrite: false,
          depthCompare: CompareFunction.always,
        ),
      );

      for (final node in marked) {
        final stage = _bindVelocityNode(
          pass: pass,
          node: node,
          past: null,
          jittered: jittered,
          current: current,
          previous: current,
          fragment: _outlineMaskShader,
          name: 'OutlineMask',
          settings: settings,
        );
        if (stage == null) continue;
        final color = node.outlineColor!;
        _outlineMaskInfo.color
          ..[0] = LinearColor.linearToSrgb(color.r).clamp(0.0, 1.0)
          ..[1] = LinearColor.linearToSrgb(color.g).clamp(0.0, 1.0)
          ..[2] = LinearColor.linearToSrgb(color.b).clamp(0.0, 1.0)
          ..[3] = 1.0;
        pass
          ..bindBlock(_outlineMaskShader, _outlineMaskInfo)
          ..bindTexture(
            _outlineMaskShader,
            'surface_texture',
            surface,
            sampler: SamplerDescriptor.nearestClamp,
          )
          ..draw(instanceCount: node is InstancedMeshNode ? node.count : 1);
        drawn++;
      }
    }
    pass.submit();
    developer.Timeline.finishSync();
    return drawn;
  }

  /// Draws the look over [scene] and returns the result.
  ///
  /// [surface] and [mask] are optional reads and a null is not an error: no
  /// surface buffer is a device that could not attach one, and the look
  /// drains and pushes the tone without flattening or outlining anything; no
  /// mask is a frame with nothing marked. Each is said to the shader as a
  /// flag, with a black texel bound in its place, because a sampler a stage
  /// declares must have something under it.
  TextureHandle _encodeHighContrast({
    required TextureHandle scene,
    required TextureHandle? surface,
    required TextureHandle? mask,
    required HighContrastSettings settings,
    required FrameResources resources,
  }) {
    developer.Timeline.startSync('Renderer.highContrast');
    final target = resources.transient(
      RenderTargetDescriptor(
        width: scene.width,
        height: scene.height,
        format: scene.format,
      ),
    );

    _highContrastInfo.look
      ..[0] = settings.flatten.clamp(0.0, 1.0)
      ..[1] = math.max(settings.contrast, 0.0)
      ..[2] = settings.saturation.clamp(0.0, 1.0)
      ..[3] = settings.roleFill.clamp(0.0, 1.0);
    _highContrastInfo.edges
      ..[0] = math.max(settings.depthEdge, 1e-4)
      ..[1] = settings.normalEdge.clamp(1e-4, 2.0)
      ..[2] = math.max(settings.outlineWidth, 0.0)
      ..[3] = math.max(settings.flattenSpacing, 1.0);
    final line = settings.outlineColor;
    _highContrastInfo.line
      ..[0] = line == null ? 0.0 : LinearColor.linearToSrgb(line.r)
      ..[1] = line == null ? 0.0 : LinearColor.linearToSrgb(line.g)
      ..[2] = line == null ? 0.0 : LinearColor.linearToSrgb(line.b)
      // Four is as far as the shader looks, so a wider ask is said as four
      // rather than as a number the shader silently clips.
      ..[3] = settings.roleWidth.clamp(0.0, 4.0);
    _highContrastInfo.screen
      ..[0] = scene.width == 0 ? 0.0 : 1.0 / scene.width
      ..[1] = scene.height == 0 ? 0.0 : 1.0 / scene.height
      ..[2] = surface == null ? 0.0 : 1.0
      ..[3] = mask == null ? 0.0 : 1.0;

    drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: _highContrastShader,
        textures: <String, TextureHandle>{
          'scene_texture': scene,
          'surface_texture': surface ?? fallbackBlack,
          'mask_texture': mask ?? fallbackBlack,
        },
        uniforms: <String, Map<String, Float32List>>{
          'HighContrastInfo': _highContrastInfo.members,
        },
        // Nearest on both buffers, for the reason the viewport shading gives:
        // a filtered tap at a silhouette averages a foreground normal with
        // the cleared background, and a filtered mark averages a colour with
        // nought — each a value belonging to neither side.
        samplers: const <String, SamplerDescriptor>{
          'surface_texture': SamplerDescriptor.nearestClamp,
          'mask_texture': SamplerDescriptor.nearestClamp,
        },
      ),
    );
    developer.Timeline.finishSync();
    return target;
  }
}
