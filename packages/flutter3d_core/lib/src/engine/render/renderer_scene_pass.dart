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
  /// Draws every view of the world into the HDR target, submits it, and
  /// returns what the pass counted.
  ///
  /// Views share a single render pass and clear: viewports do not overlap in the
  /// split-screen case, and one pass is both cheaper and simpler than a pass per
  /// view. Views are drawn in ascending priority, as in PlayCanvas.
  ///
  /// The body of [_SceneNode], extracted before the node existed so that the
  /// move was verifiable on its own: it changed no behaviour, so the goldens had
  /// to match byte for byte, and a refactor that moves the picture moved
  /// something else too.
  ///
  /// It owns the render target, the command buffer and the pass, which is what
  /// a node has to own. Ordering against the shadow passes is by *submission* —
  /// they build and submit their own command buffers before this one, and the
  /// queue runs buffers in the order they were submitted. That is the fact that
  /// makes the graph cheap to adopt here: it has to derive a submission order,
  /// not take over how passes are built.
  ///
  /// [surfaceIsRead] is the graph's answer about the frame that is running, not
  /// a setting: it decides both whether the second attachment is present and
  /// whether the pass may multisample, and those two must agree.
  ///
  /// [shadows] is the same shape of answer: every map this pass samples, taken
  /// from the frame by the node that declared it and handed down rather than
  /// looked up here. The atlases used to be the exception — bound deep in
  /// [_encodeNode] straight out of a renderer field, because the view model
  /// reaches that same code through [RenderServices.encodeScene] and only one
  /// of the two callers declared the read. Two nodes and one binding site is
  /// still true; what changed is that each of them now answers for itself.
  ///
  /// [contributors] are handed in rather than looked up. A node that reaches
  /// into a global registry cannot be a node somebody else supplies, which is
  /// the whole point of the extension model — and the distinction it makes is
  /// the one the migration keeps running into: a contributor draws *into* this
  /// pass, so it takes the pass as an argument, while a node *owns* one and
  /// therefore cannot be handed one. That is why there are two contexts:
  /// `ContributorFrame` carries a pass and `NodeFrame` does not.
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
    bool albedoIsRead = false,
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
    //
    // Nor under weighted blended transparency — `R8`: its layers are drawn
    // after this pass against the depth it stores, into one-sample targets
    // the resolve reads, so the depth is one-sample too.
    final orderIndependent =
        settings.transparency == TransparencyMode.weightedBlended;
    final msaa = surfaceIsRead || orderIndependent ? null : _hdrMsaa;
    final deferred = <_DeferredTransparency>[];
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
        label: _passLabel,
        colors: <ColorTarget>[
          colorAttachment,
          ?surfaceAttachment,
          // `L5`: the albedo buffer, beside the surface buffer and only with
          // it, so the attachments stay consecutive.
          if (albedoIsRead && surfaceAttachment != null)
            ColorTarget(texture: _albedoColor!, clearValue: vm.Vector4.zero()),
        ],
        // Standard depth: clear to the far plane, nearer fragments win.
        // Stored for the transparent layers when they are drawn apart.
        depth: orderIndependent
            ? DepthTarget(
                texture: _weightedBlendedTargets().depth,
                storeAction: StoreAction.store,
              )
            : DepthTarget(
                texture: msaa == null
                    ? (_depthStencilSingle ?? _depthStencil!)
                    : _depthStencil!,
              ),
      ),
    );

    _targetOrigin[0] = _rowsFromBottom(hdr);
    // `R2`: while a resolve reconstructs the picture, the material maps are
    // read at the sharpness of the output rather than of the scene — the
    // scale's octaves, and half a level more, because the history averages
    // sixteen jittered reads and would soften a map read at its own level.
    // Nought otherwise, which is exactly what every map was read with before.
    final temporal =
        settings.antiAlias.temporal.enabled && device.maxColorAttachments > 1;
    _targetOrigin[1] = temporal
        ? math.log(settings.renderScale.clamp(0.1, 1.0)) / math.ln2 - 0.5
        : 0.0;
    // `L1`: the metal-rough model's multiple scattering, on or off.
    _targetOrigin[2] = settings.energyCompensation ? 1.0 : 0.0;
    // `S3`: the frame's slice while a resolve runs, which turns the soft
    // shadow's taps anew each frame for the history to average; minus one
    // otherwise, and the turn stays put.
    _targetOrigin[3] = temporal ? (_frameIndex % 32).toDouble() : -1.0;
    final cameraPosition = vm.Vector3.zero();

    for (var viewNumber = 0; viewNumber < ordered.length; viewNumber++) {
      final view = ordered[viewNumber];
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

      final viewRect = Renderer._viewportPixels(
        view.viewportFraction,
        width,
        height,
      );
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
      final viewMatrix = camera.viewMatrix;
      final viewProjection = _drawViewProjection(camera, viewRect, settings);

      // `L6`: the cells, cut with the matrix the draws use, so a fragment
      // finds its cell the way the builder placed the lights.
      _clustersActive =
          settings.clusteredLights &&
          !lights.anyChannelled &&
          lights.candidates.length > LightBuffer.maxLights;
      if (_clustersActive) {
        _lightClusters.build(
          lights,
          viewProjection,
          near: camera.projection.near,
          far: camera.projection.far,
        );
      }

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
      developer.Timeline.startSync('Renderer.occlusion');
      final occlusion = _occlusionFor(
        scene: scene,
        view: view,
        settings: settings,
        frustum: frustum,
        aspect: viewRect.width / viewRect.height,
        views: ordered.length,
      );
      developer.Timeline.finishSync();
      developer.Timeline.startSync('RenderList.build');
      _renderList.build(
        scene,
        view,
        viewMatrix: viewMatrix,
        frustum: frustum,
        occlusion: occlusion,
      );
      developer.Timeline.finishSync();

      developer.Timeline.startSync('RenderList.sort');
      _renderList.sort(view);
      developer.Timeline.finishSync();
      culled += visibleBefore - _renderList.length;

      // `C9`: a split mesh's clusters are culled against what its node was,
      // at the draw, with the matrix the draw uses.
      _clusterView = (
        view: viewNumber,
        frustum: frustum,
        viewProjection: viewProjection,
        occlusion: occlusion,
      );

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
      void encodeOne(MeshNode node) => _encodeNode(
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

      void encodeHalf(List<int> indices) {
        for (var i = 0; i < indices.length; i++) {
          encodeOne(_renderList.itemAt(indices[i]).requireNode);
        }
      }

      if (settings.batchIdenticalDraws) {
        _encodeBatchedOpaque(
          indices: _renderList.opaque,
          probes: probes,
          encode: encodeOne,
        );
      } else {
        encodeHalf(_renderList.opaque);
      }
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
      if (orderIndependent) {
        // Kept rather than drawn, with what the passes after this one need
        // to draw them as this view would have — `R8`.
        deferred.add((
          view: view,
          rect: viewRect,
          viewProjection: viewProjection.clone(),
          wireframe: wireframe,
          clustered: _clustersActive,
          eye: cameraPosition.clone(),
          forward: _forward.clone(),
          transparent: <MeshNode>[
            for (final index in _renderList.transparent)
              _renderList.itemAt(index).requireNode,
          ],
        ));
      } else {
        encodeHalf(_renderList.transparent);
      }
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

      // After the resolve instead, when there is one — `R8`.
      for (final plugin
          in orderIndependent ? const <PassContributor>[] : contributors) {
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

      _clusterView = null;

      // The debug overlay is deliberately NOT drawn here. Anything written into
      // the HDR target is scene light: it would be tone mapped, and a bright
      // enough gizmo would bleed into the bloom. The overlay belongs on top of
      // the finished image, so it is drawn in the composite pass below.
    }
    // `S4`: the fog marches after this pass and reads the cells the view
    // drew with. Built here if no lit draw built them — the list compares
    // its rows first, so a view whose draws did costs a comparison — and
    // kept with its row count, because a later pass may rebuild the list
    // without cells before the fog runs. Only with the fog on: with it off
    // nothing here happens and nothing is uploaded. The flag is read again
    // after the build, which turns it off for a view whose cells would not
    // fit the texture; the list it returns then holds no cells to read.
    //
    // With several views the cells are the last view's, cut with its matrix
    // and looked up with that same matrix, so they stay consistent; a point
    // off that view's screen reads an edge cell.
    final fogCells = settings.volumetricFog.enabled && _clustersActive
        ? _buildLightList(lights)
        : null;
    _fogCells = _clustersActive ? fogCells : null;
    _fogCellRows = _lightListRows;
    _clustersActive = false;

    // Submitted before the post passes: they sample this target, and the queue
    // orders command buffers by submission.
    developer.Timeline.startSync('CommandBuffer.submit');
    final stopwatch = Stopwatch()..start();
    pass.submit();
    stopwatch.stop();
    developer.Timeline.finishSync();

    if (orderIndependent) {
      _encodeWeightedBlended(
        scene: scene,
        views: deferred,
        settings: settings,
        width: width,
        height: height,
        shadows: shadows,
        probes: probes,
        passState: passState,
        contributors: contributors,
      );
    }

    return _ScenePass(
      culled: culled,
      debugLines: debugLines,
      lightOverflow: lightOverflow,
      submitMicros: stopwatch.elapsedMicroseconds,
      // `gfx-20n`. What the pass drew with, not what was asked for: `msaa`
      // above is null whenever the surface buffer is attached, and that is
      // the case a caller cannot otherwise see.
      msaaSamples: msaa == null ? 1 : device.preferredSampleCount,
      // **The device first, and the order is the point.** A device that
      // cannot multisample at all is the cause whatever else is true, and
      // blaming the surface buffer there would send somebody to remove an
      // effect that was never the reason. The buffer is named only where
      // multisampling was available and this frame gave it up.
      msaaDeclined: msaa != null
          ? null
          : (!device.supportsOffscreenMsaa
                ? 'this device has no multisampled offscreen target'
                : (surfaceIsRead
                      ? 'a pass in this frame reads the surface buffer, and '
                            'attachments in one target must agree on sample '
                            'count'
                      : (orderIndependent
                            ? 'weighted blended transparency draws its '
                                  'layers against a one-sample depth'
                            : null))),
    );
  }

  /// The test [view]'s render list is built against, or null for none —
  /// `C2`, `C3`.
  ///
  /// Through the view's own unjittered matrix in the engine's `[0, 1]` depth,
  /// whatever the device's convention: both methods compare depths with each
  /// other and never with the depth buffer, so they only have to agree among
  /// themselves. Nothing in wireframe, where no surface hides another.
  ///
  /// A frame without hi-Z throws the reading away. A reading kept across
  /// frames that did not ask for one describes a scene nothing has been
  /// watching, and would be reprojected the moment the setting came back.
  OcclusionTest? _occlusionFor({
    required Scene scene,
    required RenderView view,
    required RenderSettings settings,
    required vm.Frustum frustum,
    required double aspect,
    required int views,
  }) {
    final mode = settings.wireframe ? OcclusionMode.none : settings.occlusion;
    if (mode != OcclusionMode.hiZ && _hiZ != null) {
      _hiZ!.reset();
      _hiZEpoch++;
    }
    final camera = view.camera;
    switch (mode) {
      case OcclusionMode.none:
        return null;
      case OcclusionMode.software:
        return (_softwareOcclusion ??= SoftwareOcclusion()).prepare(
          meshes: scene.meshes,
          viewProjection: camera.viewProjection(aspect),
          frustum: frustum,
          eye: camera.readWorldPosition(),
          layerMask: view.layerMask,
          cullBackFaces: settings.backfaceCulling,
        );
      case OcclusionMode.hiZ:
        final hiZ = _hiZ ??= HiZOcclusion();
        // The pyramid reduces the whole frame for one camera, so with a
        // second view there is no reading to have; see `_DepthPyramidNode`.
        if (views != 1) return null;
        return hiZ.prepare(
          camera.viewProjection(aspect),
          eye: camera.readWorldPosition(),
          forward: camera.readForward(),
          camera: camera,
        );
    }
  }
}
