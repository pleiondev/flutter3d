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

  ShaderHandle _fragmentShaderFor(LightingModel model) {
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

  PipelineHandle _pipelineFor(
    LightingModel model, {
    required bool skinned,
    bool instanced = false,
    bool lightmapped = false,
  }) {
    assert(!(skinned && instanced), 'a skinned batch is not a thing here');
    assert(
      !(lightmapped && (skinned || instanced)),
      'a lightmap is baked onto a level, which is neither skinned nor batched',
    );
    final key = instanced
        ? 'instanced/${model.shaderName}'
        : skinned
        ? 'skinned/${model.shaderName}'
        : lightmapped
        ? 'lightmapped/${model.shaderName}'
        : model.shaderName;
    return _pipelineCache.putIfAbsent(
      key,
      () => instanced
          ? device.createPipeline(
              instancedVertexShader,
              _fragmentShaderFor(model),
              layout: _kInstancedLayout,
            )
          : device.createPipeline(
              skinned
                  ? skinnedVertexShader
                  : lightmapped
                  ? lightmappedVertexShader
                  : vertexShader,
              _fragmentShaderFor(model),
            ),
    );
  }
}

/// The two slots an instanced draw binds: the standard vertex in slot 0, one
/// per vertex, and the placement in slot 1, one per instance.
///
/// Declared rather than read off the shader, because a shader's `in`
/// declarations say what the attributes are and not which buffer each comes
/// from; the split is what this spec exists to state, and `InstancedMeshNode`
/// says what slot 1 holds.
final VertexLayoutSpec _kInstancedLayout = VertexLayoutSpec(<BufferLayout>[
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
    ],
  ),
]);

// `Renderer.dispose` is not declared here. An extension's members are only
// in scope where the extension itself is — and this one is private, visible
// only inside this library — so a public method a host application must be
// able to call has to be a genuine member of the class, declared where the
// class is. Find it in `renderer.dart`, beside the fallback-texture getters
// it clears.
