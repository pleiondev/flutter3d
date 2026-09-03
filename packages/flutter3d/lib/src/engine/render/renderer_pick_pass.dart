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

/// One question the next frame answers: what is drawn at a point.
final class _PickRequest {
  _PickRequest(this.u, this.v);

  /// Where, as fractions of the frame from the top left.
  final double u;
  final double v;

  final Completer<MeshNode?> completer = Completer<MeshNode?>();
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
    if (!pick.completer.isCompleted) pick.completer.completeError(error, stack);
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
      final fraction = view.viewportFraction;
      final rect = ScreenRect(
        x: (fraction.x * width).round(),
        y: (fraction.y * height).round(),
        width: math.max(1, (fraction.width * width).round()),
        height: math.max(1, (fraction.height * height).round()),
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
        // A material that says it is drawn but not there — a backdrop — keeps
        // that here: it writes no depth, so what is behind it is what a click
        // on it finds. Everything else writes, blended or not, because the
        // nearest surface a pixel shows is the one somebody pointed at.
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
        pass.bindUniformBlock(stage, _kFrameInfoBlock, {
          'mvp': mvp.storage,
          'model': modelMatrix.storage,
          'normal_matrix': node.worldNormalMatrix.storage,
        });
        if (skeleton != null) {
          skeleton.update(modelMatrix);
          pass.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
            'joint_matrices': skeleton.matrices,
          });
        }

        drawn.add(node);
        final id = drawn.length;
        // A fresh list per draw rather than the renderer's usual reused
        // scratch: this pass runs on the frame somebody clicked, not on every
        // frame, and a recording backend keeps the list it was handed.
        //
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
        final masked = material.alphaMode == MaterialAlphaMode.mask;
        pass.bindUniformBlock(_objectIdShader, _kIdInfoBlock, {
          'id': Float32List.fromList(<double>[
            (id & 0xFF) / 255.0,
            ((id >> 8) & 0xFF) / 255.0,
            ((id >> 16) & 0xFF) / 255.0,
            1.0,
          ]),
          'mask': Float32List.fromList(<double>[
            masked ? material.alphaCutoff : -1.0,
            material.baseColor.w,
            0.0,
            0.0,
          ]),
        });
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
    //
    // Both answers check before they complete. A frame that fails after this
    // node has run answers its questions with the failure — see the catch in
    // `render` — and the device still hands back what it read; the readback
    // arriving second at a completer already finished would throw from inside
    // a `then`, where nothing is listening.
    final answers = List<MeshNode>.unmodifiable(drawn);
    for (final pick in picks) {
      final x = (pick.u * target.width).floor().clamp(0, target.width - 1);
      final y = (pick.v * target.height).floor().clamp(0, target.height - 1);
      device
          .readback(
            target,
            region: ScreenRect(x: x, y: y, width: 1, height: 1),
          )
          .then(
            (ByteData pixel) {
              if (pick.completer.isCompleted) return;
              final id =
                  pixel.getUint8(0) |
                  (pixel.getUint8(1) << 8) |
                  (pixel.getUint8(2) << 16);
              pick.completer.complete(
                id == 0 || id > answers.length ? null : answers[id - 1],
              );
            },
            onError: (Object error, StackTrace stack) {
              if (pick.completer.isCompleted) return;
              pick.completer.completeError(error, stack);
            },
          );
    }
    developer.Timeline.finishSync();
    return drawn.length;
  }
}
