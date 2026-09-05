/// The scene pass: every mesh the camera can see, encoded into one draw list.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// The largest of the passes by a wide margin, and the one everything else
/// exists to support: the shadow passes fill what it samples, the post passes
/// work on what it wrote.
///
/// Encoding one mesh node — pipeline, uniforms, textures, draw — lives next
/// door in `renderer_mesh_encode.dart`: it is a self-contained procedure
/// reused by the view-model pass, whereas what stays here is specific to
/// iterating this frame's views and building the render list they draw from.
part of 'renderer.dart';

extension _ScenePasses on Renderer {
  /// Renders every view into one target and returns the composited image.
  ///
  /// Views share a single render pass and clear: viewports do not overlap in the
  /// split-screen case, and one pass is both cheaper and simpler than a pass per
  /// view. Views are drawn in ascending priority, as in PlayCanvas.
  _ScenePass _encodeScene({
    required Scene scene,
    required List<RenderView> ordered,
    required RenderSettings settings,
    required int width,
    required int height,
    required SceneShadows shadows,
    required _SceneProbes probes,
    required FramePassState passState,
    required int lightOverflowCount,
    required List<PassContributor> contributors,
    required bool surfaceIsRead,
  }) {
    final hdr = _hdrColor!;
    var culled = 0;
    final debugLines = 0;
    var lightOverflow = 0;
    // No multisampling while the surface buffer is wanted, and that is a
    // correctness matter rather than a budget one. Attachments in one target
    // must agree on sample count, so the surface buffer would be resolved by
    // averaging — and the average of two octahedrally encoded normals is not
    // the encoding of any normal. Every silhouette pixel would decode to a
    // direction belonging to neither face, which a reflection shows as a
    // fringe of wrong angles along every edge.
    //
    // A golden caught this before any reflection did: surface-buffer sat just
    // outside its tolerance, every differing pixel on an edge, and which
    // pixels differed changed between runs.
    final msaa = surfaceIsRead ? null : _hdrMsaa;
    // The clear colour is authored the way a colour picker shows it, but the
    // scene target holds linear light and the composite pass encodes on the way
    // out. Clearing with the sRGB value directly would send it through the
    // encode twice and wash the background out.
    final clear = Renderer._srgbToLinear(ordered.first.clearColor);

    final colorAttachment = msaa == null
        ? ColorTarget(texture: hdr, clearValue: clear)
        : ColorTarget(
            texture: msaa,
            resolveTexture: hdr,
            storeAction: StoreAction.multisampleResolve,
            clearValue: clear,
          );

    // Attached only when something wants it. A pipeline may declare more
    // outputs than the target has attachments — the extra is discarded — so
    // the shaders write the surface unconditionally and this decides whether
    // anyone is listening. See ARCHITECTURE.md §2.
    final surface = surfaceIsRead ? _surfaceColor : null;
    final surfaceAttachment = surface == null
        ? null
        : (msaa == null
              ? ColorTarget(texture: surface, clearValue: vm.Vector4.zero())
              : ColorTarget(
                  texture: _surfaceMsaa!,
                  resolveTexture: surface,
                  storeAction: StoreAction.multisampleResolve,
                  clearValue: vm.Vector4.zero(),
                ));

    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[colorAttachment, ?surfaceAttachment],
        // Standard depth: clear to the far plane, nearer fragments win.
        depth: DepthTarget(
          texture: msaa == null
              ? (_depthStencilSingle ?? _depthStencil!)
              : _depthStencil!,
        ),
      ),
    );

    final cameraPosition = vm.Vector3.zero();

    for (final view in ordered) {
      // Per view rather than once: the debug overlay at the end of each view
      // leaves the pass in line-drawing state, so the next view has to
      // re-establish its own.
      //
      // Viewport and scissor are set explicitly because both default to a
      // zero-sized rect, and nothing in the API complains about drawing into one.
      // Asked, not assumed. A backend without glPolygonMode — OpenGL ES has
      // none — refuses the request rather than filling the triangles instead,
      // and a refusal mid-frame is a crash where a declined setting is a
      // picture. Wireframe there needs line primitives from an index buffer
      // built for it, which is geometry work and not a backend's to invent.
      final wireframe = settings.wireframe && device.supportsWireframe;

      final fraction = view.viewportFraction;
      final vx = (fraction.x * width).round();
      final vy = (fraction.y * height).round();
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());

      final viewRect = ScreenRect(x: vx, y: vy, width: vw, height: vh);
      pass.setState(
        Renderer._kSceneViewState.copyWith(
          viewport: viewRect,
          scissor: viewRect,
          polygonMode: wireframe ? PolygonMode.line : PolygonMode.fill,
        ),
      );
      // That state names the depth test, so the tracker has to agree with it or
      // the first material of the next view would skip a call it needs. The
      // debug overlay at the end of a view leaves the test on `always`, which
      // is exactly the case this catches.
      passState.depthCompare = CompareFunction.less;

      final camera = view.camera;
      final aspect = vw / vh;
      final viewMatrix = camera.viewMatrix;
      final viewProjection = _viewProjection(camera, aspect);

      // Before the render list is built, because choosing a level changes which
      // nodes are visible and the list is built from what is.
      //
      // Driven here rather than left to the application, which is the fix for a
      // feature that was written, tested and then never actually ran: nothing
      // called select(), so every LOD group sat on its finest level for ever
      // and the whole thing was decoration.
      developer.Timeline.startSync('LodGroup.select');
      for (final group in scene.lodGroups) {
        group.select(camera);
      }
      developer.Timeline.finishSync();
      final frustum = vm.Frustum.matrix(viewProjection);

      final visibleBefore = scene.meshes.length;
      developer.Timeline.startSync('RenderList.build');
      _renderList.build(scene, view, viewMatrix: viewMatrix, frustum: frustum);
      developer.Timeline.finishSync();

      developer.Timeline.startSync('RenderList.sort');
      _renderList.sort(view);
      developer.Timeline.finishSync();
      culled += visibleBefore - _renderList.length;

      camera.readWorldPosition(cameraPosition);

      lightOverflow = lightOverflowCount;

      _cameraData[0] = cameraPosition.x;
      _cameraData[1] = cameraPosition.y;
      _cameraData[2] = cameraPosition.z;

      // The axis the surface buffer's depths are measured along, and the reason
      // it is read from the camera here and from the matrix elsewhere: this
      // pass has a camera node and the others do not. Both answer the same
      // question — see `viewAxisOf`.
      camera.readForward(_forward);
      _forwardData[0] = _forward.x;
      _forwardData[1] = _forward.y;
      _forwardData[2] = _forward.z;

      developer.Timeline.startSync('Renderer.encodeDraws');
      void encodeHalf(List<int> indices) {
        for (var i = 0; i < indices.length; i++) {
          final node = _renderList.itemAt(indices[i]).requireNode;
          _encodeNode(
            encoder: pass,
            node: node,
            scene: scene,
            settings: settings,
            viewProjection: viewProjection,
            shadows: shadows,
            probes: probes,
            lights: lights,
            shadowSlots: _shadowSlots,
            state: passState,
          );
        }
      }

      encodeHalf(_renderList.opaque);
      // Between the two halves, which is the one place it can go. After the
      // opaque half, so every pixel already covered by geometry fails the depth
      // test before the sky's fragment stage runs — the software rasteriser
      // tests depth before calling the fragment shader, so this is real work
      // saved on the backend that can least afford it. Before the transparent
      // half, so glass has something behind it to blend with.
      _encodeSky(
        pass: pass,
        settings: settings,
        viewProjection: viewProjection,
        state: passState,
      );
      encodeHalf(_renderList.transparent);
      // After everything that writes depth and everything that blends over
      // it, because a silhouette is drawn where the depth test *fails*: the
      // walls have to be in the buffer for a monster to be behind one. Before
      // the contributors, so a particle drawn without depth writes still
      // lands over a silhouette the way it lands over the monster itself.
      _encodeXray(
        encoder: pass,
        scene: scene,
        settings: settings,
        viewProjection: viewProjection,
        shadows: shadows,
        lights: lights,
        shadowSlots: _shadowSlots,
        state: passState,
      );
      developer.Timeline.finishSync();

      for (final plugin in contributors) {
        plugin.encode(
          ContributorFrame(
            encoder: pass,
            device: device,
            services: this,
            state: passState,
            settings: settings,
            width: width,
            height: height,
            view: view,
            viewProjection: viewProjection,
          ),
        );
      }

      // The debug overlay is deliberately NOT drawn here. Anything written into
      // the HDR target is scene light: it would be tone mapped, and a bright
      // enough gizmo would bleed into the bloom. The overlay belongs on top of
      // the finished image, so it is drawn in the composite pass below.
    }

    // Submitted before the post passes: they sample this target, and the queue
    // orders command buffers by submission.
    developer.Timeline.startSync('CommandBuffer.submit');
    final stopwatch = Stopwatch()..start();
    pass.submit();
    stopwatch.stop();
    developer.Timeline.finishSync();

    return _ScenePass(
      culled: culled,
      debugLines: debugLines,
      lightOverflow: lightOverflow,
      submitMicros: stopwatch.elapsedMicroseconds,
    );
  }
}
