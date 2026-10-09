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
  /// **No `setDepthCompare` the ordinary way round.** The triangle goes at
  /// 0.999999, which passes the pass's own `less` against a buffer cleared
  /// to 1.0 and fails against anything already drawn. So the tracker is
  /// untouched and stays `less`, and a frame with no sky in it is
  /// byte-for-byte what it was.
  ///
  /// **[reversed], the far plane is nought** — `A2.8` — and nothing strictly
  /// beyond it passes a `greater` test against a buffer cleared to nought.
  /// So the triangle goes at nought itself and is tested `lessEqual`, which
  /// the reversed pass asks as `greaterEqual`: equal to the clear where
  /// nothing was drawn, and behind everything that was. Not a hair in front
  /// of nought, as the ordinary sky is a hair in front of one: under an
  /// infinite far plane a mountain at a million near planes is a hair in
  /// front of nought itself, and no fixed hair is small enough.
  ///
  /// [viewProjection] is the view's matrix with nothing done to its depth —
  /// the rays are all the sky reads of it.
  void _encodeSky({
    required PassEncoder pass,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required FramePassState state,
    bool reversed = false,
  }) {
    final sky = settings.sky;
    if (!sky.enabled) return;

    // Three fragment stages: the ray is the same in each, and which one runs
    // is decided by whether there is a cube to sample, and failing that,
    // whether there is air to scatter through. A cube wins, as
    // `SkySettings.physical` says. The air is the resolved one: a sky nobody
    // coloured is physical without naming a `PhysicalSky`.
    final cubemap = sky.cubemap;
    final textured = cubemap != null;
    final air = textured ? null : sky.resolvedPhysical;
    final fragmentName = textured
        ? 'SkyCube'
        : (air != null ? 'SkyPhysical' : 'Sky');

    // A vertex stage per fragment stage: the layout each draw carries is
    // derived from the stage's own declarations, and each sky wants
    // different things on its vertices. See `sky.vert`.
    //
    // Through the renderer's own library rather than `device.shaders`, like
    // every other stage it resolves by name: a bundle handed in as
    // `materials:` wins any name it shares with the engine's, and a sky it
    // replaced — or reloaded, see `relinkShaders` — was otherwise never seen.
    final vertexName = textured
        ? 'SkyCubeVertex'
        : (air != null ? 'SkyPhysicalVertex' : 'SkyVertex');
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
    pass.setDepthWrite(enabled: false);
    if (reversed && state.depthCompare != CompareFunction.lessEqual) {
      pass.setDepthCompare(CompareFunction.lessEqual);
      state.depthCompare = CompareFunction.lessEqual;
    }
    final depth = reversed ? 0.0 : Renderer._kSkyDepth;

    final inverse = vm.Matrix4.copy(viewProjection)..invert();
    _skyOrthoLens = isOrthographic(viewProjection)
        ? _orthoSkyLens(inverse)
        : null;

    pass.bindPipeline(
      textured
          ? (_skyCubePipeline ??= device.createPipeline(vertex, fragment))
          : air != null
          ? (_skyPhysicalPipeline ??= device.createPipeline(vertex, fragment))
          : (_skyPipeline ??= device.createPipeline(vertex, fragment)),
    );
    // The tracker described a pipeline this just replaced; the next mesh has to
    // bind its own rather than trust a stale answer.
    state.invalidatePipeline();

    if (textured) {
      pass.bindVertexData(
        _skyVertexBytes(inverse, sky, textured: true, depth: depth),
        3,
      );
      pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
      pass.bindTexture(
        fragment,
        'sky_texture',
        cubemap,
        sampler: SamplerDescriptor.linearClamp,
      );
      pass.draw();
      state.drawCalls++;
      return;
    }

    pass.bindVertexData(
      air != null
          ? _skyPhysicalVertexBytes(inverse, sky, air, depth: depth)
          : _skyVertexBytes(inverse, sky, textured: false, depth: depth),
      3,
    );
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
    required double depth,
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
      data[at++] = depth;

      _skyCornerRay(inverse, x, y, _skyRay);
      data[at++] = _skyRay.x;
      data[at++] = _skyRay.y;
      data[at++] = _skyRay.z;

      if (textured) {
        data[at++] = tint.r;
        data[at++] = tint.g;
        data[at++] = tint.b;
        data[at++] = 1.0;
        continue;
      }

      data[at++] = zenith.r;
      data[at++] = zenith.g;
      data[at++] = zenith.b;
      data[at++] = 0.0;

      data[at++] = horizon.r;
      data[at++] = horizon.g;
      data[at++] = horizon.b;
      data[at++] = 0.0;

      data[at++] = nadir.r;
      data[at++] = nadir.g;
      data[at++] = nadir.b;
      data[at++] = 0.0;

      data[at++] = toSun.x;
      data[at++] = toSun.y;
      data[at++] = toSun.z;
      data[at++] = sky.glowExponent;

      data[at++] = glow.r;
      data[at++] = glow.g;
      data[at++] = glow.b;
      data[at++] = sky.glowStrength;

      // The disc's inner cosine, then **how much softer its edge is** rather
      // than the outer cosine itself. Both are within a hair of one — a disc a
      // third of a degree across has cosines differing by about two parts in a
      // hundred thousand — and a varying carries them through an interpolation
      // in single precision, which rounds the two together and leaves the
      // shader's `inner > outer` guard false. A sun that never draws.
      data[at++] = sky.discInnerCosine;
      data[at++] = sky.discInnerCosine - sky.discOuterCosine;
      data[at++] = luxToEngine(sky.sunIntensity);
      data[at++] = 0.0;
    }

    // Element indices, not bytes: the source is a Float32List.
    return ByteData.sublistView(data, 0, 3 * stride);
  }

  /// The three corners of the physical sky's triangle — `P5`.
  ///
  /// The gradient's stride and the gradient's buffer: six vec4s after the ray
  /// in both, and `sky_physical.vert` lists what each holds. Lengths go over
  /// in kilometres, converted by `PhysicalSkyKilometres` so the Dart model
  /// marches with the very numbers the shader does.
  ByteData _skyPhysicalVertexBytes(
    vm.Matrix4 inverse,
    SkySettings sky,
    PhysicalSky air, {
    required double depth,
  }) {
    final data = _skyVertexData;
    const corners = <double>[-1.0, -1.0, 3.0, -1.0, -1.0, 3.0];
    const stride = Renderer._kSkyVertexFloats;
    final k = PhysicalSkyKilometres(air);
    final toSun = sky.resolvedDirectionToSun.normalized();

    for (var i = 0; i < 3; i++) {
      final x = corners[i * 2];
      final y = corners[i * 2 + 1];
      var at = i * stride;

      data[at++] = x;
      data[at++] = y;
      data[at++] = depth;

      _skyCornerRay(inverse, x, y, _skyRay);
      data[at++] = _skyRay.x;
      data[at++] = _skyRay.y;
      data[at++] = _skyRay.z;

      data[at++] = k.rayleigh.x;
      data[at++] = k.rayleigh.y;
      data[at++] = k.rayleigh.z;
      data[at++] = k.rayleighHeight;

      data[at++] = k.mie;
      data[at++] = k.mieExtinction;
      data[at++] = k.mieHeight;
      data[at++] = air.resolvedAnisotropy;

      data[at++] = toSun.x;
      data[at++] = toSun.y;
      data[at++] = toSun.z;
      // On the luminance scale, not the illuminance one: the shader multiplies
      // it by per-metre coefficients and per-steradian phase functions, which
      // turn lux into nits. `PhysicalSky._sun` says the same.
      data[at++] = nitsToEngine(air.sunIlluminance);

      data[at++] = k.planet;
      data[at++] = k.top;
      data[at++] = k.eye;
      data[at++] = air.groundAlbedo;

      data[at++] = air.starBrightness;
      data[at++] = air.starDensity;
      data[at++] = air.starCells.toDouble();
      data[at++] = air.ozone;

      // The disc as the gradient sends it, inner cosine and the width of the
      // edge — see `_skyVertexBytes` for why not the outer cosine.
      data[at++] = sky.discInnerCosine;
      data[at++] = sky.discInnerCosine - sky.discOuterCosine;
      data[at++] = luxToEngine(sky.sunIntensity);
      data[at++] = 0.0;
    }

    return ByteData.sublistView(data, 0, 3 * stride);
  }

  /// The world-space view ray at one clip-space corner.
  ///
  /// Two points on the same eye ray, subtracted. The depths are 0.5 and 1.0
  /// because both are valid in **either** depth convention — this engine runs
  /// zero-to-one on Impeller and on the software rasteriser and minus-one-to-one
  /// on WebGL, and the difference of two points on one ray is the same direction
  /// wherever the two points sit.
  ///
  /// **Except where the far plane is at infinity**, which is where depth 1.0
  /// lands with w nought — a point at infinity, and a division by it. There
  /// the second point is taken at 0.75 instead, which is a finite distance
  /// under every convention [inverse] can be in; any finite camera keeps the
  /// 1.0 it always had, so its sky is the sky it was.
  ///
  /// **Through an orthographic lens every corner's ray is the view axis**, so
  /// the sky would be one colour, a cube map one texel, and the sun's disc the
  /// whole frame or nothing — `P7`. The sky is then seen as a perspective
  /// camera of [_kOrthoSkyFieldOfView] standing where the orthographic one
  /// does would see it: an orthographic view is a way of drawing the near
  /// world, not a claim that the sky is infinitely far in one direction only.
  void _skyCornerRay(vm.Matrix4 inverse, double x, double y, vm.Vector3 out) {
    final lens = _skyOrthoLens;
    if (lens != null) {
      final spread = math.tan(_kOrthoSkyFieldOfView / 2.0);
      out
        ..setFrom(lens.forward)
        ..addScaled(lens.right, x * spread * lens.aspect)
        ..addScaled(lens.up, y * spread);
      return;
    }
    final near = inverse.transform(vm.Vector4(x, y, 0.5, 1.0));
    var far = inverse.transform(vm.Vector4(x, y, 1.0, 1.0));
    if (far.w.abs() < 1e-12) {
      far = inverse.transform(vm.Vector4(x, y, 0.75, 1.0));
    }
    out.setValues(
      far.x / far.w - near.x / near.w,
      far.y / far.w - near.y / near.w,
      far.z / far.w - near.z / near.w,
    );
  }

  /// The view axis and the world directions of the frame's right and top
  /// edges, out of an orthographic [inverse] view-projection, and the frame's
  /// aspect — the lens [_skyCornerRay] sees the sky through.
  ///
  /// Read off the matrix at the frame's middle and edges rather than off the
  /// camera, so whatever the backend did to its y — the top edge is the one
  /// clip y of one points at on every backend — the sky turns with it.
  static ({vm.Vector3 forward, vm.Vector3 right, vm.Vector3 up, double aspect})
  _orthoSkyLens(vm.Matrix4 inverse) {
    vm.Vector3 at(double x, double y, double z) {
      final p = inverse.transform(vm.Vector4(x, y, z, 1.0));
      return vm.Vector3(p.x / p.w, p.y / p.w, p.z / p.w);
    }

    final center = at(0.0, 0.0, 0.5);
    final forward = (at(0.0, 0.0, 1.0) - center)..normalize();
    final right = at(1.0, 0.0, 0.5) - center;
    final up = at(0.0, 1.0, 0.5) - center;
    final halfHeight = up.length;
    final aspect = halfHeight > 0.0 ? right.length / halfHeight : 1.0;
    return (
      forward: forward,
      right: right..normalize(),
      up: up..normalize(),
      aspect: aspect,
    );
  }
}

/// The vertical field of view the sky is seen with through an orthographic
/// lens, in radians: sixty degrees, a camera's ordinary width — `P7`.
const double _kOrthoSkyFieldOfView = math.pi / 3.0;
