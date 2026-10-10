/// Builds and caches the pipelines and fragment shaders a frame draws with.
///
/// **A part of `renderer.dart`, not a file of its own**, for the same reason
/// `renderer_shadow_pass.dart` is: these are `Renderer`'s own methods, reading
/// and filling `Renderer`'s private caches, and widening those caches to
/// public just to reach them from an ordinary library would be a worse trade
/// than sharing this library's privacy through a `part`. The fields
/// themselves — `_pipelineCache`, `_fragmentShaders`, `targetPool` — stay
/// declared in `renderer.dart`: a `part` shares a *library's* scope, not a
/// single class body split across files, and an extension can only add
/// methods and getters, never instance state.
///
/// Only *private* methods live in this extension. `Renderer.dispose`, which
/// releases what these two caches hold, is public API a host application has
/// to be able to call — and a private extension's members are only in scope
/// inside the library that declares it, so `dispose` is a genuine member of
/// `Renderer` in `renderer.dart` instead. Learned by trying it here first: a
/// test outside this library could not see it.
part of 'renderer.dart';

/// Read by [Renderer.fallbackAlbedo] and [Renderer.fallbackNormal] after
/// [Renderer.dispose] has cleared them.
const String _kDisposedMessage =
    'Renderer.dispose() has already been called; this renderer is no '
    'longer usable.';

extension _RendererResources on Renderer {
  /// The HDR format, chosen once. Half floats rather than full: the extra
  /// range of `r32g32b32a32Float` buys nothing for light values and doubles
  /// the bandwidth of every post-processing read.
  ///
  /// Asked of the backend rather than fixed here.
  ///
  /// It was a constant, which read as a property of the engine and was a
  /// property of one backend: the format is renderable on one of them with
  /// nothing to enable, and on WebGL2 only because the device requests an
  /// extension when it makes its context. A backend that could not render to
  /// it had no way to say so, and the failure would have been an incomplete
  /// framebuffer — every draw discarded, no error, a black frame and correct
  /// counters.
  TextureFormat get hdrFormat => device.hdrColorFormat;

  /// [model]'s fragment stage — its opaque variant when [opaque] is, which
  /// the caller has asked [_opaqueStageFor] is there.
  ShaderHandle _fragmentShaderFor(LightingModel model, {bool opaque = false}) {
    if (opaque) return _opaqueStageFor(model)!;
    return _fragmentShaders.putIfAbsent(model.shaderName, () {
      final shader = shaders[model.shaderName];
      if (shader == null) {
        throw StateError(
          'The bundle has no "${model.shaderName}" fragment shader. '
          'Rebuild it with tool/build_shaders.sh.',
        );
      }
      return shader;
    });
  }

  /// [model]'s variant with no reachable `discard` — `A1.2` — or null when
  /// no shader library the renderer was given has one.
  ///
  /// By name, `Pbr` and `PbrOpaque`, as a skinned material vertex stage is
  /// found: the engine's six lit models ship one, and a model from anywhere
  /// else that ships one too is drawn through it on the same terms.
  ///
  /// **Never the backend's variant of a stage somebody replaced.** An
  /// application that hands the renderer its own `Unlit` and no
  /// `UnlitOpaque` means its stage to draw: paired with the backend's opaque
  /// variant, every opaque draw ran the engine's shader and the
  /// application's never ran at all. A replaced stage with no variant of its
  /// own draws through the plain stage, as a model without one does.
  ShaderHandle? _opaqueStageFor(
    LightingModel model,
  ) => _opaqueStages.putIfAbsent(model.shaderName, () {
    final name = model.shaderName;
    final opaque = shaders['${name}Opaque'];
    if (opaque == null) return null;
    final ownPlain = device.shaders[name];
    final replaced = ownPlain != null && !identical(shaders[name], ownPlain);
    final backendsVariant = identical(opaque, device.shaders['${name}Opaque']);
    return replaced && backendsVariant ? null : opaque;
  });

  PipelineHandle _pipelineFor(
    LightingModel model, {
    required bool skinned,
    bool instanced = false,
    bool lightmapped = false,
    bool opaque = false,
  }) {
    assert(!(skinned && instanced), 'a skinned batch is not a thing here');
    assert(
      !(lightmapped && (skinned || instanced)),
      'a lightmap is baked onto a level, which is neither skinned nor batched',
    );
    // **The vertex stage is part of the key — `gfx-75n`.** It used to be the
    // fragment stage's name alone, which was complete while the vertex side was
    // fixed. Two materials that light the same way and displace differently
    // are two pipelines, and keying on the fragment name would have handed the
    // second one the first one's.
    final vertex = model.vertexShaderName;
    final name = vertex == null
        ? model.shaderName
        : '$vertex+${model.shaderName}';
    final staged = opaque ? '$name/opaque' : name;
    final key = instanced
        ? 'instanced/$staged'
        : skinned
        ? 'skinned/$staged'
        : lightmapped
        ? 'lightmapped/$staged'
        : staged;
    // Timed, and over `FramePacing.stallThreshold` reported with what asked
    // for it — `A1.7`. The stages are resolved inside the timing: finding
    // and linking a material's stage is part of what the frame waits for.
    return _pipelineCache.putIfAbsent(
      key,
      () => _timedBuild(
        () => instanced
            ? device.createPipeline(
                _instancedVertexShader,
                _fragmentShaderFor(model, opaque: opaque),
                layout: _kInstancedLayout,
              )
            : device.createPipeline(
                _vertexShaderFor(
                  model,
                  skinned: skinned,
                  lightmapped: lightmapped,
                ),
                _fragmentShaderFor(model, opaque: opaque),
              ),
        material: model.shaderName,
        vertexShader: vertex,
        geometry: instanced
            ? PipelineGeometry.instanced
            : skinned
            ? PipelineGeometry.skinned
            : lightmapped
            ? PipelineGeometry.lightmapped
            : PipelineGeometry.plain,
        opaque: opaque,
      ),
    );
  }

  /// The vertex stage this draw goes through — `gfx-75n`.
  ///
  /// The engine's own unless the material brought one, which is the seam this
  /// row exists for. Instanced and lightmapped draws keep the engine's: both
  /// read a second buffer whose layout the engine declares, and a stage
  /// supplied from outside cannot be held to a layout it has never seen.
  ShaderHandle _vertexShaderFor(
    LightingModel model, {
    required bool skinned,
    required bool lightmapped,
  }) {
    final supplied = model.vertexShaderName;
    if (supplied == null || lightmapped) {
      return skinned
          ? _skinnedVertexShader
          : lightmapped
          ? _lightmappedVertexShader
          : _vertexShader;
    }

    // One name, two stages: the skinned entry point is the given name with
    // `Skinned` on the end, the same relationship `MeshVertex` and
    // `MeshSkinnedVertex` already have. A material drawn only on props need
    // never ship the second, and one that is drawn on a character and did not
    // is told which name was wanted rather than silently drawing the bind pose.
    final wanted = skinned ? '${supplied}Skinned' : supplied;
    return _materialVertexShaders.putIfAbsent(wanted, () {
      final shader = shaders[wanted];
      if (shader == null) {
        throw StateError(
          'Material "${model.label}" asks for the vertex stage "$wanted", '
          'which no shader library the renderer was given answers to. '
          '${skinned ? 'This is the skinned half of "$supplied": a material '
                    'drawn on a skinned mesh needs both. ' : ''}'
          'Pass it to Renderer.create as `materials:`, or rebuild the '
          "backend's bundle with it in.",
        );
      }
      return shader;
    });
  }
}

/// The two slots an instanced draw binds: the standard vertex in slot 0, one
/// per vertex, and the placement in slot 1, one per instance.
///
/// Declared rather than read off the shader, because a shader's `in`
/// declarations say what the attributes are and not which buffer each comes
/// from; the split is what this spec exists to state, and `InstancedMeshNode`
/// says what slot 1 holds.
final VertexLayoutDescriptor _kInstancedLayout = VertexLayoutDescriptor(
  <BufferLayout>[
    BufferLayout(
      strideInBytes: VertexLayout.standard.strideInBytes,
      attributes: <InputAttribute>[
        for (final (name, format) in <(String, VertexFormat)>[
          ('position', VertexFormat.float32x3),
          ('normal', VertexFormat.float32x3),
          ('texcoord', VertexFormat.float32x2),
          ('tangent', VertexFormat.float32x4),
          ('color', VertexFormat.float32x4),
        ])
          InputAttribute(
            name: name,
            format: format,
            offsetInBytes: VertexLayout.standard.floatOffsetOf(name) * 4,
          ),
      ],
    ),
    const BufferLayout(
      strideInBytes: InstancedMeshNode.strideInBytes,
      stepMode: VertexStepMode.instance,
      attributes: <InputAttribute>[
        InputAttribute(name: 'i_row0', format: VertexFormat.float32x4),
        InputAttribute(
          name: 'i_row1',
          format: VertexFormat.float32x4,
          offsetInBytes: 16,
        ),
        InputAttribute(
          name: 'i_row2',
          format: VertexFormat.float32x4,
          offsetInBytes: 32,
        ),
        InputAttribute(
          name: 'i_color',
          format: VertexFormat.float32x4,
          offsetInBytes: 48,
        ),
        // `P8`: the instance's own four numbers, a material's `instance`.
        InputAttribute(
          name: 'i_data',
          format: VertexFormat.float32x4,
          offsetInBytes: 64,
        ),
      ],
    ),
  ],
);

// `Renderer.dispose` is not declared here. An extension's members are only
// in scope where the extension itself is — and this one is private, visible
// only inside this library — so a public method a host application must be
// able to call has to be a genuine member of the class, declared where the
// class is. Find it in `renderer.dart`, beside the fallback-texture getters
// it clears.
