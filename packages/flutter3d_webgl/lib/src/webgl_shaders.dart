/// Shaders for the WebGL2 backend: GLSL ES 3.00, compiled at run time.
///
/// The other backend loads a `.shaderbundle` that `impellerc` produced ahead of
/// time. There is no such artefact here and there does not need to be: a
/// browser compiles GLSL itself, so a "bundle" is a map from the engine's entry
/// point names to source text.
///
/// **The names are the contract.** `LightingModel.shaderName` and the
/// renderer's `require` calls name entry points — 'MeshVertex', 'Pbr',
/// 'Composite' and the rest — and every backend must answer to them. That is
/// the one part of the seam nothing abstracts away, and it is why this file
/// takes the names as given rather than inventing its own.
library;

import 'dart:js_interop';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_device.dart';

/// GLSL ES 3.00 sources, by the engine's entry point name.
///
/// Loaded by the application — from assets, or generated — because *where* the
/// text comes from is not this package's business, and a package that reached
/// for `rootBundle` would be untestable off a Flutter binding.
final class ShaderSources {
  const ShaderSources(this.vertex, this.fragment);

  /// Name to source, for vertex stages.
  final Map<String, String> vertex;

  /// Name to source, for fragment stages.
  final Map<String, String> fragment;

  /// Every name this set can answer to.
  Iterable<String> get names => <String>{...vertex.keys, ...fragment.keys};
}

/// What a [ShaderHandle] carries here: a compiled stage and which kind it is.
final class WebGlShader {
  WebGlShader(this.shader, this.isVertex);

  /// The compiled object this stage currently is.
  ///
  /// **Mutable, and that is the whole of how a hot reload works on this
  /// backend.** flutter_gpu mutates a stage in place when a bundle is
  /// reparsed; GL has no such thing — a `WebGLShader` is compiled once from
  /// one source — so keeping the `ShaderHandle` the renderer holds means
  /// swapping what sits behind it. `WebGlLoadedShaderLibrary.refresh` is the
  /// one writer, and it deletes the object it replaces.
  web.WebGLShader shader;
  final bool isVertex;
}

/// Compiles one stage, or throws naming it and quoting the driver's log.
///
/// Shared by the engine's library and a loaded one, because a stage that
/// failed to compile and came back null would look exactly like a stage the
/// bundle never had, and the two need different fixes — so both refuse the
/// same way, loudly.
///
/// The info log is read before the shader is deleted, and deleted it must be:
/// nothing caches a failure, so every retry would otherwise leak one more GL
/// shader.
web.WebGLShader compileWebGlShader(
  web.WebGL2RenderingContext gl,
  String name,
  String source, {
  required bool isVertex,
}) {
  final type = isVertex
      ? web.WebGLRenderingContext.VERTEX_SHADER
      : web.WebGLRenderingContext.FRAGMENT_SHADER;
  final shader = gl.createShader(type)!;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  final ok =
      gl.getShaderParameter(shader, web.WebGLRenderingContext.COMPILE_STATUS)!
          as JSBoolean;
  if (!ok.toDart) {
    final log = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw StateError('the "$name" shader did not compile:\n$log');
  }
  return shader;
}

/// A [ShaderLibrary] over sources compiled on first use.
///
/// Compiled lazily and cached, because a scene uses a handful of the bundle's
/// stages and compiling all of them at startup would cost a visible pause for
/// shaders the frame never binds.
final class WebGlShaderLibrary implements ShaderLibrary {
  WebGlShaderLibrary(this._gl, this._sources);

  final web.WebGL2RenderingContext _gl;
  final ShaderSources _sources;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  /// Linked programs, by the *handles* of the pair and not their names.
  ///
  /// It was keyed by `'$vertex+$fragment'`, and that stopped being a key the
  /// day a second library could answer the same name: a bundle loaded from
  /// bytes wins `Pbr` over the engine's when it is layered first, and a cache
  /// keyed on the word would hand back whichever pair linked first — the
  /// engine's stage running where the application's was asked for, with the
  /// lookup itself returning the right handle. Identity is what the pipeline
  /// actually depends on, so identity is the key. A reload keeps the handles
  /// and evicts through [forgetPrograms], so the same key then links the new
  /// code.
  final Map<ShaderHandle, Map<ShaderHandle, WebGlProgram>> _programs =
      <ShaderHandle, Map<ShaderHandle, WebGlProgram>>{};

  @override
  ShaderHandle? operator [](String name) =>
      _handles.putIfAbsent(name, () => _compile(name));

  ShaderHandle? _compile(String name) {
    final isVertex = _sources.vertex.containsKey(name);
    final source = isVertex ? _sources.vertex[name] : _sources.fragment[name];
    // Null rather than throwing: the contract says a missing name comes back
    // null and lets the caller decide, because the renderer refuses to start
    // while a contributor merely draws nothing.
    if (source == null) return null;
    // A failed compile throws out of `putIfAbsent`, so it is never cached.
    final shader = compileWebGlShader(_gl, name, source, isVertex: isVertex);
    return ShaderHandle(backend: WebGlShader(shader, isVertex), name: name);
  }

  /// Links a pair of stages and reflects what the engine will need to bind.
  ///
  /// Cached on the pair, for the reason the other backend caches: linking is
  /// expensive, and the engine asks for the same pair every frame.
  /// Links a stage pair, and wraps it with the layout the pipeline was asked
  /// for.
  ///
  /// **The GL program is cached by the stage pair; the layout is not part of
  /// it.** A layout changes how attributes are pointed at buffers at bind time,
  /// through `vertexAttribPointer`, and not how the program links — so two
  /// layouts over one pair share one linked program and differ only in the
  /// wrapper. Keying the cache on the layout as well would link the same
  /// program twice; ignoring the layout when a cached program is found would
  /// hand back a pipeline that quietly draws with the wrong one, which is the
  /// mistake this shape makes impossible rather than merely unlikely.
  PipelineHandle link(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) {
    final key = '${vertex.name}+${fragment.name}';
    final linked = _programs
        .putIfAbsent(vertex, () => <ShaderHandle, WebGlProgram>{})
        .putIfAbsent(fragment, () => _link(vertex, fragment));
    return PipelineHandle(
      backend: WebGlProgram(
        linked.program,
        linked.attributes,
        linked.blocks,
        linked.samplers,
        layout: layout,
      ),
      name: key,
    );
  }

  /// Deletes every linked program that involves one of [stale], so the next
  /// [link] of the same pair links again.
  ///
  /// Called by a loaded library after it has swapped the compiled object
  /// behind a handle: the handle is the same, the code is not, and a program
  /// linked from the old code would draw it until this runs.
  void forgetPrograms(Iterable<ShaderHandle> stale) {
    final gone = stale.toSet();
    for (final vertex in gone) {
      final byFragment = _programs.remove(vertex);
      if (byFragment == null) continue;
      for (final program in byFragment.values) {
        _gl.deleteProgram(program.program);
      }
    }
    for (final byFragment in _programs.values) {
      for (final fragment in gone) {
        final program = byFragment.remove(fragment);
        if (program != null) _gl.deleteProgram(program.program);
      }
    }
  }

  WebGlProgram _link(ShaderHandle vertex, ShaderHandle fragment) {
    final program = _gl.createProgram()!;
    _gl.attachShader(program, (vertex.backend as WebGlShader).shader);
    _gl.attachShader(program, (fragment.backend as WebGlShader).shader);
    _gl.linkProgram(program);
    final linked =
        _gl.getProgramParameter(program, web.WebGLRenderingContext.LINK_STATUS)!
            as JSBoolean;
    if (!linked.toDart) {
      // The log first, the delete second, the throw last — the same discipline
      // as a failed compile above: the throw escapes `putIfAbsent`, nothing
      // caches the failure, and a retry would leak one GL program per attempt
      // if this path kept the object.
      final log = _gl.getProgramInfoLog(program);
      _gl.deleteProgram(program);
      throw StateError(
        'linking ${vertex.name} with ${fragment.name} failed:\n$log',
      );
    }

    return WebGlProgram(
      program,
      _reflectAttributes(program),
      _reflectBlocks(program),
      _reflectSamplers(program),
    );
  }

  /// How many compiled shaders and linked programs are currently cached, for
  /// tests. Falls to zero after [dispose]. The nulls in `_handles` — names the
  /// sources never had — are cached answers, not GL objects, and do not count.
  int get debugTrackedResourceCount =>
      _programCount + _handles.values.nonNulls.length;

  int get _programCount => _programs.values.fold(
    0,
    (int count, Map<ShaderHandle, WebGlProgram> byFragment) =>
        count + byFragment.length,
  );

  /// Deletes every cached program and shader, and forgets them.
  ///
  /// GL shaders and programs are driver objects like any texture or buffer:
  /// nothing collects them, so a library that compiled lazily and cached
  /// forever leaked one of each per entry point for the life of the tab.
  /// `WebGlDevice.dispose` calls this alongside its own teardown; the maps are
  /// cleared so the count above falls to zero rather than naming objects the
  /// driver no longer has.
  ///
  /// The programs a loaded library's stages were linked into are here too —
  /// linking goes through the device's library whichever library answered the
  /// names — so this is also where they go.
  void dispose() {
    for (final byFragment in _programs.values) {
      for (final program in byFragment.values) {
        _gl.deleteProgram(program.program);
      }
    }
    _programs.clear();
    for (final handle in _handles.values.nonNulls) {
      _gl.deleteShader((handle.backend as WebGlShader).shader);
    }
    _handles.clear();
  }

  /// Vertex attributes, in location order.
  ///
  /// Location order and not declaration order, and the difference matters: the
  /// engine's vertices are interleaved in the order `VertexLayout` names them,
  /// and the shaders assign locations to match. Sorting by location is what
  /// ties the two together without the HAL carrying a descriptor — see
  /// [WebGlProgram.attributes].
  List<WebGlAttribute> _reflectAttributes(web.WebGLProgram program) {
    final count =
        (_gl.getProgramParameter(
                  program,
                  web.WebGLRenderingContext.ACTIVE_ATTRIBUTES,
                )!
                as JSNumber)
            .toDartInt;
    final found = <WebGlAttribute>[];
    for (var i = 0; i < count; i++) {
      final info = _gl.getActiveAttrib(program, i);
      if (info == null) continue;
      final location = _gl.getAttribLocation(program, info.name);
      // Built-ins like gl_VertexID report a negative location and are not fed
      // from a buffer.
      if (location < 0) continue;
      found.add(WebGlAttribute(location, _componentsOf(info.type)));
    }
    found.sort(
      (WebGlAttribute a, WebGlAttribute b) => a.location.compareTo(b.location),
    );
    return found;
  }

  static int _componentsOf(int type) => switch (type) {
    web.WebGLRenderingContext.FLOAT => 1,
    web.WebGLRenderingContext.FLOAT_VEC2 => 2,
    web.WebGLRenderingContext.FLOAT_VEC3 => 3,
    web.WebGLRenderingContext.FLOAT_VEC4 => 4,
    _ => throw UnsupportedError(
      'vertex attributes in this engine are floats and vectors of them; '
      'GL type $type is neither. Integer attributes would need the HAL '
      'to describe a vertex layout rather than take it from the shader.',
    ),
  };

  /// Uniform blocks, with their std140 member offsets.
  ///
  /// Reflected rather than computed. The packing rules are the driver's to
  /// apply, and a backend that laid out std140 by hand would be maintaining a
  /// second copy of a specification — which is the shape of bug this project
  /// has spent the most time on.
  Map<String, WebGlBlock> _reflectBlocks(web.WebGLProgram program) {
    final count =
        (_gl.getProgramParameter(
                  program,
                  web.WebGL2RenderingContext.ACTIVE_UNIFORM_BLOCKS,
                )!
                as JSNumber)
            .toDartInt;
    final blocks = <String, WebGlBlock>{};
    for (var index = 0; index < count; index++) {
      final name = _gl.getActiveUniformBlockName(program, index);
      if (name == null) continue;
      final size =
          (_gl.getActiveUniformBlockParameter(
                    program,
                    index,
                    web.WebGL2RenderingContext.UNIFORM_BLOCK_DATA_SIZE,
                  )!
                  as JSNumber)
              .toDartInt;

      final indices =
          _gl.getActiveUniformBlockParameter(
                program,
                index,
                web.WebGL2RenderingContext.UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES,
              )!
              as JSUint32Array;
      final members = indices.toDart;
      final offsets =
          _gl.getActiveUniforms(
                program,
                members.map((int i) => i.toJS).toList().toJS,
                web.WebGL2RenderingContext.UNIFORM_OFFSET,
              )!
              as JSArray<JSNumber>;

      final byName = <String, int>{};
      for (var i = 0; i < members.length; i++) {
        final info = _gl.getActiveUniform(program, members[i]);
        if (info == null) continue;
        // GLSL reports a block member as `Block.member`, and an array member as
        // `Block.member[0]`. The engine binds by the bare member name.
        var member = info.name;
        final dot = member.indexOf('.');
        if (dot >= 0) member = member.substring(dot + 1);
        final bracket = member.indexOf('[');
        if (bracket >= 0) member = member.substring(0, bracket);
        byName[member] = offsets.toDart[i].toDartInt;
      }
      blocks[name] = WebGlBlock(index, size, byName);
    }
    return blocks;
  }

  /// Sampler uniforms, by name.
  ///
  /// Only their presence matters here; the texture unit is assigned per bind,
  /// because the engine binds a slot when its material declares one and the set
  /// differs between draws.
  /// Whether a GL uniform type is one of the sampler types.
  ///
  /// The list is the WebGL2 set. Named by value rather than by constant because
  /// `package:web` exposes only the two this backend uses.
  static bool _isSampler(int type) => const <int>[
    0x8B5E, // SAMPLER_2D
    0x8B60, // SAMPLER_CUBE
    0x8DC1, // SAMPLER_2D_ARRAY
    0x8B62, // SAMPLER_2D_SHADOW
    0x8DC4, // SAMPLER_2D_ARRAY_SHADOW
    0x8DC5, // SAMPLER_CUBE_SHADOW
    0x8DCA, // INT_SAMPLER_2D
    0x8DCF, // INT_SAMPLER_2D_ARRAY
    0x8DD2, // UNSIGNED_INT_SAMPLER_2D
    0x8DD7, // UNSIGNED_INT_SAMPLER_2D_ARRAY
    0x8B5F, // SAMPLER_3D
    0x8DCB, // INT_SAMPLER_3D
    0x8DD3, // UNSIGNED_INT_SAMPLER_3D
    0x8DCC, // INT_SAMPLER_CUBE
    0x8DD4, // UNSIGNED_INT_SAMPLER_CUBE
  ].contains(type);

  Map<String, int> _reflectSamplers(web.WebGLProgram program) {
    final count =
        (_gl.getProgramParameter(
                  program,
                  web.WebGLRenderingContext.ACTIVE_UNIFORMS,
                )!
                as JSNumber)
            .toDartInt;
    final samplers = <String, int>{};
    for (var i = 0; i < count; i++) {
      final info = _gl.getActiveUniform(program, i);
      if (info == null) continue;
      final type = info.type;
      if (type == web.WebGLRenderingContext.SAMPLER_2D ||
          type == web.WebGLRenderingContext.SAMPLER_CUBE) {
        samplers[info.name] = i;
        continue;
      }
      // Anything else is not something this reflection knows how to bind, and
      // dropping it silently is how a sampler stops working with nothing said.
      //
      // That is not hypothetical: this line read `!= SAMPLER_2D` and skipped
      // the rest, so a `samplerCube` never reached `samplers`, `bindTexture`
      // then found no location and returned, and the draw sampled whatever was
      // left in texture unit zero. Impeller and the software rasteriser drew
      // the right picture; the web drew rubbish and logged nothing. Throwing
      // means the next non-2D sampler is a message rather than a mystery.
      if (_isSampler(type)) {
        throw StateError(
          'The shader declares "${info.name}", a sampler of GL type 0x'
          '${type.toRadixString(16)} that this backend cannot bind. Teach '
          '_reflectSamplers and bindTexture about it, or the draw will sample '
          'whatever was in the texture unit.',
        );
      }
    }
    return samplers;
  }
}
