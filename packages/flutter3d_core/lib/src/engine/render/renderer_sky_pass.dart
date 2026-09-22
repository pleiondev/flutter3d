/// The sky, which is one triangle and a great deal of arithmetic.
///
/// A `part` of `renderer.dart` for the reason written at the top of
/// `renderer_shadow_pass.dart`: these are `Renderer`'s methods and they read
/// `Renderer`'s private fields, and a file of their own would mean widening
/// those fields for the sake of a directory listing.
part of 'renderer.dart';

extension _SkyPass on Renderer {
  /// Draws the sky, if the frame asked for one.
  ///
  /// Encoded into the scene pass rather than a pass of its own, and that is not
  /// a shortcut. `DepthTarget` has no load action — every pass clears depth on
  /// entry and discards it on exit — so a sky drawn upstream would have no
  /// world depth to test against, and one drawn downstream would have no depth
  /// buffer at all. With MSAA the scene's colour is a multisample texture that
  /// cannot be pre-filled either.
  ///
  /// **No `setDepthCompare`.** `sky.vert` puts the triangle at 0.999999, which
  /// passes the pass's own `less` against a buffer cleared to 1.0 and fails
  /// against anything already drawn. So the tracker is untouched and stays
  /// `less`, and a frame with no sky in it is byte-for-byte what it was.
  void _encodeSky({
    required PassEncoder pass,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required FramePassState state,
  }) {
    final sky = settings.sky;
    if (!sky.enabled) return;

    // Two fragment stages behind one vertex stage: the ray is the same either
    // way, and which one runs is decided by whether there is a cube to sample.
    final cubemap = sky.cubemap;
    final textured = cubemap != null;
    final fragmentName = textured ? 'SkyCube' : 'Sky';

    final shaders = device.shaders;
    // Two vertex stages, one per fragment stage: the layout each draw carries
    // is derived from the stage's own declarations, and the gradient and the
    // cube want different things on their vertices. See `sky.vert`.
    final vertexName = textured ? 'SkyCubeVertex' : 'SkyVertex';
    final vertex = shaders[vertexName];
    final fragment = shaders[fragmentName];
    if (vertex == null || fragment == null) {
      throw StateError(
        'RenderSettings.sky is enabled but the bundle has no "$vertexName"/'
        '"$fragmentName" entry. Rebuild the backend\'s shader bundle — for the '
        'web backend that means re-running tool/generate_shaders.dart, which '
        'nothing checks for you.',
      );
    }
    if (textured && cubemap.type != TextureType.textureCube) {
      throw StateError(
        'RenderSettings.sky.cubemap is a ${cubemap.type.name} rather than a '
        'cube. Build it with GraphicsDevice.createCubeTextureFromPixels; a 2D '
        'texture bound to a cube sampler is black on one backend and rubbish '
        'on another.',
      );
    }

    // Blending named explicitly. `_kSceneViewState` deliberately leaves it out,
    // so with an empty opaque half this pass would still be carrying whatever
    // the previous one set — and on WebGL that is global GL state.
    pass.setBlend(null);
    pass.setCullMode(CullMode.none);
    pass.setDepthWrite(false);

    final inverse = vm.Matrix4.copy(viewProjection)..invert();

    pass.bindPipeline(
      textured
          ? (_skyCubePipeline ??= device.createPipeline(vertex, fragment))
          : (_skyPipeline ??= device.createPipeline(vertex, fragment)),
    );
    // The tracker described a pipeline this just replaced; the next mesh has to
    // bind its own rather than trust a stale answer.
    state.invalidatePipeline();

    if (textured) {
      pass.bindVertexData(_skyVertexBytes(inverse, sky, textured: true), 3);
      pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
      pass.bindTexture(
        fragment,
        'sky_texture',
        cubemap,
        sampler: SamplerOptions.linearClamp,
      );
      pass.draw();
      state.drawCalls++;
      return;
    }

    pass.bindVertexData(_skyVertexBytes(inverse, sky, textured: false), 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);

    pass.draw();
    state.drawCalls++;
  }

  /// The three corners of the sky's triangle, with everything the stages need.
  ///
  /// **Everything, because a uniform block does not reach this pipeline on
  /// Impeller** — see the note at the top of `sky.vert`, which lists what was
  /// measured. A vertex attribute does, so the ray and the preset travel that
  /// way: the ray differs per corner and interpolates to the pixel's own
  /// direction, and the preset is written identically on all three, so any
  /// interpolation of it returns exactly what was written.
  ///
  /// Rebuilt every frame through the transient allocator rather than uploaded once:
  /// the rays follow the camera, and 348 bytes a frame is less than the uniform
  /// upload it replaces.
  ByteData _skyVertexBytes(
    vm.Matrix4 inverse,
    SkySettings sky, {
    required bool textured,
  }) {
    final data = _skyVertexData;
    // The clip-space corners of the full-screen triangle.
    const corners = <double>[-1.0, -1.0, 3.0, -1.0, -1.0, 3.0];
    // The stride is the stage's own, not the larger of the two: the cube's
    // vertex is nine floats and the gradient's twenty-nine, and writing the
    // second stride into the first buffer puts two of the three vertices where
    // nothing reads them.
    final stride = textured
        ? Renderer._kSkyCubeVertexFloats
        : Renderer._kSkyVertexFloats;

    final toSun = sky.resolvedDirectionToSun.normalized();
    final zenith = sky.resolvedZenith;
    final horizon = sky.resolvedHorizon;
    final nadir = sky.resolvedNadir;
    final glow = sky.resolvedSunColor;
    final tint = sky.resolvedTint;

    for (var i = 0; i < 3; i++) {
      final x = corners[i * 2];
      final y = corners[i * 2 + 1];
      var at = i * stride;

      data[at++] = x;
      data[at++] = y;

      _skyCornerRay(inverse, x, y, _skyRay);
      data[at++] = _skyRay.x;
      data[at++] = _skyRay.y;
      data[at++] = _skyRay.z;

      if (textured) {
        data[at++] = tint.x;
        data[at++] = tint.y;
        data[at++] = tint.z;
        data[at++] = 1.0;
        continue;
      }

      data[at++] = zenith.x;
      data[at++] = zenith.y;
      data[at++] = zenith.z;
      data[at++] = 0.0;

      data[at++] = horizon.x;
      data[at++] = horizon.y;
      data[at++] = horizon.z;
      data[at++] = 0.0;

      data[at++] = nadir.x;
      data[at++] = nadir.y;
      data[at++] = nadir.z;
      data[at++] = 0.0;

      data[at++] = toSun.x;
      data[at++] = toSun.y;
      data[at++] = toSun.z;
      data[at++] = sky.glowExponent;

      data[at++] = glow.x;
      data[at++] = glow.y;
      data[at++] = glow.z;
      data[at++] = sky.glowStrength;

      // The disc's inner cosine, then **how much softer its edge is** rather
      // than the outer cosine itself. Both are within a hair of one — a disc a
      // third of a degree across has cosines differing by about two parts in a
      // hundred thousand — and a varying carries them through an interpolation
      // in single precision, which rounds the two together and leaves the
      // shader's `inner > outer` guard false. A sun that never draws.
      data[at++] = sky.discInnerCosine;
      data[at++] = sky.discInnerCosine - sky.discOuterCosine;
      data[at++] = sky.sunIntensity;
      data[at++] = 0.0;
    }

    // Element indices, not bytes: the source is a Float32List.
    return ByteData.sublistView(data, 0, 3 * stride);
  }

  /// The world-space view ray at one clip-space corner.
  ///
  /// Two points on the same eye ray, subtracted. The depths are 0.5 and 1.0
  /// because both are valid in **either** depth convention — this engine runs
  /// zero-to-one on Impeller and on the software rasteriser and minus-one-to-one
  /// on WebGL, and the difference of two points on one ray is the same direction
  /// wherever the two points sit.
  static void _skyCornerRay(
    vm.Matrix4 inverse,
    double x,
    double y,
    vm.Vector3 out,
  ) {
    final near = inverse.transform(vm.Vector4(x, y, 0.5, 1.0));
    final far = inverse.transform(vm.Vector4(x, y, 1.0, 1.0));
    out.setValues(
      far.x / far.w - near.x / near.w,
      far.y / far.w - near.y / near.w,
      far.z / far.w - near.z / near.w,
    );
  }
}
