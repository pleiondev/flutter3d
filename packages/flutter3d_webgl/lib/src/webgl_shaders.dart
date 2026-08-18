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

import 'package:flutter3d_graphics/flutter3d_graphics.dart';
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
  const WebGlShader(this.shader, this.isVertex);
  final web.WebGLShader shader;
  final bool isVertex;
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
  final Map<String, WebGlProgram> _programs = <String, WebGlProgram>{};

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

    final type = isVertex
        ? web.WebGLRenderingContext.VERTEX_SHADER
        : web.WebGLRenderingContext.FRAGMENT_SHADER;
    final shader = _gl.createShader(type)!;
    _gl.shaderSource(shader, source);
    _gl.compileShader(shader);
    final ok = _gl.getShaderParameter(
        shader, web.WebGLRenderingContext.COMPILE_STATUS)! as JSBoolean;
    if (!ok.toDart) {
      // Loudly. A stage that failed to compile and came back null would look
      // exactly like a stage the bundle never had, and the two need different
      // fixes.
      throw StateError(
        'the "$name" shader did not compile:\n${_gl.getShaderInfoLog(shader)}',
      );
    }
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
  PipelineHandle link(ShaderHandle vertex, ShaderHandle fragment,
      {VertexLayoutSpec? layout}) {
    final key = '${vertex.name}+${fragment.name}';
    final linked = _programs.putIfAbsent(key, () => _link(vertex, fragment));
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

  WebGlProgram _link(ShaderHandle vertex, ShaderHandle fragment) {
    final program = _gl.createProgram()!;
    _gl.attachShader(program, (vertex.backend as WebGlShader).shader);
    _gl.attachShader(program, (fragment.backend as WebGlShader).shader);
    _gl.linkProgram(program);
    final linked = _gl.getProgramParameter(
        program, web.WebGLRenderingContext.LINK_STATUS)! as JSBoolean;
    if (!linked.toDart) {
      throw StateError(
        'linking ${vertex.name} with ${fragment.name} failed:\n'
        '${_gl.getProgramInfoLog(program)}',
      );
    }

    return WebGlProgram(
      program,
      _reflectAttributes(program),
      _reflectBlocks(program),
      _reflectSamplers(program),
    );
  }

  /// Vertex attributes, in location order.
  ///
  /// Location order and not declaration order, and the difference matters: the
  /// engine's vertices are interleaved in the order `VertexLayout` names them,
  /// and the shaders assign locations to match. Sorting by location is what
  /// ties the two together without the HAL carrying a descriptor — see
  /// [WebGlProgram.attributes].
  List<WebGlAttribute> _reflectAttributes(web.WebGLProgram program) {
    final count = (_gl.getProgramParameter(
            program, web.WebGLRenderingContext.ACTIVE_ATTRIBUTES)! as JSNumber)
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
    found.sort((WebGlAttribute a, WebGlAttribute b) =>
        a.location.compareTo(b.location));
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
    final count = (_gl.getProgramParameter(program,
            web.WebGL2RenderingContext.ACTIVE_UNIFORM_BLOCKS)! as JSNumber)
        .toDartInt;
    final blocks = <String, WebGlBlock>{};
    for (var index = 0; index < count; index++) {
      final name = _gl.getActiveUniformBlockName(program, index);
      if (name == null) continue;
      final size = (_gl.getActiveUniformBlockParameter(program, index,
              web.WebGL2RenderingContext.UNIFORM_BLOCK_DATA_SIZE)! as JSNumber)
          .toDartInt;

      final indices = _gl.getActiveUniformBlockParameter(
          program,
          index,
          web.WebGL2RenderingContext
              .UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES)! as JSUint32Array;
      final members = indices.toDart;
      final offsets = _gl.getActiveUniforms(
        program,
        members.map((int i) => i.toJS).toList().toJS,
        web.WebGL2RenderingContext.UNIFORM_OFFSET,
      )! as JSArray<JSNumber>;

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
  Map<String, int> _reflectSamplers(web.WebGLProgram program) {
    final count = (_gl.getProgramParameter(
            program, web.WebGLRenderingContext.ACTIVE_UNIFORMS)! as JSNumber)
        .toDartInt;
    final samplers = <String, int>{};
    for (var i = 0; i < count; i++) {
      final info = _gl.getActiveUniform(program, i);
      if (info == null) continue;
      if (info.type != web.WebGLRenderingContext.SAMPLER_2D) continue;
      samplers[info.name] = i;
    }
    return samplers;
  }
}
