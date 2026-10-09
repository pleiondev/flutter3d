/// Reads a material written as source into a [MaterialProgram] — `gfx-84n`.
///
/// ```text
/// material RimLight {
///   param float rimPower = 2.0;
///   param vec3 rimColor = vec3(0.2, 0.6, 1.0);
///   texture base = base_color_texture;
///
///   fragment {
///     let facing = clamp(nDotV, 0.0, 1.0);
///     let rim = pow(1.0 - facing, rimPower);
///     return vec4(albedo + rimColor * rim, alpha);
///   }
/// }
/// ```
///
/// A material may also answer each light itself — `P8`, the lighting hook:
///
/// ```text
/// material Toon {
///   light {
///     let banded = floor(nDotL * 3.0) / 3.0;
///     return albedo * banded / max(nDotL, 0.001);
///   }
///   fragment {
///     return vec4(lit, alpha);
///   }
/// }
/// ```
///
/// A file may say which version of the language it is written in, on a line
/// of its own ahead of `material`:
///
/// ```text
/// f3dmat 1
/// material RimLight { ... }
/// ```
///
/// Without the line it is version 1, which is every file written so far. A
/// build reads every version up to [materialLanguageVersion] and refuses a
/// newer one with the version that reads it.
///
/// Version 2 — item 9 of `tasks/1.0-scope-additions.md` — adds, behind
/// `f3dmat 2`:
///
/// ```text
/// f3dmat 2
/// material Shallows {
///   uniform float time = 0.0;
///   state { blend alpha; depthWrite off; depthLayer 1; effectsDepth on; }
///   vertex { out world = world + vec3(0.0, 0.02 * sin(time + world.x), 0.0); }
///   light { return albedo; }
///   ambient { return albedo * (ambient + lightmap); }
///   composite { return (direct + indirect) * occlusion + emissive; }
///   fragment {
///     let edge = clamp((sceneDepth - viewDepth) * 3.0, 0.0, 1.0);
///     return vec4(lit, alpha * edge);
///   }
/// }
/// ```
///
/// and two kinds besides `material`: `fullscreen Name { ... fragment {...} }`,
/// which reads `uv`, `sceneDepth` and the picture as the texture `scene`, and
/// `compute Name { workgroup 8 8; kernel {...} }`, which reads `cell`,
/// `size` and `uv` and returns the texel it writes. The site's material
/// language page is the reference, with what each backend does with each.
///
/// The `light` block runs once per light inside the engine's light loop and
/// returns how the surface answers it, which the engine multiplies by the
/// light's radiance, its `n·l` and its shadow; it reads the light through
/// `lightDir`, `halfDir`, `nDotL`, `nDotH` and `vDotH`. The fragment body
/// reads the result as `lit` — see `materialLitInput` for what that adds up.
///
/// /// **The vocabulary is GLSL's, and that is the whole design.** `clamp`, `mix`,
/// `pow`, the swizzles and the broadcasting rules all mean what they mean in
/// GLSL, because the emitted shader has to read like the source for anybody
/// debugging the pair — and because a language that invented its own `mix`
/// would have to explain how it differs from the one every author already
/// knows. What is *not* GLSL is everything a material must not be allowed to
/// do: declare a uniform block, sample a texture the engine does not bind,
/// write to a global, or loop. Those are refusals with a sentence attached
/// rather than omissions.
///
/// **Typed on the way in, not on the way out.** Every expression node carries
/// its type because the parser worked it out; an emitter that had to infer
/// types would be a second type checker, and the two would disagree about
/// something like `vec3 * float` on one backend only.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException, FormatSpec;

import 'material_ast.dart';

/// What the engine binds, and therefore the only names a `texture` declaration
/// may point at.
///
/// A material cannot invent a slot: the renderer binds textures by these names
/// and a name it does not know reaches the GPU as a missing sampler, which on
/// Metal is a crash rather than a black texture. The list is short because the
/// set really is that small — `surface.glsl` declares them.
const List<String> materialTextureBindings = <String>[
  'base_color_texture',
  'normal_texture',
  'occlusion_texture',
  'emissive_texture',
  'metallic_roughness_texture',
];

/// The newest material language version this build reads. A file with no
/// `f3dmat` line is version 1.
///
/// A source may open with `f3dmat <version>` before `material`. Every version
/// up to this one is read; a newer one is refused with the version to update
/// to.
///
/// **Version 2** (1.0) grows the syntax, and every construct it adds is read
/// only in a file that says `f3dmat 2`: the `state`, `vertex`, `ambient` and
/// `composite` blocks, the `fullscreen` and `compute` kinds, and the inputs
/// `sceneDepth`, `viewDepth` and `scenePosition`. Behind the header, because
/// an older build then refuses a newer file by its version rather than with
/// a syntax error, and because a version 1 file stays exactly what it was —
/// one that binds `let sceneDepth` still compiles. A version 2 file also
/// keeps names starting `f3d_` for the generated stage.
const int materialLanguageVersion = 2;

/// `.f3dmat` in the format registry: text, versioned by an optional
/// `f3dmat <N>` line, so it has no JSON envelope and no fixed magic.
///
/// `f3d.materialLanguage`, so it is not mistaken for the material file
/// (`.fmat`, `f3d.fmat`); the registry answers to its first id,
/// `f3d.material`, as well, which no file ever carried.
const FormatSpec f3dmatFormat = FormatSpec(
  id: 'f3d.materialLanguage',
  aliases: <String>['f3d.material'],
  version: materialLanguageVersion,
  suffixes: <String>['.f3dmat'],
  fixture: 'test/fixtures/v<N>/rim_glow.f3dmat',
  enveloped: false,
);

/// A material source that could not be read, with where it went wrong.
///
/// Line and column rather than a byte offset: the author is looking at the
/// text in an editor, and "at 1:14" is a place they can put a cursor.
final class MaterialSyntaxException extends Flutter3dFormatException {
  const MaterialSyntaxException(this.message, this.line, this.column);

  @override
  final String message;
  final int line;
  final int column;

  @override
  String toString() => 'MaterialSyntaxException at $line:$column: $message';
}

/// Reads [source] as one material.
MaterialProgram parseMaterial(String source) =>
    _Parser(_lex(source)).parseMaterial();

// ---------------------------------------------------------------------------
// Lexing
// ---------------------------------------------------------------------------

/// A token's kind, as the character or word that opens it.
///
/// Strings rather than a type of their own: the parser compares against
/// literals it writes out anyway (`'{'`, `'return'`), and a kind enum would be
/// a second spelling of the same set with a conversion between them.
final class _Token {
  const _Token(this.kind, this.text, this.line, this.column, [this.number]);

  /// One of `name`, `number`, `end`, or the punctuation itself.
  final String kind;
  final String text;
  final int line;
  final int column;

  /// A number token's value as written; a token carries no unit.
  final double? number;
}

const String _punctuation = '{}()=;,.+-*/';

List<_Token> _lex(String source) {
  final tokens = <_Token>[];
  var line = 1;
  var column = 1;
  var at = 0;

  void advance(int count) {
    for (var i = 0; i < count; i++) {
      if (source[at + i] == '\n') {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    at += count;
  }

  while (at < source.length) {
    final ch = source[at];
    if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
      advance(1);
      continue;
    }
    // `//` to the end of the line. A material is a thing an author comments,
    // and a language with no comments is one whose files grow a README beside
    // them.
    if (ch == '/' && at + 1 < source.length && source[at + 1] == '/') {
      while (at < source.length && source[at] != '\n') {
        advance(1);
      }
      continue;
    }

    final startLine = line;
    final startColumn = column;
    if (_isDigit(ch) ||
        (ch == '.' && at + 1 < source.length && _isDigit(source[at + 1]))) {
      var end = at;
      while (end < source.length &&
          (_isDigit(source[end]) || source[end] == '.')) {
        end++;
      }
      final text = source.substring(at, end);
      final value = double.tryParse(text);
      if (value == null) {
        throw MaterialSyntaxException(
          '"$text" is not a number.',
          startLine,
          startColumn,
        );
      }
      advance(end - at);
      tokens.add(_Token('number', text, startLine, startColumn, value));
      continue;
    }
    if (_isNameStart(ch)) {
      var end = at;
      while (end < source.length && _isNamePart(source[end])) {
        end++;
      }
      final text = source.substring(at, end);
      advance(end - at);
      tokens.add(_Token('name', text, startLine, startColumn));
      continue;
    }
    if (_punctuation.contains(ch)) {
      advance(1);
      tokens.add(_Token(ch, ch, startLine, startColumn));
      continue;
    }
    throw MaterialSyntaxException(
      '"$ch" is not part of this language.',
      startLine,
      startColumn,
    );
  }
  tokens.add(_Token('end', '', line, column));
  return tokens;
}

/// Names a `let` would collide with once `emitMaterialFragment` writes it into
/// `main()` beside what is already there.
///
/// **A local is emitted under its own name**, so that the shader reads like
/// the source, and that makes these its namespace too: `s` and `result` are
/// the emitter's own locals (a second declaration does not compile), the
/// samplers and `v_…` varyings are what `sample(…)` and the `uv`/`world`
/// inputs are written as (shadowing them compiles and reads the wrong value),
/// and the rest are GLSL words a declaration cannot take.
const Set<String> _reservedNames = <String>{
  // The emitter's own, `P8`'s uniform block among them.
  's', 'result', 'main', 'material_params', 'MaterialParams', 'light', 'lit',
  // `surface.glsl`'s, as the emitted shader spells them.
  'Surface', 'LightSample', 'ReadSurface', 'WriteSurface', 'ShadeLight',
  'LightVisibility', 'v_texcoord', 'v_world_position', 'AccumulateLights',
  'ShadowFactor', 'ApplyCommonMaps', 'SampleLightmap',
  ...materialTextureBindings,
  // GLSL: the one builtin the emitter calls that is not a [MaterialBuiltin],
  // and the keywords and type names a declaration cannot reuse.
  'texture', 'in', 'out', 'inout', 'uniform', 'const', 'void', 'bool', 'int',
  'uint', 'true', 'false', 'if', 'else', 'for', 'while', 'do', 'switch',
  'case', 'default', 'break', 'continue', 'return', 'discard', 'struct',
  'layout', 'precision', 'highp', 'mediump', 'lowp', 'flat', 'smooth',
  'centroid', 'invariant', 'attribute', 'varying', 'sampler2D',
  'samplerCube', 'mat2', 'mat3', 'mat4', 'ivec2', 'ivec3', 'ivec4', 'uvec2',
  'uvec3', 'uvec4', 'bvec2', 'bvec3', 'bvec4',
};

/// Names a `let` in a `vertex` block would collide with, on top of
/// [_reservedNames]: the vertex stage's own attributes and blocks, which the
/// emitted `main` reads under these names.
const Set<String> _vertexReservedNames = <String>{
  'texcoord',
  'tangent',
  'joints',
  'weights',
  'frame_info',
  'FrameInfo',
  'skin_info',
  'SkinInfo',
  'material_vertex_info',
  'MaterialVertexInfo',
  'v_normal',
  'v_tangent',
  'v_color',
  'v_lightmap_uv',
  'v_instance',
  'ApplyMorph',
  'JointIndex',
  'SkinMatrix',
};

/// Names a version 2 stage declares besides [_reservedNames]: the blocks and
/// samplers a full-screen stage, a compute kernel and the scene's depth are
/// read through.
const Set<String> _version2ReservedNames = <String>{
  'v_uv',
  'frag_color',
  'scene_texture',
  'surface_texture',
  'scene_depth_texture',
  'SceneDepthInfo',
  'scene_depth_info',
  'target',
  'image2D',
  'imageStore',
  'textureLod',
  'ShadeAmbient',
  'ShadeComposite',
  'MaterialLights',
};

/// One body of a source — which block it is, what it reads and what it
/// returns.
final class _Block {
  const _Block(
    this.what,
    this.opening, {
    required this.inputs,
    this.returns,
    this.samples = true,
  });

  /// How a message names it: "fragment body", "light block".
  final String what;

  /// The word that opens it, for "{" after it.
  final String opening;

  /// The inputs it reads by name.
  final List<MaterialInput> inputs;

  /// The type its `return` must have; null for a `vertex` block, which has
  /// outputs instead.
  final MaterialType? returns;

  /// Whether `sample(...)` may be called in it.
  final bool samples;

  bool get isVertex => returns == null;
}

/// Every input a version 2 surface names in one block or another, for the
/// rule that a declaration may not take one's name.
const List<MaterialInput> _surfaceVersion2Inputs = <MaterialInput>[
  ...materialSceneInputs,
  ...materialVertexInputs,
  ...materialAmbientInputs,
  ...materialCompositeInputs,
];

bool _isDigit(String ch) => ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;

bool _isNameStart(String ch) =>
    (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
    (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
    ch == '_';

bool _isNamePart(String ch) => _isNameStart(ch) || _isDigit(ch);

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

final class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  int at = 0;

  final List<MaterialParameter> parameters = <MaterialParameter>[];
  final List<MaterialTextureSlot> textures = <MaterialTextureSlot>[];
  final Map<String, MaterialType> locals = <String, MaterialType>{};

  /// The language version the source declared — 1 without a header.
  int version = 1;

  /// What the source is, read after the version.
  MaterialStageKind kind = MaterialStageKind.surface;

  /// The body being read, or null between bodies.
  _Block? block;

  /// Whether the body being read is the `light` block — `P8`.
  bool get inLight => identical(block, lightBlock);

  /// Where the fragment body first read `lit`, to point at when the material
  /// turns out to have no `light` block to gather it.
  _Token? litAt;

  /// Where a body first read the scene behind it, to point at when the
  /// material turns out not to be translucent.
  _Token? sceneAt;
  final Set<String> inputsUsed = <String>{};

  /// The slots `sample` read, for the rule that a full-screen stage and a
  /// kernel read every texture they declare.
  final Set<String> sampled = <String>{};

  /// What the `vertex` block being read has written.
  final Set<String> outputs = <String>{};

  // The bodies, each with the inputs it reads. Built per parse, because the
  // fragment body's set depends on the version the file declares.
  late final _Block fragmentBlock = _Block(
    'fragment body',
    'fragment',
    inputs: <MaterialInput>[
      ...materialInputs,
      if (version >= 2) ...materialSceneInputs,
    ],
    returns: MaterialType.vec4,
  );
  final _Block lightBlock = const _Block(
    'light block',
    'light',
    inputs: <MaterialInput>[...materialInputs, ...materialLightInputs],
    returns: MaterialType.vec3,
  );
  final _Block ambientBlock = const _Block(
    'ambient block',
    'ambient',
    inputs: <MaterialInput>[...materialInputs, ...materialAmbientInputs],
    returns: MaterialType.vec3,
  );
  final _Block compositeBlock = const _Block(
    'composite block',
    'composite',
    inputs: <MaterialInput>[...materialInputs, ...materialCompositeInputs],
    returns: MaterialType.vec3,
  );
  final _Block vertexBlock = const _Block(
    'vertex block',
    'vertex',
    inputs: materialVertexInputs,
    samples: false,
  );
  final _Block fullscreenBlock = const _Block(
    'full-screen stage',
    'fragment',
    inputs: materialFullscreenInputs,
    returns: MaterialType.vec4,
  );
  final _Block kernelBlock = const _Block(
    'kernel',
    'kernel',
    inputs: materialComputeInputs,
    returns: MaterialType.vec4,
  );

  _Token get current => tokens[at];

  Never fail(String message, [_Token? where]) {
    final token = where ?? current;
    throw MaterialSyntaxException(message, token.line, token.column);
  }

  _Token take(String kind, String what) {
    if (current.kind != kind) {
      fail(
        'expected $what, found "${current.text.isEmpty ? 'the end of the '
                  'file' : current.text}".',
      );
    }
    final token = current;
    at++;
    return token;
  }

  bool takeIf(String kind) {
    if (current.kind != kind) return false;
    at++;
    return true;
  }

  bool takeWordIf(String word) {
    if (current.kind != 'name' || current.text != word) return false;
    at++;
    return true;
  }

  MaterialProgram parseMaterial() {
    version = parseVersion();
    kind = parseKind();
    final surface = kind == MaterialStageKind.surface;
    final name = take('name', 'the material\'s name').text;
    take('{', '"{" after the material\'s name');
    // The picture a full-screen stage draws over, bound as every post stage
    // of the engine's binds it.
    if (kind == MaterialStageKind.fullscreen) {
      textures.add(const MaterialTextureSlot('scene', 'scene_texture'));
    }

    List<MaterialStatement>? body;
    List<MaterialStatement>? light;
    List<MaterialStatement>? vertex;
    List<MaterialStatement>? ambient;
    List<MaterialStatement>? composite;
    var state = MaterialFileState.none;
    var workgroup = (8, 8);
    _Token? lightAt;
    _Token? ambientAt;
    _Token? compositeAt;
    _Token? stateAt;
    _Token? workgroupAt;

    /// The body a word opens, read once.
    List<MaterialStatement> once(
      List<MaterialStatement>? already,
      _Token where,
      String what,
      _Block block,
    ) {
      at++;
      if (already != null) fail('a material has one $what.', where);
      return parseBody(block);
    }

    while (!takeIf('}')) {
      if (current.kind == 'end') fail('the material is never closed with "}".');
      final word = current.kind == 'name' ? current.text : '';
      final where = current;
      if (takeWordIf('param')) {
        parseParameter();
      } else if (takeWordIf('uniform')) {
        parseParameter(uniform: true);
      } else if (takeWordIf('texture')) {
        parseTexture();
      } else if (word == 'fragment' && kind != MaterialStageKind.compute) {
        at++;
        if (body != null) fail('a material has one fragment body.');
        body = parseBody(surface ? fragmentBlock : fullscreenBlock);
      } else if (word == 'kernel' && kind == MaterialStageKind.compute) {
        body = once(body, where, 'kernel', kernelBlock);
      } else if (word == 'light' && surface) {
        lightAt = where;
        at++;
        if (light != null) fail('a material has one light block.', lightAt);
        light = parseBody(lightBlock);
      } else if (surface &&
          version < 2 &&
          const <String>{
            'state',
            'vertex',
            'ambient',
            'composite',
          }.contains(word)) {
        fail(
          '"$word" is material language version 2: open the file with '
          '"f3dmat 2".',
        );
      } else if (word == 'state' && surface) {
        at++;
        if (stateAt != null) fail('a material has one state block.', where);
        stateAt = where;
        state = parseState();
      } else if (word == 'vertex' && surface) {
        vertex = once(vertex, where, 'vertex block', vertexBlock);
      } else if (word == 'ambient' && surface) {
        ambientAt = where;
        ambient = once(ambient, where, 'ambient block', ambientBlock);
      } else if (word == 'composite' && surface) {
        compositeAt = where;
        composite = once(composite, where, 'composite block', compositeBlock);
      } else if (word == 'workgroup' && kind == MaterialStageKind.compute) {
        at++;
        if (workgroupAt != null) fail('a kernel has one workgroup.', where);
        workgroupAt = where;
        workgroup = parseWorkgroup();
      } else {
        fail(switch (kind) {
          _ when version < 2 =>
            '"${current.text}" is not a declaration: a material holds '
                '"param", "uniform", "texture", one "fragment" and at most '
                'one "light".',
          MaterialStageKind.fullscreen =>
            '"${current.text}" is not a declaration: a full-screen stage '
                'holds "param", "uniform", "texture" and one "fragment".',
          MaterialStageKind.compute =>
            '"${current.text}" is not a declaration: a compute stage holds '
                '"param", "uniform", "texture", at most one "workgroup" and '
                'one "kernel".',
          _ =>
            '"${current.text}" is not a declaration: a material holds '
                '"param", "uniform", "texture", at most one "state", one '
                '"fragment", and at most one each of "vertex", "light", '
                '"ambient" and "composite".',
        });
      }
    }
    if (body == null) {
      fail(
        kind == MaterialStageKind.compute
            ? 'the compute stage has no kernel.'
            : kind == MaterialStageKind.fullscreen
            ? 'the full-screen stage has no fragment body.'
            : 'the material has no fragment body.',
      );
    }
    if (litAt case final where? when light == null) {
      fail(
        '"lit" is the light a "light" block gathers, and this material has '
        'none: add one, or return the colour without it.',
        where,
      );
    }
    if (light != null && litAt == null) {
      fail(
        'the light block is never read: a fragment body that does not read '
        '"lit" gathers no lights, and the compiled shader would drop the '
        'block and everything the engine binds for it.',
        lightAt,
      );
    }
    // The two hooks shape the light a `light` block gathers; without one
    // there is no `lit` for them to shape.
    for (final (hook, where) in <(String, _Token?)>[
      ('ambient', ambientAt),
      ('composite', compositeAt),
    ]) {
      if (where != null && light == null) {
        fail(
          'the $hook block shapes the light a "light" block gathers, and this '
          'material has none: add one, or leave the $hook block out.',
          where,
        );
      }
    }
    if ((!state.environment || !state.directional) && light == null) {
      fail(
        '"environment" and "directional" switch light out of what a "light" '
        'block gathers, and this material has none.',
        stateAt,
      );
    }
    if (!state.environment && ambientAt != null) {
      fail(
        'the ambient block is the environment\'s light, and the state block '
        'compiles the environment out with "environment off": keep one or '
        'the other.',
        ambientAt,
      );
    }
    if (sceneAt case final where? when !state.isTranslucent && surface) {
      fail(
        '"${where.text}" is the scene behind a translucent surface, and this '
        'material is opaque: give its state block "blend alpha", "blend '
        'additive" or "blend premultiplied". An opaque surface is the scene '
        'it would be reading.',
        where,
      );
    }
    if (!surface) {
      for (final slot in textures) {
        if (sampled.contains(slot.name)) continue;
        fail(
          slot.name == 'scene'
              ? 'a full-screen stage reads the picture it draws over, and '
                    'this one never samples it: read it with '
                    'sample(scene, uv).'
              : '"${slot.name}" is declared and never sampled: the compiled '
                    'stage would drop it, and binding a sampler a stage does '
                    'not have is a native crash on Metal.',
        );
      }
    }

    return MaterialProgram(
      name: name,
      parameters: parameters,
      textures: textures,
      body: body,
      light: light,
      vertex: vertex,
      ambient: ambient,
      composite: composite,
      inputsUsed: inputsUsed,
      languageVersion: version,
      kind: kind,
      state: state,
      workgroupSize: workgroup,
    );
  }

  /// `material`, `fullscreen` or `compute` — the last two version 2.
  MaterialStageKind parseKind() {
    final token = current;
    for (final candidate in MaterialStageKind.all) {
      if (!takeWordIf(candidate.name)) continue;
      if (candidate != MaterialStageKind.surface && version < 2) {
        fail(
          '"${candidate.name}" is material language version 2: open the file '
          'with "f3dmat 2".',
          token,
        );
      }
      return candidate;
    }
    fail(
      version < 2
          ? 'a material starts with the word "material".'
          : 'a source starts with "material", "fullscreen" or "compute".',
    );
  }

  /// A `state` block's settings, once each — version 2.
  MaterialFileState parseState() {
    take('{', '"{" after "state"');
    final seen = <String>{};
    MaterialBlend? blend;
    double? cutoff;
    bool? depthWrite;
    bool? depthTest;
    String? depthCompare;
    bool? alphaToCoverage;
    bool? doubleSided;
    int? depthLayer;
    bool? effectsDepth;
    var environment = true;
    var directional = true;
    _Token? cutoffAt;
    _Token? coverageAt;
    _Token? compareAt;
    _Token? effectsAt;

    bool onOff(_Token key) {
      final value = take('name', '"on" or "off" after "${key.text}"');
      return switch (value.text) {
        'on' => true,
        'off' => false,
        _ => fail(
          '"${key.text}" is "on" or "off", not "${value.text}".',
          value,
        ),
      };
    }

    while (!takeIf('}')) {
      if (current.kind == 'end') fail('the state block is never closed.');
      final key = take('name', 'a setting');
      if (!seen.add(key.text)) fail('"${key.text}" is set twice.', key);
      switch (key.text) {
        case 'blend':
          final value = take('name', 'a blend after "blend"');
          blend =
              MaterialBlend.byName(value.text) ??
              fail(
                '"${value.text}" is not a blend: '
                '${MaterialBlend.all.join(', ')} are.',
                value,
              );
        case 'cutoff':
          cutoffAt = key;
          final value = take('number', 'the alpha the mask cuts at');
          cutoff = value.number!;
          if (cutoff < 0 || cutoff > 1) {
            fail('a cutoff is an alpha, from nought to one.', value);
          }
        case 'depthWrite':
          depthWrite = onOff(key);
        case 'depthTest':
          depthTest = onOff(key);
        case 'depthCompare':
          compareAt = key;
          final value = take('name', 'a depth test after "depthCompare"');
          if (!materialDepthCompares.contains(value.text)) {
            fail(
              '"${value.text}" is not a depth test: '
              '${materialDepthCompares.join(', ')} are.',
              value,
            );
          }
          depthCompare = value.text;
        case 'alphaToCoverage':
          coverageAt = key;
          alphaToCoverage = onOff(key);
        case 'doubleSided':
          doubleSided = onOff(key);
        case 'depthLayer':
          final negative = takeIf('-');
          final value = take('number', 'a whole number after "depthLayer"');
          final number = value.number!;
          if (number != number.truncateToDouble() ||
              number > materialDepthLayerLimit) {
            fail(
              'a depth layer is a whole number from '
              '-$materialDepthLayerLimit to $materialDepthLayerLimit.',
              value,
            );
          }
          depthLayer = negative ? -number.toInt() : number.toInt();
        case 'effectsDepth':
          effectsAt = key;
          effectsDepth = onOff(key);
        case 'environment':
          environment = onOff(key);
        case 'directional':
          directional = onOff(key);
        default:
          fail(
            '"${key.text}" is not a setting: a state block sets blend, '
            'cutoff, depthWrite, depthTest, depthCompare, alphaToCoverage, '
            'doubleSided, depthLayer, effectsDepth, environment and '
            'directional.',
            key,
          );
      }
      take(';', '";" after the setting');
    }

    final masked = blend == MaterialBlend.mask;
    if (cutoffAt != null && !masked) {
      fail(
        'a cutoff is where "blend mask" cuts, and this is not masked.',
        cutoffAt,
      );
    }
    if (coverageAt != null && alphaToCoverage! && !masked) {
      fail(
        'alpha to coverage antialiases the edge "blend mask" cuts, and this '
        'is not masked.',
        coverageAt,
      );
    }
    if (compareAt != null && depthTest != null) {
      fail(
        '"depthTest" and "depthCompare" both say how the depth is tested: '
        'keep one.',
        compareAt,
      );
    }
    if (effectsAt != null && effectsDepth! && !(blend?.translucent ?? false)) {
      fail(
        '"effectsDepth" puts a translucent surface into the depth the '
        'effects read, and an opaque one is there already.',
        effectsAt,
      );
    }
    return MaterialFileState(
      blend: blend,
      cutoff: cutoff,
      depthWrite: depthWrite,
      depthTest: depthTest,
      depthCompare: depthCompare,
      alphaToCoverage: alphaToCoverage,
      doubleSided: doubleSided,
      depthLayer: depthLayer,
      effectsDepth: effectsDepth,
      environment: environment,
      directional: directional,
    );
  }

  /// `workgroup x y;` — a kernel's workgroup size, version 2.
  ///
  /// At most 256 invocations in all: WebGPU's own limit, which the other
  /// backends that run compute meet too.
  (int, int) parseWorkgroup() {
    int side() {
      final token = take('number', 'a whole number of invocations');
      final value = token.number!;
      if (value != value.truncateToDouble() || value < 1 || value > 256) {
        fail('a workgroup side is a whole number from 1 to 256.', token);
      }
      return value.toInt();
    }

    final x = side();
    final y = side();
    take(';', '";" after the workgroup');
    if (x * y > 256) {
      fail('a workgroup is at most 256 invocations, and $x by $y is ${x * y}.');
    }
    return (x, y);
  }

  /// The optional `f3dmat <version>` line ahead of `material`.
  ///
  /// **Absent reads as version 1**, because every `.f3dmat` written before the
  /// header existed is a version 1 file and has to keep compiling (decision 8
  /// of `tasks/1.0-stability.md`). Every version up to
  /// [materialLanguageVersion] is read: a later one that changes what a
  /// construct means is parsed the old way when the file says it is older.
  /// Only the future is refused, naming the version that reads it.
  ///
  /// Mutation: accept any number here and a material written for a newer
  /// language compiles to whatever this build thinks its words mean.
  int parseVersion() {
    final header = current;
    if (!takeWordIf('f3dmat')) return 1;
    final number = take('number', 'the language version after "f3dmat"');
    final value = number.number!;
    if (value != value.truncateToDouble() || value < 1) {
      fail(
        '"${number.text}" is not a language version: write a whole number '
        'from 1, as in "f3dmat 1".',
        number,
      );
    }
    final version = value.toInt();
    if (version > materialLanguageVersion) {
      fail(
        'this material is written in material language version $version and '
        'this build reads up to $materialLanguageVersion. Update flutter3d '
        'to a release that reads version $version.',
        header,
      );
    }
    return version;
  }

  void parseParameter({bool uniform = false}) {
    final type = parseType();
    if (!type.isNumeric) {
      fail(
        'a parameter is a number or a vector; a texture is declared with '
        '"texture".',
      );
    }
    final nameToken = take('name', 'the parameter\'s name');
    checkFreeName(nameToken);
    // A uniform reaches the shader under its own name, as a member of the
    // block — `P8` — so the names GLSL and the emitter keep are closed to it,
    // as they are to a `let`. A `param` is folded and never written.
    if (uniform &&
        (_reservedNames.contains(nameToken.text) ||
            nameToken.text.startsWith('gl_'))) {
      fail(
        '"${nameToken.text}" is a name the generated shader already uses, and '
        'a uniform is written into it under its own name.',
        nameToken,
      );
    }
    take(
      '=',
      '"=" and a default value — a parameter without one is a '
          'parameter a variant can forget to set',
    );
    final value = parseConstant(type);
    take(';', '";" after the parameter');
    parameters.add(
      MaterialParameter(nameToken.text, type, value, uniform: uniform),
    );
  }

  void parseTexture() {
    final nameToken = take('name', 'the slot\'s name');
    checkFreeName(nameToken);
    take('=', '"=" and the engine binding this slot reads');
    final binding = take('name', 'the engine binding\'s name');
    if (kind != MaterialStageKind.surface) {
      // A full-screen stage or a kernel is bound by whoever draws it, by
      // the names it declares — `FullscreenEffect.textures` — so the slot
      // is the author's to name, short of the names the stage already uses.
      if (_reservedNames.contains(binding.text) ||
          _version2ReservedNames.contains(binding.text) ||
          binding.text.startsWith('gl_') ||
          binding.text.startsWith('f3d_')) {
        fail(
          '"${binding.text}" is a name the generated stage already uses; '
          'bind the texture under another.',
          binding,
        );
      }
      if (textures.any((slot) => slot.bindingName == binding.text)) {
        fail('"${binding.text}" is bound twice.', binding);
      }
    } else if (!materialTextureBindings.contains(binding.text)) {
      fail(
        '"${binding.text}" is not a texture this engine binds. It binds '
        '${materialTextureBindings.join(', ')} — a material cannot introduce '
        'a slot, because the renderer binds by name and a name it does not '
        'know reaches the GPU as a missing sampler.',
        binding,
      );
    }
    take(';', '";" after the texture');
    textures.add(MaterialTextureSlot(nameToken.text, binding.text));
  }

  /// The inputs a name may not take: every one the source could read
  /// somewhere, for a declaration, and the body's own for a `let`.
  ///
  /// A version 1 file keeps the set it always had — the surface's, the
  /// light's and `lit` — so a name it bound then binds now.
  List<MaterialInput> takenInputs() => switch (kind) {
    MaterialStageKind.fullscreen => materialFullscreenInputs,
    MaterialStageKind.compute => materialComputeInputs,
    _ => <MaterialInput>[
      ...materialInputs,
      ...materialLightInputs,
      materialLitInput,
      if (version >= 2)
        ...switch (block) {
          null => _surfaceVersion2Inputs,
          final body => body.inputs,
        },
    ],
  };

  /// A name may not shadow an input, a builtin or an earlier declaration.
  ///
  /// GLSL would allow some of this and the result is a material whose author
  /// thinks they are reading the surface normal and is reading their own
  /// variable — a bug that looks like the lighting being wrong.
  void checkFreeName(_Token token) {
    final name = token.text;
    for (final input in takenInputs()) {
      if (input.name == name) {
        fail(
          kind == MaterialStageKind.surface
              ? '"$name" is one of the surface inputs.'
              : '"$name" is one of the inputs.',
          token,
        );
      }
    }
    if (kind == MaterialStageKind.fullscreen && name == 'scene') {
      fail('"scene" is the picture a full-screen stage draws over.', token);
    }
    if (MaterialBuiltin.byName(name) != null || name == 'sample') {
      fail('"$name" is a builtin function.', token);
    }
    if (MaterialType.numeric.values.any((t) => t.name == name)) {
      fail('"$name" is a type.', token);
    }
    for (final parameter in parameters) {
      if (parameter.name == name) fail('"$name" is declared twice.', token);
    }
    for (final slot in textures) {
      if (slot.name == name) fail('"$name" is declared twice.', token);
    }
    if (locals.containsKey(name)) {
      fail('"$name" is already bound in this body.', token);
    }
  }

  MaterialType parseType() {
    final token = take('name', 'a type');
    for (final type in MaterialType.numeric.values) {
      if (type.name == token.text) return type;
    }
    fail(
      '"${token.text}" is not a type: float, vec2, vec3 and vec4 are.',
      token,
    );
  }

  /// A parameter's default: a literal, or a constructor of literals.
  List<double> parseConstant(MaterialType type) {
    final expression = parseExpression();
    if (expression is! MaterialConstant) {
      fail('a parameter\'s default has to be a constant.');
    }
    if (expression.type != type) {
      fail(
        'the default is a ${expression.type}, and the parameter is a $type.',
      );
    }
    return expression.value;
  }

  /// One body — [body] says which, what it reads and what it returns.
  ///
  /// Each has its own locals: they are functions of their own in the
  /// shader, or a stage of their own.
  List<MaterialStatement> parseBody(_Block body) {
    final what = body.what;
    take('{', '"{" after "${body.opening}"');
    locals.clear();
    outputs.clear();
    block = body;
    final statements = <MaterialStatement>[];
    while (!takeIf('}')) {
      if (current.kind == 'end') fail('the $what is never closed.');
      if (takeWordIf('let')) {
        final nameToken = take('name', 'the name being bound');
        checkFreeName(nameToken);
        // Only a `let` is written into the shader under its own name; a
        // parameter is folded to a number and a slot to its binding.
        final name = nameToken.text;
        if (_reservedNames.contains(name) ||
            name.startsWith('gl_') ||
            (version >= 2 &&
                (name.startsWith('f3d_') ||
                    _version2ReservedNames.contains(name))) ||
            (body.isVertex && _vertexReservedNames.contains(name))) {
          fail(
            '"$name" is a name the generated shader already uses — GLSL, '
            '`surface.glsl` or the emitter itself — so a binding of it would '
            'not compile, or would quietly replace what the engine reads.',
            nameToken,
          );
        }
        take('=', '"=" after the name');
        final value = parseExpression();
        if (!value.type.isNumeric) {
          fail('a "let" binds a number or a vector, not a ${value.type}.');
        }
        take(';', '";" after the binding');
        locals[nameToken.text] = value.type;
        statements.add(MaterialLet(nameToken.text, value));
      } else if (body.isVertex && takeWordIf('out')) {
        statements.add(parseOutput());
      } else if (!body.isVertex && takeWordIf('return')) {
        final value = parseExpression();
        if (value.type != body.returns) {
          fail(switch (body.opening) {
            'light' =>
              'a light block returns a vec3 — how the surface answers this '
                  'one light, which the engine multiplies by its radiance, '
                  'n·l and shadow — and this one returns a ${value.type}.',
            'ambient' =>
              'an ambient block returns a vec3 — the light the surface '
                  'takes from its surroundings — and this one returns a '
                  '${value.type}.',
            'composite' =>
              'a composite block returns a vec3 — the surface\'s light, '
                  'added up, which the fragment body reads as "lit" — and '
                  'this one returns a ${value.type}.',
            'kernel' =>
              'a kernel returns a vec4 — the texel it writes — and this one '
                  'returns a ${value.type}.',
            _ when kind == MaterialStageKind.fullscreen =>
              'a full-screen stage returns a vec4 — the picture\'s colour '
                  'and alpha — and this one returns a ${value.type}.',
            _ =>
              'a fragment body returns a vec4 — rgb the light the surface '
                  'emits, a its opacity — and this one returns a '
                  '${value.type}.',
          });
        }
        take(';', '";" after the returned value');
        statements.add(MaterialReturn(value));
        if (current.kind != '}') {
          fail('nothing follows the return in a $what.');
        }
      } else {
        fail(
          body.isVertex
              ? '"${current.text}" is not a statement: a vertex block is '
                    '"let" bindings and "out" outputs.'
              : '"${current.text}" is not a statement: a $what is "let" '
                    'bindings and one "return".',
        );
      }
    }
    if (body.isVertex) {
      if (outputs.isEmpty) {
        fail(
          'the vertex block writes nothing: give it an "out" — position, '
          'world or normal — or leave the block out and keep the engine\'s '
          'vertex stage.',
        );
      }
    } else if (statements.isEmpty || statements.last is! MaterialReturn) {
      fail('the $what has no "return".');
    }
    block = null;
    return statements;
  }

  /// `out name = value;` in a `vertex` block — version 2.
  MaterialOutput parseOutput() {
    final nameToken = take('name', 'the output\'s name');
    final name = nameToken.text;
    final output =
        materialVertexOutputs.where((o) => o.name == name).firstOrNull ??
        fail(
          '"$name" is not an output: a vertex block writes '
          '${materialVertexOutputs.map((o) => o.name).join(', ')}.',
          nameToken,
        );
    if (!outputs.add(name)) fail('"$name" is written twice.', nameToken);
    if (outputs.contains('position') && outputs.contains('world')) {
      fail(
        'a vertex block writes "position", before the model transform, or '
        '"world", after it — not both.',
        nameToken,
      );
    }
    take('=', '"=" after the output');
    final value = parseExpression();
    if (value.type != output.type) {
      fail('"$name" is a ${output.type}, and this is a ${value.type}.');
    }
    take(';', '";" after the output');
    return MaterialOutput(output, value);
  }

  // Expressions, by precedence: sum over product over unary over postfix.

  MaterialExpression parseExpression() {
    var left = parseProduct();
    while (current.kind == '+' || current.kind == '-') {
      final op = take(current.kind, 'an operator');
      final right = parseProduct();
      left = binary(op, left, right);
    }
    return left;
  }

  MaterialExpression parseProduct() {
    var left = parseUnary();
    while (current.kind == '*' || current.kind == '/') {
      final op = take(current.kind, 'an operator');
      final right = parseUnary();
      left = binary(op, left, right);
    }
    return left;
  }

  MaterialExpression parseUnary() {
    if (current.kind == '-') {
      final token = take('-', '"-"');
      final operand = parseUnary();
      if (!operand.type.isNumeric) {
        fail('a ${operand.type} cannot be negated.', token);
      }
      if (operand is MaterialConstant) {
        return MaterialConstant(<double>[
          for (final component in operand.value) -component,
        ], operand.type);
      }
      return MaterialNegate(operand);
    }
    return parsePostfix();
  }

  MaterialExpression parsePostfix() {
    var value = parsePrimary();
    while (takeIf('.')) {
      final field = take('name', 'a component after "."');
      value = swizzle(value, field);
    }
    return value;
  }

  MaterialExpression parsePrimary() {
    if (takeIf('(')) {
      final inner = parseExpression();
      take(')', '")"');
      return inner;
    }
    if (current.kind == 'number') {
      final token = take('number', 'a number');
      return MaterialConstant(<double>[token.number!], MaterialType.float);
    }
    if (current.kind != 'name') {
      fail('expected a value, found "${current.text}".');
    }

    final token = take('name', 'a value');
    final name = token.text;

    // A constructor.
    for (final type in MaterialType.numeric.values) {
      if (type.name == name) return construct(type, token);
    }
    if (name == 'sample') return sampleCall(token);
    final builtin = MaterialBuiltin.byName(name);
    if (builtin != null) return call(builtin, token);

    final local = locals[name];
    if (local != null) return MaterialLocalRef(name, local);
    final parameter = parameterNamed(name);
    // Carried as a reference and folded by `specializeMaterial`, so that one
    // parse serves every variant.
    if (parameter != null) return MaterialParamRef(parameter);
    // Outside a body — a parameter's default — names resolve as the main
    // body's would, and `parseConstant` then says a default is a constant.
    final body =
        block ??
        switch (kind) {
          MaterialStageKind.fullscreen => fullscreenBlock,
          MaterialStageKind.compute => kernelBlock,
          _ => fragmentBlock,
        };
    for (final input in body.inputs) {
      if (input.name == name) {
        inputsUsed.add(name);
        if (name == 'sceneDepth' || name == 'scenePosition') sceneAt ??= token;
        return MaterialInputRef(input);
      }
    }
    final surface = kind == MaterialStageKind.surface;
    if (surface && materialLightInputs.any((i) => i.name == name)) {
      fail(
        '"$name" is read of one light, in the "light" block; the '
        'fragment body sees them gathered, as "lit".',
        token,
      );
    }
    if (surface && name == materialLitInput.name) {
      if (inLight) {
        fail(
          '"lit" is every light gathered through this block, so the block '
          'cannot read it; the fragment body does.',
          token,
        );
      }
      if (!identical(body, fragmentBlock)) {
        fail(
          '"lit" is what the light, ambient and composite blocks add up, so '
          'the ${body.what} cannot read it; the fragment body does.',
          token,
        );
      }
      litAt ??= token;
      inputsUsed.add(name);
      return MaterialInputRef(materialLitInput);
    }
    if (textureNamed(name) != null) {
      fail('"$name" is a texture; it is read with sample($name, uv).', token);
    }
    // An input of another body: where it is read, rather than "not bound",
    // which would send an author looking for a declaration.
    if (surface) {
      for (final (other, inputs) in <(String, List<MaterialInput>)>[
        ('fragment body', materialSceneInputs),
        ('vertex block', materialVertexInputs),
        ('ambient block', materialAmbientInputs),
        ('composite block', materialCompositeInputs),
        ('fragment body', materialInputs),
      ]) {
        if (!inputs.any((input) => input.name == name)) continue;
        if (version < 2) {
          fail(
            '"$name" is read from material language version 2: open the '
            'file with "f3dmat 2".',
            token,
          );
        }
        fail('"$name" is read in the $other, not in the ${body.what}.', token);
      }
    }
    fail('"$name" is not bound here.', token);
  }

  MaterialParameter? parameterNamed(String name) {
    for (final parameter in parameters) {
      if (parameter.name == name) return parameter;
    }
    return null;
  }

  MaterialTextureSlot? textureNamed(String name) {
    for (final slot in textures) {
      if (slot.name == name) return slot;
    }
    return null;
  }

  List<MaterialExpression> arguments() {
    take('(', '"(" and the arguments');
    final arguments = <MaterialExpression>[];
    if (!takeIf(')')) {
      do {
        arguments.add(parseExpression());
      } while (takeIf(','));
      take(')', '")" after the arguments');
    }
    return arguments;
  }

  MaterialExpression construct(MaterialType type, _Token token) {
    final parts = arguments();
    var components = 0;
    for (final part in parts) {
      if (!part.type.isNumeric) {
        fail('a ${part.type} is not a number and cannot go in a $type.', token);
      }
      components += part.type.components;
    }
    // GLSL's own rule for the one-argument case: `vec3(1.0)` is every
    // component. Anything else has to add up exactly.
    if (parts.length == 1 && parts.single.type == MaterialType.float) {
      final only = parts.single;
      if (only is MaterialConstant) {
        return MaterialConstant(
          List<double>.filled(type.components, only.value.single),
          type,
        );
      }
      return MaterialConstruct(
        List<MaterialExpression>.filled(type.components, only),
        type,
      );
    }
    if (components != type.components) {
      fail(
        'a $type takes ${type.components} components and these add up to '
        '$components.',
        token,
      );
    }
    if (parts.every((p) => p is MaterialConstant)) {
      return MaterialConstant(<double>[
        for (final part in parts) ...(part as MaterialConstant).value,
      ], type);
    }
    return MaterialConstruct(parts, type);
  }

  MaterialExpression sampleCall(_Token token) {
    final body = block;
    if (body != null && !body.samples) {
      fail(
        'a ${body.what} cannot sample a texture: the vertex stage binds '
        'none, and a displacement read from a map is a fragment\'s work or '
        'a uniform\'s.',
        token,
      );
    }
    take('(', '"(" after sample');
    final slotToken = take('name', 'the texture slot');
    final slot = textureNamed(slotToken.text);
    if (slot == null) {
      fail(
        '"${slotToken.text}" is not a texture this material declares.',
        slotToken,
      );
    }
    sampled.add(slot.name);
    take(',', '"," and the coordinates');
    final uv = parseExpression();
    if (uv.type != MaterialType.vec2) {
      fail('sample takes a vec2 of coordinates, not a ${uv.type}.', token);
    }
    take(')', '")" after sample');
    return MaterialSample(slot, uv);
  }

  MaterialExpression call(MaterialBuiltin builtin, _Token token) {
    final parts = arguments();
    if (parts.length != builtin.arity) {
      fail(
        '${builtin.name} takes ${builtin.arity} arguments and was given '
        '${parts.length}.',
        token,
      );
    }
    var width = 1;
    for (final part in parts) {
      if (!part.type.isNumeric) {
        fail('${builtin.name} takes numbers, not a ${part.type}.', token);
      }
      if (part.type.components > width) width = part.type.components;
    }
    for (final part in parts) {
      final components = part.type.components;
      if (components != width && !(builtin.componentWise && components == 1)) {
        fail(
          '${builtin.name} was given a ${part.type} beside a '
          '${MaterialType.numeric[width]}.',
          token,
        );
      }
    }
    final resultWidth = builtin.resultComponents ?? width;
    return MaterialCall(builtin, parts, MaterialType.numeric[resultWidth]!);
  }

  MaterialExpression binary(
    _Token op,
    MaterialExpression left,
    MaterialExpression right,
  ) {
    if (!left.type.isNumeric || !right.type.isNumeric) {
      fail('"${op.text}" works on numbers, not on a texture.', op);
    }
    final a = left.type.components;
    final b = right.type.components;
    if (a != b && a != 1 && b != 1) {
      fail(
        'a ${left.type} and a ${right.type} cannot be combined with '
        '"${op.text}".',
        op,
      );
    }
    return MaterialBinary(
      op.text,
      left,
      right,
      MaterialType.numeric[a > b ? a : b]!,
    );
  }

  MaterialExpression swizzle(MaterialExpression target, _Token field) {
    if (!target.type.isNumeric) {
      fail('a ${target.type} has no components.', field);
    }
    const sets = <String>['xyzw', 'rgba'];
    final indices = <int>[];
    String? chosen;
    for (final letter in field.text.split('')) {
      final set = sets.firstWhere((s) => s.contains(letter), orElse: () => '');
      if (set.isEmpty) {
        fail(
          '"$letter" is not a component: xyzw and rgba are, and one '
          'swizzle does not mix the two.',
          field,
        );
      }
      // GLSL refuses `.xg` too, and for the reason it reads badly rather than
      // for one about the hardware: two names for the same component in one
      // expression is somebody having lost track of which vector they are in.
      chosen ??= set;
      if (set != chosen) {
        fail('"${field.text}" mixes xyzw with rgba.', field);
      }
      final index = set.indexOf(letter);
      if (index >= target.type.components) {
        fail('a ${target.type} has no "$letter".', field);
      }
      indices.add(index);
    }
    if (indices.isEmpty || indices.length > 4) {
      fail('"${field.text}" is not one to four components.', field);
    }
    final type = MaterialType.numeric[indices.length]!;
    if (target is MaterialConstant) {
      return MaterialConstant(<double>[
        for (final index in indices) target.value[index],
      ], type);
    }
    return MaterialSwizzle(target, indices, type);
  }
}
