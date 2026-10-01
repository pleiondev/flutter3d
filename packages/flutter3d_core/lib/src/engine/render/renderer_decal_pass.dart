/// Projected box decals — `P3`.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// **One pass over the scene target, after the opaque half and before the
/// glass.** Each view's decals are cut into batches the stage can hold —
/// sixteen decals and four pictures — and each batch is two fullscreen draws,
/// scissored to the screen rectangle its boxes cover: the factor that swaps
/// the albedo under the light the surface was lit by, multiplied in, and the
/// term an unlit surface and an emissive decal add. `decal.frag` says why it
/// takes two.
///
/// **Order is kept within a batch and approximated across two.** Inside one
/// draw the stage stacks its decals in order and swaps the albedo once, which
/// is exact. A second batch swaps from the surface's albedo again rather than
/// from the one the first left, so where a decal of the second lies over one
/// of the first, the light under the first is read through the surface's
/// colour rather than the first decal's. Seventeen overlapping decals, or a
/// fifth picture, are where that starts.
part of 'renderer.dart';

/// One draw's decals and the pictures they read.
final class _DecalBatch {
  /// Decals per draw, as `kMaxDecals` in `decal.frag` holds them.
  static const int maxDecals = 16;

  /// Pictures per draw, the stage's four `decal_texture_` slots.
  static const int maxSlots = 4;

  final List<DecalNode> decals = <DecalNode>[];
  final List<TextureHandle> slots = <TextureHandle>[];

  /// The screen rectangle the boxes cover, in pixels from the top left.
  int left = 1 << 30;
  int top = 1 << 30;
  int right = -1;
  int bottom = -1;

  /// Whether [decal] fits: a free place, and its picture already bound or a
  /// free slot for it.
  bool admits(DecalNode decal) {
    if (decals.length >= maxDecals) return false;
    final texture = decal.texture;
    return texture == null ||
        slots.contains(texture) ||
        slots.length < maxSlots;
  }

  /// The slot [texture] is read through, binding it if it is new; minus one
  /// for none.
  int slotOf(TextureHandle? texture) {
    if (texture == null) return -1;
    final at = slots.indexOf(texture);
    if (at >= 0) return at;
    slots.add(texture);
    return slots.length - 1;
  }

  void cover(ScreenRect rect) {
    left = math.min(left, rect.x);
    top = math.min(top, rect.y);
    right = math.max(right, rect.x + rect.width);
    bottom = math.max(bottom, rect.y + rect.height);
  }

  ScreenRect get covered =>
      ScreenRect(x: left, y: top, width: right - left, height: bottom - top);
}

extension _DecalPass on Renderer {
  /// Multiplies the target by what the stage writes, leaving alpha alone.
  static const BlendState _multiply = BlendState(
    sourceColorFactor: BlendFactor.zero,
    destinationColorFactor: BlendFactor.sourceColor,
    sourceAlphaFactor: BlendFactor.zero,
    destinationAlphaFactor: BlendFactor.one,
  );

  /// Adds what the stage writes, leaving alpha alone.
  static const BlendState _add = BlendState(
    sourceColorFactor: BlendFactor.one,
    destinationColorFactor: BlendFactor.one,
    sourceAlphaFactor: BlendFactor.zero,
    destinationAlphaFactor: BlendFactor.one,
  );

  /// Trilinear and clamped: a decal's picture is minified as a material's
  /// is, and its edge must not wrap the opposite edge in.
  static const SamplerOptions _pictureSampler = SamplerOptions(
    minFilter: MinMagFilter.linear,
    magFilter: MinMagFilter.linear,
    mipFilter: MipFilter.linear,
  );

  /// The decals [views] can see, painted into [target] in order.
  void _encodeDecals({
    required TextureHandle target,
    required TextureHandle surface,
    required TextureHandle albedo,
    required List<DecalNode> decals,
    required List<RenderView> views,
    required FramePassState passState,
  }) {
    // Higher order over lower, attachment order between equals: a stable
    // sort, which `List.sort` does not promise, so the index breaks the tie.
    final visible =
        <(int, DecalNode)>[
          for (var i = 0; i < decals.length; i++)
            if (decals[i].visibleInHierarchy) (i, decals[i]),
        ]..sort((a, b) {
          final byOrder = a.$2.order.compareTo(b.$2.order);
          return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
        });
    if (visible.isEmpty) return;

    final width = target.width;
    final height = target.height;
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: target, loadAction: LoadAction.load),
        ],
      ),
    );
    pass
      ..bindPipeline(
        _fullscreenPipelines[decalShader] ??= device.createPipeline(
          fullscreenVertexShader,
          decalShader,
        ),
      )
      ..bindVertexBuffer(_fullscreenTriangle, 3)
      ..bindIndexBuffer(_identityIndices(3), IndexType.int32, 3)
      ..bindTexture(
        decalShader,
        'surface_texture',
        surface,
        sampler: SamplerOptions.nearestClamp,
      )
      ..bindTexture(
        decalShader,
        'albedo_texture',
        albedo,
        sampler: SamplerOptions.nearestClamp,
      );
    passState.invalidatePipeline();

    final info = _decalInfo;
    info.params
      ..[1] = 1.0 / width
      ..[2] = 1.0 / height;
    final full = ScreenRect(width: width, height: height);
    for (final view in views) {
      final rect = Renderer._viewportPixels(
        view.viewportFraction,
        width,
        height,
      );
      final aspect = rect.width / rect.height;
      // Unadjusted for the depth range, for the reason `_encodeReflections`
      // gives: the stage unprojects both ends of a pixel's ray at clip depths
      // nought and one. Adjusted for the framebuffer origin, so the texture
      // coordinates it derives land on the rows the buffer was written in.
      final viewProjection = view.camera.viewProjection(aspect);
      final inverse = vm.Matrix4.copy(
        toFramebufferOrigin(viewProjection, device.framebufferOrigin),
      )..invert();
      info.inverseViewProjection.setAll(0, inverse.storage);
      final eye = view.camera.readWorldPosition();
      final forward = vm.Vector3.zero();
      view.camera.readForward(forward);
      info.camera
        ..[0] = eye.x
        ..[1] = eye.y
        ..[2] = eye.z;
      info.forward
        ..[0] = forward.x
        ..[1] = forward.y
        ..[2] = forward.z;
      info.view
        ..[0] = rect.x / width
        ..[1] = rect.y / height
        ..[2] = rect.width / width
        ..[3] = rect.height / height;

      for (final batch in _decalBatches(visible, viewProjection, rect)) {
        _fillDecalBatch(batch);
        for (var i = 0; i < _DecalBatch.maxSlots; i++) {
          pass.bindTexture(
            decalShader,
            'decal_texture_$i',
            i < batch.slots.length ? batch.slots[i] : fallbackAlbedo,
            sampler: _pictureSampler,
          );
        }
        final scissor = batch.covered;
        for (final term in const <double>[0.0, 1.0]) {
          info.params[3] = term;
          pass
            ..setState(
              Renderer._kFullscreenState.copyWith(
                viewport: full,
                scissor: scissor,
                blend: term == 0.0 ? _multiply : _add,
              ),
            )
            ..bindBlock(decalShader, info)
            ..draw();
          _frameCounters?.drawCalls++;
        }
      }
    }
    pass.submit();
  }

  /// [visible]'s decals cut into draws, leaving out every one whose box the
  /// view does not see.
  List<_DecalBatch> _decalBatches(
    List<(int, DecalNode)> visible,
    vm.Matrix4 viewProjection,
    ScreenRect view,
  ) {
    final batches = <_DecalBatch>[];
    for (final (_, decal) in visible) {
      final covers = _decalCover(decal, viewProjection, view);
      if (covers == null) continue;
      if (batches.isEmpty || !batches.last.admits(decal)) {
        batches.add(_DecalBatch());
      }
      batches.last
        ..decals.add(decal)
        ..slotOf(decal.texture)
        ..cover(covers);
    }
    return batches;
  }

  /// The pixels of [view] that [decal]'s box can reach, or null for none.
  ///
  /// The eight corners projected and their bounds taken, a pixel wider on
  /// each side for the rounding. A corner behind the eye has no place on the
  /// screen, and then the box may reach anywhere in the view.
  ScreenRect? _decalCover(
    DecalNode decal,
    vm.Matrix4 viewProjection,
    ScreenRect view,
  ) {
    final toClip = vm.Matrix4.copy(viewProjection)..multiply(decal.worldMatrix);
    final corners = <vm.Vector4>[
      for (var corner = 0; corner < 8; corner++)
        toClip.transform(
          vm.Vector4(
            (corner & 1) == 0 ? -0.5 : 0.5,
            (corner & 2) == 0 ? -0.5 : 0.5,
            (corner & 4) == 0 ? -0.5 : 0.5,
            1.0,
          ),
        ),
    ];
    if (corners.any((clip) => clip.w <= 1e-6)) return view;
    final xs = corners.map((clip) => clip.x / clip.w);
    final ys = corners.map((clip) => clip.y / clip.w);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final left = math.max(
      view.x,
      (view.x + (minX * 0.5 + 0.5) * view.width).floor() - 1,
    );
    final right = math.min(
      view.x + view.width,
      (view.x + (maxX * 0.5 + 0.5) * view.width).ceil() + 1,
    );
    final top = math.max(
      view.y,
      (view.y + (0.5 - maxY * 0.5) * view.height).floor() - 1,
    );
    final bottom = math.min(
      view.y + view.height,
      (view.y + (0.5 - minY * 0.5) * view.height).ceil() + 1,
    );
    if (right <= left || bottom <= top) return null;
    return ScreenRect(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  /// [batch] written into the stage's block.
  void _fillDecalBatch(_DecalBatch batch) {
    final info = _decalInfo;
    info.params[0] = batch.decals.length.toDouble();
    for (var i = 0; i < _DecalBatch.maxSlots; i++) {
      final texture = i < batch.slots.length ? batch.slots[i] : null;
      info.slots
        ..[i * 4] = (texture?.width ?? 1).toDouble()
        ..[i * 4 + 1] = (texture?.height ?? 1).toDouble();
    }
    for (var i = 0; i < batch.decals.length; i++) {
      final decal = batch.decals[i];
      // The rows of the world-to-box matrix, out of column-major storage.
      final m = decal.inverseWorldMatrix.storage;
      for (final (row, into) in <(int, Float32List)>[
        (0, info.axisX),
        (1, info.axisY),
        (2, info.axisZ),
      ]) {
        into
          ..[i * 4] = m[row]
          ..[i * 4 + 1] = m[4 + row]
          ..[i * 4 + 2] = m[8 + row]
          ..[i * 4 + 3] = m[12 + row];
      }
      final region = decal.region;
      info.region
        ..[i * 4] = region.x
        ..[i * 4 + 1] = region.y
        ..[i * 4 + 2] = region.z
        ..[i * 4 + 3] = region.w;
      // Linear here rather than in the stage: one conversion, in doubles,
      // that every backend then reads as the same float.
      final tint = Renderer._srgbToLinear(decal.color);
      info.color
        ..[i * 4] = tint.x
        ..[i * 4 + 1] = tint.y
        ..[i * 4 + 2] = tint.z
        ..[i * 4 + 3] = tint.w.clamp(0.0, 1.0);
      final limit = decal.angleLimit.clamp(0.0, math.pi);
      final gone = math.cos(limit);
      final whole = math.cos(math.max(limit - decal.angleFade, 0.0));
      info.fade
        ..[i * 4] = batch.slotOf(decal.texture).toDouble()
        ..[i * 4 + 1] = gone
        ..[i * 4 + 2] = math.max(whole - gone, 1e-4)
        ..[i * 4 + 3] = decal.depthFade.clamp(0.0, 1.0);
      final emissive = decal.emissive;
      info.emissive
        ..[i * 4] = emissive.x
        ..[i * 4 + 1] = emissive.y
        ..[i * 4 + 2] = emissive.z;
    }
  }
}
