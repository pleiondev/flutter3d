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

/// One draw's decals and the pictures they read, through one stage.
final class _DecalBatch {
  _DecalBatch(this.stage, {required this.maxDecals, required this.maxSlots});

  /// Pictures per draw, the stage's four `decal_texture_` slots.
  static int get slotCount => DecalSettings.maxPicturesPerDraw;

  /// The stage the draw paints with: a decal's own, or null for the
  /// engine's `Decal`.
  final LightingModel? stage;

  /// Decals per draw, as `DecalSettings.decalsPerDraw` asks, within what
  /// `kMaxDecals` in `decal.frag` holds.
  final int maxDecals;

  /// Pictures per draw, as `DecalSettings.picturesPerDraw` asks, within the
  /// stage's [slotCount].
  final int maxSlots;

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
    if (!identical(decal.lighting, stage)) return false;
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
  static const SamplerDescriptor _pictureSampler = SamplerDescriptor(
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
    DecalSettings settings = const DecalSettings(),
  }) {
    final visible = _decalsInOrder(decals);
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
    passState.invalidatePipeline();
    // The stage bound last, so a run of draws through one stage binds its
    // pipeline, its triangle and its two buffers once. The triangle after the
    // pipeline: binding a pipeline clears what was bound before it, and on
    // the software device a triangle bound first was a draw of nothing.
    ShaderHandle? bound;
    void useStage(ShaderHandle stage) {
      if (identical(stage, bound)) return;
      bound = stage;
      pass
        ..bindPipeline(
          _fullscreenPipelines[stage] ??= device.createPipeline(
            _fullscreenVertexShader,
            stage,
          ),
        )
        ..bindVertexBuffer(_fullscreenTriangle, 3)
        ..bindIndexBuffer(_identityIndices(3), IndexType.int32, 3)
        ..bindTexture(
          stage,
          'surface_texture',
          surface,
          sampler: SamplerDescriptor.nearestClamp,
        )
        ..bindTexture(
          stage,
          'albedo_texture',
          albedo,
          sampler: SamplerDescriptor.nearestClamp,
        );
    }

    final perDraw = settings.decalsPerDraw.clamp(
      1,
      DecalSettings.maxDecalsPerDraw,
    );
    final pictures = settings.picturesPerDraw.clamp(
      1,
      DecalSettings.maxPicturesPerDraw,
    );

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
      final viewProjection = _finiteViewProjection(view.camera, aspect);
      final inverse = vm.Matrix4.copy(
        toFramebufferOrigin(viewProjection, device.framebufferOrigin),
      )..invert();
      info.inverseViewProjection.setAll(0, inverse.storage);
      final eye = view.camera.readViewOrigin();
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

      for (final batch in _decalBatches(
        visible,
        viewProjection,
        rect,
        perDraw: perDraw,
        pictures: pictures,
      )) {
        final stage = switch (batch.stage) {
          null => _decalShader,
          final model => _fragmentShaderFor(model),
        };
        useStage(stage);
        _fillDecalBatch(batch);
        for (var i = 0; i < _DecalBatch.slotCount; i++) {
          pass.bindTexture(
            stage,
            'decal_texture_$i',
            i < batch.slots.length ? batch.slots[i] : fallbackAlbedo,
            sampler: _pictureSampler,
          );
        }
        // **From the top left, and not adjusted for the framebuffer origin,
        // unlike the matrix above.** A rectangle is the engine's own
        // vocabulary and every backend takes it from the top: WebGL2's
        // encoder turns it upside down itself in `setScissor`, as it does for
        // the scene pass's view rectangles, which are handed over the same
        // way. The matrix is different because the stage reads texture rows,
        // which no encoder translates. Flipping here as well was tried: the
        // WebGL2 `decal-floor` golden differs by 602 pixels, and
        // `decal_test.dart` keeps a decal in the top rows for the same reason.
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
            ..bindBlock(stage, info)
            ..draw();
          _frameCounters?.drawCalls++;
        }
      }
    }
    pass.submit();
  }

  /// The visible decals of [decals], higher order over lower and attachment
  /// order between equals, in [Renderer._decalOrder].
  ///
  /// **Sorted as packed integers**: each decal's order and its index in one
  /// key, `(order + 2³¹) × 2²⁰ + index`, so the sort compares numbers rather
  /// than calling back into a comparator over records it allocated, and the
  /// index both breaks ties (a stable sort, which `List.sort` does not
  /// promise) and names the decal afterwards. Multiplied and added rather
  /// than shifted and or-ed, for the reason `RenderList`'s keys are: on the
  /// web an integer is a double and bitwise operators are 32-bit. The key
  /// fits 52 bits, inside what a double holds exactly. An order beyond ±2³¹
  /// sorts as the bound, and a scene of more than 2²⁰ decals paints the rest
  /// in no particular place.
  List<DecalNode> _decalsInOrder(List<DecalNode> decals) {
    const span = 1048576; // 2^20 decals
    const bias = 2147483648; // 2^31
    final keys = _decalKeys..clear();
    for (var i = 0; i < decals.length && i < span; i++) {
      if (!decals[i].isVisibleInHierarchy) continue;
      final order = decals[i].order.clamp(-bias, bias - 1);
      keys.add((order + bias) * span + i);
    }
    keys.sort();
    final ordered = _decalOrder..clear();
    for (final key in keys) {
      ordered.add(decals[key % span]);
    }
    return ordered;
  }

  /// [visible]'s decals cut into draws, leaving out every one whose box the
  /// view does not see.
  ///
  /// A draw holds [perDraw] decals and [pictures] pictures at most, all
  /// painted through one stage: a decal of another stage starts the next.
  List<_DecalBatch> _decalBatches(
    List<DecalNode> visible,
    vm.Matrix4 viewProjection,
    ScreenRect view, {
    required int perDraw,
    required int pictures,
  }) {
    final batches = <_DecalBatch>[];
    for (final decal in visible) {
      final covers = _decalCover(decal, viewProjection, view);
      if (covers == null) continue;
      if (batches.isEmpty || !batches.last.admits(decal)) {
        batches.add(
          _DecalBatch(decal.lighting, maxDecals: perDraw, maxSlots: pictures),
        );
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
    for (var i = 0; i < _DecalBatch.slotCount; i++) {
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
      // Linear, as the stage reads it: the colour is linear already.
      final tint = decal.color;
      info.color
        ..[i * 4] = tint.r
        ..[i * 4 + 1] = tint.g
        ..[i * 4 + 2] = tint.b
        ..[i * 4 + 3] = tint.a.clamp(0.0, 1.0);
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
        ..[i * 4] = emissive.r
        ..[i * 4 + 1] = emissive.g
        ..[i * 4 + 2] = emissive.b;
    }
  }
}
