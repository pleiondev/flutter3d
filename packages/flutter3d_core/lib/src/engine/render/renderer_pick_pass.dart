/// The picking pass: every visible mesh drawn again as its id, and one pixel
/// of that read back per question asked.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why these
/// are extensions on `Renderer` rather than files of their own.
///
/// **Why a pass rather than a ray.** A ray against bounds answers "which box
/// did I point at", and a box is not the thing: a monster's box is a metre
/// wider than the monster, a torch's box overlaps the wall it hangs on, and a
/// batch of brushes is one box for a whole room. The pixel under the cursor
/// belongs to exactly one draw, and the rasteriser already decided which. So
/// the scene is drawn once more with a stage that writes the draw's number
/// instead of its colour, and the answer is read off the picture — which is
/// what makes it exact by construction rather than by a tie-breaking rule.
///
/// It costs a scene's worth of draws on the frame it runs, which is why it
/// runs only on a frame something asked ([Renderer.pickPixel]) and never
/// otherwise: the node is inactive with no question pending, and an inactive
/// node is culled before it costs a texture.
part of 'renderer.dart';

/// One question the next frame's id pass answers: what is drawn at a point
/// ([_PixelPick]), or what is drawn everywhere ([_FramePick]).
///
/// **Two kinds of one question, on one queue**, because both are answered by
/// the same pass reading the same target: a frame that has either pending
/// draws the ids once, and each question reads the part of it it wants.
sealed class _PickRequest {
  Completer<Object?> get _completer;

  /// Asks [device] for this question's part of [target], queued behind the
  /// pass that filled it, and answers from what comes back. [nodes] maps an
  /// id back to its node, one-based.
  ///
  /// **Asked through `Future.sync`**, because a device refuses synchronously:
  /// `readbackRegionOf` throws before any future exists, and so does a WebGL2
  /// context that has lost its fence or a flutter_gpu copy that is turned
  /// down. Called bare, the first refusal would come out of the node and fail
  /// the whole frame — the picture with it — where what it is is one question
  /// that cannot be answered. Wrapped, it lands in the handler below, the
  /// question is completed with the error the caller is told to catch, and
  /// every other question in the list still gets asked.
  ///
  /// Both answers check before they complete. A frame that fails after the
  /// node has run answers its questions with the failure — see the catch in
  /// `render` — and the device still hands back what it read; the readback
  /// arriving second at a completer already finished would throw from inside
  /// a `then`, where nothing is listening.
  void ask(GraphicsDevice device, TextureHandle target, List<MeshNode> nodes) {
    Future<ByteData>.sync(
      () => device.readback(target, region: _regionOf(target)),
    ).then(
      (ByteData pixels) {
        if (_completer.isCompleted) return;
        _completer.complete(_answer(pixels, target, nodes));
      },
      onError: (Object error, StackTrace stack) {
        if (_completer.isCompleted) return;
        _completer.completeError(error, stack);
      },
    );
  }

  /// The part of the id target this question reads; null is all of it.
  ScreenRect? _regionOf(TextureHandle target);

  /// What [pixels] — [_regionOf]'s bytes — say to this question.
  Object? _answer(ByteData pixels, TextureHandle target, List<MeshNode> nodes);

  /// Answers a question no frame will ever answer, from `Renderer.dispose`.
  void abandon();
}

/// The id in the three low bytes of the RGBA8 pixel at [offset] of [pixels]:
/// red is the lowest, as `_encodeObjectIds` writes it.
int _idAt(ByteData pixels, int offset) =>
    pixels.getUint8(offset) |
    (pixels.getUint8(offset + 1) << 8) |
    (pixels.getUint8(offset + 2) << 16);

/// What is drawn at one point — [Renderer.pickPixel].
final class _PixelPick extends _PickRequest {
  _PixelPick(this.u, this.v);

  /// Where, as fractions of the frame from the top left.
  final double u;
  final double v;

  final Completer<MeshNode?> completer = Completer<MeshNode?>();

  @override
  Completer<Object?> get _completer => completer;

  @override
  ScreenRect _regionOf(TextureHandle target) => ScreenRect(
    x: (u * target.width).floor().clamp(0, target.width - 1),
    y: (v * target.height).floor().clamp(0, target.height - 1),
    width: 1,
    height: 1,
  );

  @override
  MeshNode? _answer(
    ByteData pixels,
    TextureHandle target,
    List<MeshNode> nodes,
  ) {
    final id = _idAt(pixels, 0);
    return id == 0 || id > nodes.length ? null : nodes[id - 1];
  }

  /// Nothing, which is what a pick that finds no mesh answers too.
  @override
  void abandon() => completer.complete(null);
}

/// What is drawn at every pixel — [Renderer.captureObjectIds].
final class _FramePick extends _PickRequest {
  final Completer<ObjectIdFrame> completer = Completer<ObjectIdFrame>();

  @override
  Completer<Object?> get _completer => completer;

  @override
  ScreenRect? _regionOf(TextureHandle target) => null;

  @override
  ObjectIdFrame _answer(
    ByteData pixels,
    TextureHandle target,
    List<MeshNode> nodes,
  ) {
    final ids = Uint32List(target.width * target.height);
    for (var i = 0; i < ids.length; i++) {
      final id = _idAt(pixels, i * 4);
      // An id past the list is a byte the pass did not write, which the pixel
      // pick reads as nothing; the frame says the same.
      ids[i] = id > nodes.length ? 0 : id;
    }
    return ObjectIdFrame(
      width: target.width,
      height: target.height,
      ids: ids,
      nodes: nodes,
    );
  }

  /// An error rather than an empty frame: a picture of nothing would read as
  /// a scene with nothing in it, and the scene was never drawn.
  @override
  void abandon() => completer.completeError(
    StateError('the renderer was disposed before a frame answered'),
  );
}

/// Answers every question in [picks] still open with [error]: the frame they
/// were asked of did not happen.
///
/// Still open, and not simply every one, because the id pass may already have
/// handed a question to the device, and the device's own answer checks the
/// same way before it completes — whichever of the two arrives second at a
/// finished completer would otherwise throw from inside a `then`, where nothing
/// is listening. Called from both catches in `Renderer.render`: the one around
/// building the frame, where an application node reading a name nothing writes
/// fails, and the one around running it.
void _failPicks(List<_PickRequest> picks, Object error, StackTrace stack) {
  for (final pick in picks) {
    if (!pick._completer.isCompleted) {
      pick._completer.completeError(error, stack);
    }
  }
}

extension _PickPass on Renderer {
  /// The id stage, resolved on first use rather than at `Renderer.create`,
  /// like the particle and sky stages: an application whose bundle predates
  /// it should fail to *pick*, not fail to start.
  ShaderHandle get _objectIdShader {
    final shader = shaders['ObjectId'];
    if (shader == null) {
      throw StateError(
        'The bundle has no "ObjectId" fragment shader, which picking by pixel '
        'draws with. Rebuild it with tool/build_shaders.sh.',
      );
    }
    return shader;
  }

  PipelineHandle _objectIdPipelineFor({
    required bool skinned,
    required bool instanced,
  }) {
    final key = instanced
        ? 'instanced/ObjectId'
        : skinned
        ? 'skinned/ObjectId'
        : 'ObjectId';
    return _pipelineCache.putIfAbsent(
      key,
      () => instanced
          ? device.createPipeline(
              instancedVertexShader,
              _objectIdShader,
              layout: _kInstancedLayout,
            )
          : device.createPipeline(
              // The lightmapped stage is left out on purpose: it reads the
              // same layout as the plain one and differs only in what it
              // hands the fragment stage, which this one ignores.
              skinned ? skinnedVertexShader : vertexShader,
              _objectIdShader,
            ),
    );
  }

  /// Draws every visible mesh of every view into [target] as its id, submits,
  /// and answers each of [picks] from one pixel of it.
  ///
  /// Returns how many meshes were drawn. The ids are one-based positions in
  /// the order drawn, so zero — the clear — is "nothing here", and the list
  /// that maps them back is this frame's alone: the readback answers a frame
  /// or two later, and by then the scene may have changed, which is why the
  /// closure below holds the list rather than a field.
  int _encodeObjectIds({
    required FrameResources resources,
    required TextureHandle target,
    required Scene scene,
    required List<RenderView> ordered,
    required RenderSettings settings,
    required int width,
    required int height,
    required List<_PickRequest> picks,
  }) {
    developer.Timeline.startSync('Renderer.objectIds');
    // Scratch, through the frame's own source so the release waits out the
    // frames in flight — the same reason the shadow passes take theirs there.
    final depth = resources.transient(
      RenderTargetSpec(
        width: target.width,
        height: target.height,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          // Zero is the id nothing has, so the clear is the answer for a pixel
          // no mesh reaches.
          ColorTarget(texture: target, clearValue: vm.Vector4.zero()),
        ],
        depth: DepthTarget(texture: depth),
      ),
    );

    final drawn = <MeshNode>[];
    final mvp = vm.Matrix4.identity();
    for (final view in ordered) {
      final rect = Renderer._viewportPixels(
        view.viewportFraction,
        width,
        height,
      );
      // The scene pass's own state, with two things it leaves per material
      // decided once: no blending — an id is not a colour and half of one is
      // nothing — and the fill mode, since a wireframe of ids would pick the
      // wall behind every face.
      pass.setState(
        Renderer._kSceneViewState.copyWith(
          viewport: rect,
          scissor: rect,
          polygonMode: PolygonMode.fill,
          blend: null,
        ),
      );

      final camera = view.camera;
      final aspect = rect.width / rect.height;
      final viewProjection = _viewProjection(camera, aspect);
      _renderList.build(
        scene,
        view,
        viewMatrix: camera.viewMatrix,
        frustum: vm.Frustum.matrix(viewProjection),
      );

      // Opaque then transparent, the order the scene draws them, so the depth
      // test between the two halves answers the same way it did on screen.
      bool? boundSkinned;
      bool? boundInstanced;
      for (final index in <int>[
        ..._renderList.opaque,
        ..._renderList.transparent,
      ]) {
        final node = _renderList.itemAt(index).requireNode;
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
        final instanced = node is InstancedMeshNode ? node : null;
        if (instanced != null && instanced.count == 0) continue;
        final skeleton = node.skeleton;
        final skinned = skeleton != null;
        final batched = instanced != null;

        if (boundSkinned != skinned || boundInstanced != batched) {
          pass.bindPipeline(
            _objectIdPipelineFor(skinned: skinned, instanced: batched),
          );
          boundSkinned = skinned;
          boundInstanced = batched;
        }

        final material = node.material;
        pass.setWindingOrder(
          node.worldIsMirrored
              ? WindingOrder.clockwise
              : WindingOrder.counterClockwise,
        );
        pass.setCullMode(
          settings.backfaceCulling && !material.doubleSided
              ? CullMode.backFace
              : CullMode.none,
        );
        // **`?? true`, where the scene pass has `?? !blend`, and the
        // difference is a decision rather than an oversight.** A blended
        // surface is picked as though it were opaque: glass, a marker, an
        // additive flash all answer with themselves and not with what is seen
        // through them. That is what an editor wants — a click selects the
        // thing clicked, and a pane of glass is a thing — and it is what
        // matching the scene pass would give anyway, since the id stage does
        // not blend: the pane writes its number over the box either way, and
        // all the write decides is which of two *transparent* surfaces at one
        // pixel wins. Writing makes that the nearer one whatever order they
        // were drawn in; not writing makes it whichever was drawn last.
        //
        // A material that says it is drawn but not there — a backdrop — keeps
        // that here: it writes no depth, so what is behind it is what a click
        // on it finds. The one way to be seen through *and* picked through is
        // the masked one below, where the fragment is discarded in both passes
        // and there is no surface at that pixel at all.
        pass.setDepthWrite(material.depthWrite ?? true);
        pass.setDepthCompare(material.depthCompare ?? CompareFunction.less);

        pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
        pass.bindIndexBuffer(mesh.indices, mesh.indexType, mesh.indexCount);
        if (instanced != null) {
          pass.bindVertexData(
            instanced.instanceBytes,
            instanced.count,
            slot: 1,
          );
        }

        final stage = batched
            ? instancedVertexShader
            : skinned
            ? skinnedVertexShader
            : vertexShader;
        final modelMatrix = node.worldMatrix;
        mvp
          ..setFrom(viewProjection)
          ..multiply(modelMatrix);
        _frameInfo.mvp.setAll(0, mvp.storage);
        _frameInfo.model.setAll(0, modelMatrix.storage);
        _frameInfo.normalMatrix.setAll(0, node.worldNormalMatrix.storage);
        pass.bindBlock(stage, _frameInfo);
        _bindMorph(pass, stage, node.morph);
        if (instanced != null) {
          _bindInstanceMorph(pass, stage, instanced);
        }
        if (skeleton != null) {
          skeleton.update(modelMatrix);
          _skinInfo.jointMatrices.setAll(0, skeleton.matrices);
          pass.bindBlock(skinnedVertexShader, _skinInfo);
        }

        drawn.add(node);
        final id = drawn.length;
        // **What the scene pass throws away is thrown away here too.** A
        // masked material — glTF's `MASK`: a fence, a leaf, a grate —
        // discards every fragment whose alpha falls under its cutoff, and
        // what is on the screen through the hole is the thing behind it. The
        // id stage samples the same texture against the same cutoff, so a
        // click through the hole answers with what the eye sees there rather
        // than with the plane the hole is cut in. The cutoff is negative for
        // a material that is not masked, the encoding `material2.x` already
        // uses, and the tint's alpha rides beside it because the scene pass
        // multiplies the texel by that as well.
        // **Hashed counts as masked here, at a fixed half.** `gfx-16n`'s mode
        // keeps a random half-ish of its pixels, and a click is one pixel:
        // answering it with noise would make picking a leaf a coin toss that
        // changed with the camera. Half is the honest middle — a click near
        // the opaque core of a leaf hits, one at its faded edge does not, and
        // the answer is the same twice running.
        final masked =
            material.alphaMode == MaterialAlphaMode.mask ||
            material.alphaMode == MaterialAlphaMode.hashed;
        final cutoff = material.alphaMode == MaterialAlphaMode.hashed
            ? 0.5
            : material.alphaCutoff;
        _idInfo.id
          ..[0] = (id & 0xFF) / 255.0
          ..[1] = ((id >> 8) & 0xFF) / 255.0
          ..[2] = ((id >> 16) & 0xFF) / 255.0
          ..[3] = 1.0;
        _idInfo.mask
          ..[0] = masked ? cutoff : -1.0
          ..[1] = material.baseColor.w
          ..[2] = 0.0
          ..[3] = 0.0;
        pass.bindBlock(_objectIdShader, _idInfo);
        // For every draw, not only the masked ones: the stage declares the
        // sampler, and a sampler a stage has that nothing was bound to is
        // undefined on one backend and a dropped draw on another. An unmasked
        // material's texture is sampled and ignored, which is what the scene
        // pass does with it as well.
        pass.bindTexture(
          _objectIdShader,
          _kAlbedoTextureSlot,
          material.albedo ?? fallbackAlbedo,
          sampler: material.albedoSampler,
        );

        pass.draw(instanceCount: instanced?.count ?? 1);
      }
    }
    pass.submit();

    // After the submit, so the copy is queued behind the pass that fills the
    // target — which is the whole of what `readback` promises about order.
    // How each question reads it, and why a refusal is one question's answer
    // rather than the frame's failure, is `_PickRequest.ask`.
    final answers = List<MeshNode>.unmodifiable(drawn);
    for (final pick in picks) {
      pick.ask(device, target, answers);
    }
    developer.Timeline.finishSync();
    return drawn.length;
  }
}
