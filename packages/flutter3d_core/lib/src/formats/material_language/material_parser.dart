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
/// `size` and `uv` and returns the texel it writes: the short form of a
/// kernel, which `lowerMaterialCompute` writes in the kernel language
/// (`ComputeKernel`) for every device that computes. The site's material
/// language page is the reference, with what each backend does with each.
///
/// The `light` block runs once per light inside the engine's light loop and
/// returns how the surface answers it, which the engine multiplies by the
/// light's radiance, its `n·l` and its shadow; it reads the light through
/// `lightDir`, `halfDir`, `nDotL`, `nDotH` and `vDotH`. The fragment body
/// reads the result as `lit` — see `materialLitInput` for what that adds up.
///
/// **The vocabulary is GLSL's, and that is the whole design.** `clamp`, `mix`,
/// `pow`, the swizzles and the broadcasting rules all mean what they mean in
/// GLSL, because the emitted shader has to read like the source for anybody
/// debugging the pair — and because a language that invented its own `mix`
/// would have to explain how it differs from the one every author already
/// knows. What is *not* GLSL is everything a material must not be allowed to
/// do: write to a global, loop, or take a name the engine's stages use.
/// Those are refusals with a sentence attached rather than omissions. A
/// block or a texture of the material's own (version 2) is declared, not
/// written as GLSL — `uniform(Hair) …`, `texture fur;` — so it lands in the
/// slot table every backend binds by (D21).
///
/// **Typed on the way in, not on the way out.** Every expression node carries
/// its type because the parser worked it out; an emitter that had to infer
/// types would be a second type checker, and the two would disagree about
/// something like `vec3 * float` on one backend only.
///
/// **The expressions are the engine's expression language.** This parser
/// extends `flutter3d_foundation`'s [ExpressionParser]: it reads the
/// declarations and the blocks, and every expression in them is read and
/// typed by the base class, under [materialSyntax] (the tokens versions 1
/// and 2 know, no units, no comparisons) and with [materialBuiltins], so a
/// file of either version reads exactly as it did before the language was
/// lifted out.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        Expression,
        ExpressionBuiltin,
        ExpressionConstant,
        ExpressionScope,
        ExpressionSyntax,
        ExpressionSyntaxException,
        ExpressionType;
import 'package:flutter3d_foundation/internal.dart'
    show ExpressionParser, ExpressionToken, tokenizeExpression;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException, FormatSpec;
import 'package:flutter3d_shaders/kernel.dart' show WorkgroupSize;

import 'material_ast.dart';
import 'material_words.dart';

/// The tokens the material language reads: the expression language's
/// arithmetic, its own `{ } = ;`, and no units, exponents or comparisons,
/// which no version of it has had.
///
/// `:` and `>` are version 3's, for an `updates` block's `2: rename a -> b`;
/// in an expression they are refused as they were.
const ExpressionSyntax materialSyntax = ExpressionSyntax(
  units: false,
  exponents: false,
  logic: false,
  punctuation: '{}=;:>',
);

/// What the engine binds, and therefore the only names a `texture` declaration
/// with `=` may point at.
///
/// A material cannot invent a name for one of these: the renderer binds
/// textures by these names and a name it does not know reaches the GPU as a
/// missing sampler, which on Metal is a crash rather than a black texture.
/// The list is short because the set really is that small — `surface.glsl`
/// declares them. A texture of the material's own is declared without `=`
/// (version 2) and is a slot in its `MaterialSlotTable` instead.
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
///
/// **Version 3** (1.0) gives a material a version of its own and the
/// updates that carry an older instance's values to it:
///
/// ```text
/// f3dmat 3
/// material Hatch version 3 {
///   uniform vec3 inkColor = vec3(0.1);
///   uniform float roughness = 0.5;
///   updates {
///     2: rename ink -> inkColor;
///     3: scale roughness 0.5;
///   }
///   ...
/// }
/// ```
///
/// An update is `rename a -> b`, `scale a <factor>` or `remove a`, under
/// the version it leads to, from 2 to the material's own;
/// `MaterialProgram.lift` applies them. Everything else reads as version 2.
const int materialLanguageVersion = 3;

/// The material language version that adds the `state`, `vertex`,
/// `ambient` and `composite` blocks, the `fullscreen` and `compute` kinds,
/// the scene inputs, and a material's own blocks and textures.
const int materialLanguageStagesVersion = 2;

/// The material language version that gives a material a version of its
/// own and an `updates` block.
const int materialLanguageUpdatesVersion = 3;

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
  /// A refusal saying [message] at [line] and [column] of the source.
  const MaterialSyntaxException(this.message, this.line, this.column);

  @override
  final String message;

  /// The source line where reading failed, counted from one.
  final int line;

  /// The column on [line] where reading failed, counted from one.
  final int column;

  @override
  String toString() => 'MaterialSyntaxException at $line:$column: $message';
}

/// Reads [source] as one material.
///
/// **A `.f3dmat` holds one block of the material language, first**, and
/// after it only `compute` blocks, which are the kernel language's
/// (`ComputeKernel.parseAll` reads them, and skips the first block). The
/// optional `f3dmat <N>` line, and the kernel language's `kernel <N>` after
/// it, come before the first block. Anything else after it — a second
/// `material`, a `fullscreen`, a word nobody reads — is refused with where
/// it starts, rather than dropped without a word.
MaterialProgram parseMaterial(String source) {
  // The whole source where the first block never closes, which the parser
  // then refuses in its own words.
  final end = _blockEnd(source) ?? source.length;
  final List<ExpressionToken> tokens;
  try {
    tokens = tokenizeExpression(
      source.substring(0, end),
      syntax: materialSyntax,
    );
  } on ExpressionSyntaxException catch (error, stack) {
    Error.throwWithStackTrace(
      MaterialSyntaxException(error.message, error.line, error.column),
      stack,
    );
  }
  final program = _Parser(tokens).parseMaterial();
  _checkAfterFirstBlock(source, end);
  return program;
}

/// One past the brace that closes the first block [source] opens from
/// [from], or null where none closes. `//` comments are skipped, as the
/// tokenizer skips them.
int? _blockEnd(String source, [int from = 0]) {
  var depth = 0;
  var at = from;
  while (at < source.length) {
    if (source.startsWith('//', at)) {
      final newline = source.indexOf('\n', at);
      if (newline < 0) return null;
      at = newline;
      continue;
    }
    switch (source[at]) {
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) return at + 1;
    }
    at++;
  }
  return null;
}

/// Holds what follows the first block of [source], from [from], to the one
/// thing a `.f3dmat` may hold there: kernel-language `compute` blocks, each
/// `compute <Name> { … }`, whose insides are the kernel parser's to read.
void _checkAfterFirstBlock(String source, int from) {
  Never refuse(int at, String message) {
    final before = source.substring(0, at);
    final line = '\n'.allMatches(before).length + 1;
    throw MaterialSyntaxException(message, line, at - before.lastIndexOf('\n'));
  }

  var at = from;
  void skipSpace() {
    while (at < source.length) {
      if (source.startsWith('//', at)) {
        final newline = source.indexOf('\n', at);
        at = newline < 0 ? source.length : newline;
      } else if (source[at].trim().isEmpty) {
        at++;
      } else {
        return;
      }
    }
  }

  String word() {
    final match = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(source, at);
    if (match == null) return '';
    at = match.end;
    return match[0]!;
  }

  while (true) {
    skipSpace();
    if (at >= source.length) return;
    final start = at;
    final opening = word();
    if (opening != 'compute') {
      final what = opening.isEmpty ? source[start] : opening;
      refuse(
        start,
        opening == 'material' || opening == 'fullscreen'
            ? 'a .f3dmat holds one material, first, and this "$opening" is '
                  'a second: put it in a file of its own.'
            : '"$what" cannot follow the material: after its first block a '
                  '.f3dmat holds only "compute" blocks of the kernel '
                  'language.',
      );
    }
    skipSpace();
    if (word().isEmpty) {
      refuse(at, 'a "compute" block after the material names its kernel.');
    }
    skipSpace();
    if (at >= source.length || source[at] != '{') {
      refuse(at, '"{" after the kernel\'s name.');
    }
    at =
        _blockEnd(source, at) ??
        refuse(start, 'the "compute" block is never closed with "}".');
  }
}

/// Names a `let` or a `uniform` would collide with once
/// `emitMaterialFragment` writes it into `main()` beside what is already
/// there, in every version.
///
/// **A local is emitted under its own name**, so that the shader reads like
/// the source, and that makes these its namespace too: the emitter's own
/// locals and `surface.glsl`'s names ([materialEmitterNames]), the samplers
/// `sample(…)` is written as, and every keyword and reserved word of GLSL
/// 4.60 and GLSL ES 3.00 ([materialGlslWords]).
const Set<String> _reservedNames = <String>{
  ...materialEmitterNames,
  ...materialTextureBindings,
  ...materialGlslWords,
};

/// Every uniform block one of the engine's own shaders declared at 1.0.0,
/// which a material's block cannot be named: **frozen**, not read off the
/// live table, so a block the engine adds in a minor takes no name from a
/// material that built before. A block the engine adds after 1.0.0 is named
/// in [isEngineBlockName]'s reserved shape instead, which a material's
/// block was never allowed (`material_language_versions_test.dart` holds
/// the engine to that).
const Set<String> materialReservedBlockNames = <String>{
  'AccumulateInfo',
  'BloomInfo',
  'CameraVelocityInfo',
  'CausticInfo',
  'CompositeInfo',
  'ContactShadowInfo',
  'ContactShadowResolveInfo',
  'ContributorLightInfo',
  'ConvolveInfo',
  'DecalInfo',
  'DepthPyramidInfo',
  'DofInfo',
  'DofTileInfo',
  'EasuInfo',
  'EvsmFilterInfo',
  'FieldDecayInfo',
  'FogInfo',
  'FogUpsampleInfo',
  'FragCoordInfo',
  'FragInfo',
  'FrameInfo',
  'FxaaInfo',
  'HighContrastInfo',
  'IdInfo',
  'IrradianceInfo',
  'LayerInfo',
  'LensFlareInfo',
  'LightListInfo',
  'LineInfo',
  'LocalExposureBlurInfo',
  'LocalExposureInfo',
  'LuminanceInfo',
  'MaskInfo',
  'MaterialParams',
  'MorphInfo',
  'MorphInstanceInfo',
  'MotionBlurInfo',
  'NeighborMaxInfo',
  'NoiseInfo',
  'OutlineMaskInfo',
  'ParticleInfo',
  'ParticleMeshInfo',
  'PlanarReflectionInfo',
  'PointShadow',
  'PredrawInfo',
  'PrevFrameInfo',
  'ProbeInfo',
  'ReactiveInfo',
  'ReflectionInfo',
  'RenderTextureInfo',
  'SceneCopyInfo',
  'ShadeInfo',
  'ShadowCopyInfo',
  'ShadowLight',
  'ShaftInfo',
  'SixWayInfo',
  'SkinInfo',
  'SmaaInfo',
  'SoftParticleInfo',
  'SplatHashInfo',
  'SsaoBlurInfo',
  'SsaoInfo',
  'TemporalInfo',
  'TileMaxInfo',
  'TransmittanceInfo',
  'VelocityInfo',
  'VolumeFogInfo',
};

/// Whether [name] is one of the engine's block names, or in the shape the
/// engine keeps for the blocks it adds later: `F3d…` or `…Info`.
bool isEngineBlockName(String name) =>
    materialReservedBlockNames.contains(name) ||
    name.startsWith('F3d') ||
    name.endsWith('Info');

/// One body of a source — which block it is, what it reads and what it
/// returns.
final class _Block {
  const _Block(
    this.what,
    this.opening, {
    required this.inputs,
    this.returns,
    this.outputs = const <MaterialInput>[],
    this.samples = true,
  });

  /// How a message names it: "fragment body", "light block".
  final String what;

  /// The word that opens it, for "{" after it.
  final String opening;

  /// The inputs it reads by name.
  final List<MaterialInput> inputs;

  /// The type its `return` must have; null for a `vertex` or a `surface`
  /// block, which has [outputs] instead.
  final ExpressionType? returns;

  /// What its `out` statements may write: a `vertex` block's or a
  /// `surface` block's.
  final List<MaterialInput> outputs;

  /// Whether `sample(...)` may be called in it.
  final bool samples;

  /// Whether it is a block of `out` statements rather than one `return`.
  bool get writes => returns == null;

  /// Whether it is the `vertex` block, whose names are the vertex stage's.
  bool get isVertex => opening == 'vertex';
}

/// Every input a version 2 surface names in one block or another, for the
/// rule that a declaration may not take one's name.
const List<MaterialInput> _surfaceVersion2Inputs = <MaterialInput>[
  ...materialSceneInputs,
  ...materialVertexInputs,
  ...materialAmbientInputs,
  ...materialCompositeInputs,
];

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// The material language over the expression language's parser: the
/// declarations and blocks are read here, every expression by the base
/// class, with a material's names resolved by [resolveName] and `sample`
/// read by [parseSpecialCall].
final class _Parser extends ExpressionParser {
  _Parser(super.tokens)
    : super(
        scope: const ExpressionScope(builtins: materialBuiltins),
        syntax: materialSyntax,
      );

  final List<MaterialParameter> parameters = <MaterialParameter>[];
  final Map<String, String> lightTypes = <String, String>{};
  final List<MaterialTextureSlot> textures = <MaterialTextureSlot>[];
  final Map<String, ExpressionType> locals = <String, ExpressionType>{};

  /// The language version the source declared — 1 without a header.
  int version = materialLanguageFirstVersion;

  /// What the source is, read after the version.
  MaterialStageKind kind = MaterialStageKind.surface;

  /// The body being read, or null between bodies.
  _Block? block;

  /// Whether the body being read is the `light` block — `P8` — the
  /// standard model's or a material's own.
  bool get inLight => block?.opening == 'light';

  /// The engine's model the material is lit by — `lighting standard;`,
  /// version 3 — or null for a material that lights itself.
  String? lighting;

  /// Whether the material is lit by the standard model.
  bool get standard => lighting == materialStandardLighting;

  /// Where the fragment body first read `lit`, to point at when the material
  /// turns out to have no `light` block to gather it.
  ExpressionToken? litAt;

  /// Where a body first read the scene behind it, to point at when the
  /// material turns out not to be translucent.
  ExpressionToken? sceneAt;
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
      if (version >= materialLanguageStagesVersion) ...materialSceneInputs,
    ],
    returns: ExpressionType.vec4,
  );
  final _Block lightBlock = const _Block(
    'light block',
    'light',
    inputs: <MaterialInput>[...materialInputs, ...materialLightInputs],
    returns: ExpressionType.vec3,
  );
  final _Block ambientBlock = const _Block(
    'ambient block',
    'ambient',
    inputs: <MaterialInput>[...materialInputs, ...materialAmbientInputs],
    returns: ExpressionType.vec3,
  );
  final _Block compositeBlock = const _Block(
    'composite block',
    'composite',
    inputs: <MaterialInput>[...materialInputs, ...materialCompositeInputs],
    returns: ExpressionType.vec3,
  );
  final _Block vertexBlock = const _Block(
    'vertex block',
    'vertex',
    inputs: materialVertexInputs,
    outputs: materialVertexOutputs,
    samples: false,
  );

  /// Version 3, beside `lighting standard`: the standard model's answer to
  /// one light, read as `standard`.
  final _Block standardLightBlock = const _Block(
    'light block',
    'light',
    inputs: <MaterialInput>[
      ...materialInputs,
      ...materialLightInputs,
      materialStandardLightInput,
    ],
    returns: ExpressionType.vec3,
  );

  /// Version 3, beside `lighting standard`: the surface the model lights,
  /// rewritten.
  final _Block surfaceBlock = const _Block(
    'surface block',
    'surface',
    inputs: materialInputs,
    outputs: materialSurfaceOutputs,
  );
  final _Block fullscreenBlock = const _Block(
    'full-screen stage',
    'fragment',
    inputs: materialFullscreenInputs,
    returns: ExpressionType.vec4,
  );
  final _Block kernelBlock = const _Block(
    'kernel',
    'kernel',
    inputs: materialComputeInputs,
    returns: ExpressionType.vec4,
  );

  @override
  Never fail(String message, {ExpressionToken? where}) {
    final token = where ?? current;
    throw MaterialSyntaxException(message, token.line, token.column);
  }

  MaterialProgram parseMaterial() {
    version = parseVersion();
    // The kernel language's version line, which a file holding kernels
    // beside its material writes after its own; the kernel parser reads it.
    if (current.kind == 'name' &&
        current.text == 'kernel' &&
        tokens[position + 1].kind == 'number') {
      position += 2;
    }
    kind = parseKind();
    final surface = kind == MaterialStageKind.surface;
    final name = expectToken('name', 'the material\'s name').text;
    var materialVersion = firstMaterialVersion;
    if (current.kind == 'name' && current.text == 'version') {
      if (version < materialLanguageUpdatesVersion) {
        fail(
          'a material\'s own version is material language version 3: open '
          'the file with "f3dmat 3".',
        );
      }
      position++;
      materialVersion = wholeNumber(
        'the material\'s version',
        from: firstMaterialVersion,
      );
    }
    expectToken('{', '"{" after the material\'s name');
    final updates = <(ExpressionToken, MaterialUpdate)>[];
    ExpressionToken? updatesAt;
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
    List<MaterialStatement>? surfaceHook;
    var state = MaterialFileState.none;
    var workgroup = const WorkgroupSize(8, 8, 1);
    ExpressionToken? lightAt;
    ExpressionToken? ambientAt;
    ExpressionToken? compositeAt;
    ExpressionToken? stateAt;
    ExpressionToken? workgroupAt;
    ExpressionToken? lightingAt;
    ExpressionToken? fragmentAt;

    /// The body a word opens, read once.
    List<MaterialStatement> once(
      List<MaterialStatement>? already,
      ExpressionToken where,
      String what,
      _Block block,
    ) {
      position++;
      if (already != null) fail('a material has one $what.', where: where);
      return parseBody(block);
    }

    while (!skipIf('}')) {
      if (current.kind == 'end') fail('the material is never closed with "}".');
      final word = current.kind == 'name' ? current.text : '';
      final where = current;
      if (skipWordIf('param')) {
        parseParameter();
      } else if (skipWordIf('uniform')) {
        parseParameter(uniform: true);
      } else if (skipWordIf('texture')) {
        parseTexture();
      } else if (word == 'lighttype' &&
          surface &&
          version < materialLanguageUpdatesVersion) {
        fail(
          '"lighttype" is material language version 3: open the file with '
          '"f3dmat 3".',
        );
      } else if (word == 'lighttype' &&
          surface &&
          version >= materialLanguageUpdatesVersion) {
        position++;
        parseLightType();
      } else if (word == 'lighting' &&
          surface &&
          version < materialLanguageUpdatesVersion) {
        fail(
          '"lighting" is material language version 3: open the file with '
          '"f3dmat 3".',
        );
      } else if (word == 'lighting' && surface) {
        position++;
        if (lightingAt != null) {
          fail('a material is lit one way, said once.', where: where);
        }
        if (body != null ||
            light != null ||
            vertex != null ||
            ambient != null ||
            composite != null ||
            surfaceHook != null) {
          fail(
            '"lighting" says what the blocks after it inject into, so it '
            'comes before them.',
            where: where,
          );
        }
        lightingAt = where;
        final model = expectToken('name', 'the model after "lighting"');
        if (model.text != materialStandardLighting) {
          fail(
            '"${model.text}" is not a model a material can be lit by: '
            '"lighting $materialStandardLighting;" is the engine\'s '
            'metal-rough model, and a material that names none lights '
            'itself.',
            where: model,
          );
        }
        expectToken(';', '";" after the model');
        lighting = model.text;
      } else if (word == 'surface' &&
          surface &&
          version < materialLanguageUpdatesVersion) {
        fail(
          '"surface" is material language version 3: open the file with '
          '"f3dmat 3".',
        );
      } else if (word == 'surface' && surface) {
        if (!standard) {
          fail(
            'the surface block rewrites the surface the standard model '
            'lights: declare "lighting $materialStandardLighting;" first, or '
            'shape the surface in the fragment body.',
            where: where,
          );
        }
        surfaceHook = once(surfaceHook, where, 'surface block', surfaceBlock);
      } else if (word == 'fragment' && kind != MaterialStageKind.compute) {
        fragmentAt ??= where;
        position++;
        if (body != null) fail('a material has one fragment body.');
        body = parseBody(surface ? fragmentBlock : fullscreenBlock);
      } else if (word == 'kernel' && kind == MaterialStageKind.compute) {
        body = once(body, where, 'kernel', kernelBlock);
      } else if (word == 'light' && surface) {
        lightAt = where;
        position++;
        if (light != null) {
          fail('a material has one light block.', where: lightAt);
        }
        light = parseBody(standard ? standardLightBlock : lightBlock);
      } else if (surface &&
          version < materialLanguageStagesVersion &&
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
        position++;
        if (stateAt != null) {
          fail('a material has one state block.', where: where);
        }
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
        position++;
        if (workgroupAt != null) {
          fail('a kernel has one workgroup.', where: where);
        }
        workgroupAt = where;
        workgroup = parseWorkgroup();
      } else if (word == 'updates' &&
          version < materialLanguageUpdatesVersion) {
        fail(
          '"updates" is material language version 3: open the file with '
          '"f3dmat 3".',
        );
      } else if (word == 'updates') {
        position++;
        if (updatesAt != null) {
          fail('a material has one updates block.', where: where);
        }
        updatesAt = where;
        updates.addAll(parseUpdates());
      } else {
        fail(switch (kind) {
          _ when version < materialLanguageStagesVersion =>
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
    // Version 3: the standard model writes the surface itself, and gathers
    // its own environment and every light, so what a material lighting
    // itself says about them has nothing here to say it to.
    if (standard) {
      if (fragmentAt != null) {
        fail(
          'a material lit by the standard model has no fragment body: the '
          'model writes the surface, which a "surface" block rewrites and a '
          '"light" block answers each light of.',
          where: fragmentAt,
        );
      }
      for (final (hook, at) in <(String, ExpressionToken?)>[
        ('ambient', ambientAt),
        ('composite', compositeAt),
      ]) {
        if (at == null) continue;
        fail(
          'the standard model takes its own environment and adds its own '
          'light up, so a material lit by it has no $hook block.',
          where: at,
        );
      }
      if (!state.environment || !state.directional) {
        fail(
          '"environment" and "directional" switch light out of what a '
          'material\'s own light block gathers; the standard model gathers '
          'all of it.',
          where: stateAt,
        );
      }
    }
    if (body == null && !standard) {
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
        where: where,
      );
    }
    if (light != null && litAt == null && !standard) {
      fail(
        'the light block is never read: a fragment body that does not read '
        '"lit" gathers no lights, and the compiled shader would drop the '
        'block and everything the engine binds for it.',
        where: lightAt,
      );
    }
    // The two hooks shape the light a `light` block gathers; without one
    // there is no `lit` for them to shape.
    for (final (hook, where) in <(String, ExpressionToken?)>[
      ('ambient', ambientAt),
      ('composite', compositeAt),
    ]) {
      if (where != null && light == null) {
        fail(
          'the $hook block shapes the light a "light" block gathers, and this '
          'material has none: add one, or leave the $hook block out.',
          where: where,
        );
      }
    }
    if ((!state.environment || !state.directional) && light == null) {
      fail(
        '"environment" and "directional" switch light out of what a "light" '
        'block gathers, and this material has none.',
        where: stateAt,
      );
    }
    if (!state.environment && ambientAt != null) {
      fail(
        'the ambient block is the environment\'s light, and the state block '
        'compiles the environment out with "environment off": keep one or '
        'the other.',
        where: ambientAt,
      );
    }
    if (sceneAt case final where? when !state.isTranslucent && surface) {
      fail(
        '"${where.text}" is the scene behind a translucent surface, and this '
        'material is opaque: give its state block "blend alpha", "blend '
        'additive" or "blend premultiplied". An opaque surface is the scene '
        'it would be reading.',
        where: where,
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
    checkUpdates(name, materialVersion, updates);

    return MaterialProgram(
      name: name,
      version: materialVersion,
      updates: <MaterialUpdate>[for (final (_, update) in updates) update],
      parameters: parameters,
      textures: textures,
      body: body ?? const <MaterialStatement>[],
      light: light,
      vertex: vertex,
      ambient: ambient,
      composite: composite,
      inputsUsed: inputsUsed,
      languageVersion: version,
      kind: kind,
      state: state,
      workgroupSize: workgroup,
      lightTypes: Map<String, String>.unmodifiable(lightTypes),
      lighting: lighting,
      surface: surfaceHook,
    );
  }

  /// `lighttype tube = acme.tube;` — version 3: a name the `light` block
  /// reads as one while it shades a light of that type, and a member of
  /// `MaterialParams` the renderer fills with the type's code.
  void parseLightType() {
    final nameToken = expectToken('name', 'the name the light block reads');
    checkFreeName(nameToken);
    expectToken('=', '"=" after the name');
    final parts = <String>[expectToken('name', 'a light type\'s name').text];
    while (skipIf('.')) {
      parts.add(expectToken('name', 'the rest of the light type\'s name').text);
    }
    expectToken(';', '";" after the light type');
    final type = parts.join('.');
    if (parts.length < 2) {
      fail(
        '"$type" is not a light type of a plugin\'s own: those are named '
        '<pluginId>.<name>, and the engine\'s own four are told apart by '
        'lightKind (0 to 3)',
        where: nameToken,
      );
    }
    lightTypes[nameToken.text] = type;
    // The code, as a member of `MaterialParams` the renderer fills; minus
    // one, which matches no light, where no hook packs the type.
    parameters.add(
      MaterialParameter(
        materialLightTypeMember(nameToken.text),
        ExpressionType.float,
        const <double>[-1],
        uniform: true,
      ),
    );
  }

  /// `material`, `fullscreen` or `compute` — the last two version 2.
  MaterialStageKind parseKind() {
    final token = current;
    for (final candidate in MaterialStageKind.all) {
      if (!skipWordIf(candidate.name)) continue;
      if (candidate != MaterialStageKind.surface &&
          version < materialLanguageStagesVersion) {
        fail(
          '"${candidate.name}" is material language version 2: open the file '
          'with "f3dmat 2".',
          where: token,
        );
      }
      return candidate;
    }
    fail(
      version < materialLanguageStagesVersion
          ? 'a material starts with the word "material".'
          : 'a source starts with "material", "fullscreen" or "compute".',
    );
  }

  /// A `state` block's settings, once each — version 2.
  MaterialFileState parseState() {
    expectToken('{', '"{" after "state"');
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
    ExpressionToken? cutoffAt;
    ExpressionToken? coverageAt;
    ExpressionToken? compareAt;
    ExpressionToken? effectsAt;

    bool onOff(ExpressionToken key) {
      final value = expectToken('name', '"on" or "off" after "${key.text}"');
      return switch (value.text) {
        'on' => true,
        'off' => false,
        _ => fail(
          '"${key.text}" is "on" or "off", not "${value.text}".',
          where: value,
        ),
      };
    }

    while (!skipIf('}')) {
      if (current.kind == 'end') fail('the state block is never closed.');
      final key = expectToken('name', 'a setting');
      if (!seen.add(key.text)) fail('"${key.text}" is set twice.', where: key);
      switch (key.text) {
        case 'blend':
          final value = expectToken('name', 'a blend after "blend"');
          blend =
              MaterialBlend.byName(value.text) ??
              fail(
                '"${value.text}" is not a blend: '
                '${MaterialBlend.all.join(', ')} are.',
                where: value,
              );
        case 'cutoff':
          cutoffAt = key;
          final value = expectToken('number', 'the alpha the mask cuts at');
          cutoff = value.number!;
          if (cutoff < 0 || cutoff > 1) {
            fail('a cutoff is an alpha, from nought to one.', where: value);
          }
        case 'depthWrite':
          depthWrite = onOff(key);
        case 'depthTest':
          depthTest = onOff(key);
        case 'depthCompare':
          compareAt = key;
          final value = expectToken(
            'name',
            'a depth test after "depthCompare"',
          );
          if (!materialDepthCompares.contains(value.text)) {
            fail(
              '"${value.text}" is not a depth test: '
              '${materialDepthCompares.join(', ')} are.',
              where: value,
            );
          }
          depthCompare = value.text;
        case 'alphaToCoverage':
          coverageAt = key;
          alphaToCoverage = onOff(key);
        case 'doubleSided':
          doubleSided = onOff(key);
        case 'depthLayer':
          final negative = skipIf('-');
          final value = expectToken(
            'number',
            'a whole number after "depthLayer"',
          );
          final number = value.number!;
          if (number != number.truncateToDouble() ||
              number > materialDepthLayerLimit) {
            fail(
              'a depth layer is a whole number from '
              '-$materialDepthLayerLimit to $materialDepthLayerLimit.',
              where: value,
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
            where: key,
          );
      }
      expectToken(';', '";" after the setting');
    }

    final masked = blend == MaterialBlend.mask;
    if (cutoffAt != null && !masked) {
      fail(
        'a cutoff is where "blend mask" cuts, and this is not masked.',
        where: cutoffAt,
      );
    }
    if (coverageAt != null && alphaToCoverage! && !masked) {
      fail(
        'alpha to coverage antialiases the edge "blend mask" cuts, and this '
        'is not masked.',
        where: coverageAt,
      );
    }
    if (compareAt != null && depthTest != null) {
      fail(
        '"depthTest" and "depthCompare" both say how the depth is tested: '
        'keep one.',
        where: compareAt,
      );
    }
    if (effectsAt != null && effectsDepth! && !(blend?.translucent ?? false)) {
      fail(
        '"effectsDepth" puts a translucent surface into the depth the '
        'effects read, and an opaque one is there already.',
        where: effectsAt,
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

  /// A whole number token of at least [from], [what] naming it in a
  /// refusal.
  int wholeNumber(String what, {required int from}) {
    final token = expectToken('number', what);
    final value = token.number!;
    if (value != value.truncateToDouble() || value < from) {
      fail(
        '$what is a whole number from $from, not "${token.text}".',
        where: token,
      );
    }
    return value.toInt();
  }

  /// An `updates` block — version 3: `<version>: rename a -> b;`,
  /// `<version>: scale a <factor>;` and `<version>: remove a;`, each with
  /// the token it starts at.
  List<(ExpressionToken, MaterialUpdate)> parseUpdates() {
    expectToken('{', '"{" after "updates"');
    final updates = <(ExpressionToken, MaterialUpdate)>[];
    while (!skipIf('}')) {
      if (current.kind == 'end') fail('the updates block is never closed.');
      final at = current;
      final leadsTo = wholeNumber(
        'an update\'s version',
        from: firstMaterialVersion + 1,
      );
      expectToken(':', '":" after the update\'s version');
      final verb = expectToken('name', 'rename, scale or remove');
      final update = switch (verb.text) {
        'rename' => () {
          final from = expectToken('name', 'the name the parameter had').text;
          expectToken('-', '"->" after the old name');
          expectToken('>', '"->" after the old name');
          final to = expectToken('name', 'the name the parameter has now').text;
          if (from == to) fail('"$from" is renamed to itself.', where: verb);
          return MaterialRenameUpdate(leadsTo, from, to);
        }(),
        'scale' => () {
          final parameter = expectToken('name', 'the parameter to scale').text;
          final negative = skipIf('-');
          final factor = expectToken(
            'number',
            'the factor its value is scaled by',
          );
          return MaterialScaleUpdate(
            leadsTo,
            parameter,
            negative ? -factor.number! : factor.number!,
          );
        }(),
        'remove' => MaterialRemoveUpdate(
          leadsTo,
          expectToken('name', 'the parameter that is removed').text,
        ),
        _ => fail(
          '"${verb.text}" is not an update: rename, scale and remove are.',
          where: verb,
        ),
      };
      expectToken(';', '";" after the update');
      updates.add((at, update));
    }
    return updates;
  }

  /// Every update leads to a version from 2 to the material's own, and a
  /// rename or a scale names, by the name it ends up with, a parameter the
  /// material declares: an update of a parameter nobody has is a typo that
  /// would otherwise carry an instance's value nowhere.
  void checkUpdates(
    String material,
    int materialVersion,
    List<(ExpressionToken, MaterialUpdate)> updates,
  ) {
    final ordered =
        <(int, ExpressionToken, MaterialUpdate)>[
          for (final (index, (at, update)) in updates.indexed)
            (index, at, update),
        ]..sort(
          (a, b) => a.$3.version != b.$3.version
              ? a.$3.version.compareTo(b.$3.version)
              : a.$1.compareTo(b.$1),
        );
    for (final (k, (_, at, update)) in ordered.indexed) {
      if (update.version > materialVersion) {
        fail(
          'an update leads to a version from 2 to the material\'s own, '
          '$materialVersion, and this one leads to ${update.version}: raise '
          'the material\'s version with "material $material version '
          '${update.version}".',
          where: at,
        );
      }
      String? name = switch (update) {
        MaterialRenameUpdate(:final to) => to,
        MaterialScaleUpdate(:final name) => name,
        _ => null,
      };
      final written = name;
      for (final (_, _, later) in ordered.skip(k + 1)) {
        if (name == null) break;
        name = switch (later) {
          MaterialRenameUpdate(:final from, :final to) when from == name => to,
          MaterialRemoveUpdate(name: final removed) when removed == name =>
            null,
          _ => name,
        };
      }
      if (name != null && parameterNamed(name) == null) {
        fail(
          written == name
              ? '"$name" is not a parameter "$material" declares.'
              : '"$written" becomes "$name", which "$material" does not '
                    'declare.',
          where: at,
        );
      }
    }
  }

  /// `workgroup x y;` or `workgroup x y z;` — a kernel's workgroup size,
  /// version 2, with z one where it is not given.
  ///
  /// At most 256 invocations in all, and 64 along z: WebGPU's own limits,
  /// which the other backends that run compute meet too.
  WorkgroupSize parseWorkgroup() {
    int side(String axis, int most) {
      final token = expectToken('number', 'a whole number of invocations');
      final value = token.number!;
      if (value != value.truncateToDouble() || value < 1 || value > most) {
        fail(
          'a workgroup\'s $axis is a whole number from 1 to $most.',
          where: token,
        );
      }
      return value.toInt();
    }

    final x = side('x', 256);
    final y = side('y', 256);
    final z = current.kind == 'number' ? side('z', 64) : 1;
    expectToken(';', '";" after the workgroup');
    if (x * y * z > 256) {
      fail(
        'a workgroup is at most 256 invocations, and $x by $y by $z is '
        '${x * y * z}.',
      );
    }
    return WorkgroupSize(x, y, z);
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
    if (!skipWordIf('f3dmat')) return materialLanguageFirstVersion;
    final number = expectToken('number', 'the language version after "f3dmat"');
    final value = number.number!;
    if (value != value.truncateToDouble() ||
        value < materialLanguageFirstVersion) {
      fail(
        '"${number.text}" is not a language version: write a whole number '
        'from $materialLanguageFirstVersion, as in "f3dmat '
        '$materialLanguageFirstVersion".',
        where: number,
      );
    }
    final version = value.toInt();
    if (version > materialLanguageVersion) {
      fail(
        'this material is written in material language version $version and '
        'this build reads up to $materialLanguageVersion. Update flutter3d '
        'to a release that reads version $version.',
        where: header,
      );
    }
    return version;
  }

  void parseParameter({bool uniform = false}) {
    // `uniform(Hair) vec3 tint = …;` — version 2 (D21): a member of a block
    // of the material's own rather than of `MaterialParams`.
    String? block;
    if (uniform && skipIf('(')) {
      final named = expectToken('name', 'the uniform block\'s name');
      if (version < materialLanguageStagesVersion) {
        fail(
          'a uniform block of a material\'s own is version 2; start the file '
          'with "f3dmat 2"',
          where: named,
        );
      }
      if (isEngineBlockName(named.text) ||
          !RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(named.text)) {
        fail(
          '"${named.text}" cannot name a material\'s block: a block is named '
          'in PascalCase, not as one of the engine\'s own, and not in the '
          'shape the engine keeps for later ones (F3d…, …Info)',
          where: named,
        );
      }
      expectToken(')', '")" after the block\'s name');
      block = named.text;
    }
    final type = parseType();
    if (!type.isNumeric) {
      fail(
        'a parameter is a number or a vector; a texture is declared with '
        '"texture".',
      );
    }
    final nameToken = expectToken('name', 'the parameter\'s name');
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
        where: nameToken,
      );
    }
    expectToken(
      '=',
      '"=" and a default value — a parameter without one is a '
          'parameter a variant can forget to set',
    );
    final value = parseConstant(type);
    expectToken(';', '";" after the parameter');
    parameters.add(
      MaterialParameter(
        nameToken.text,
        type,
        value,
        uniform: uniform,
        block: block,
      ),
    );
  }

  void parseTexture() {
    final nameToken = expectToken('name', 'the slot\'s name');
    checkFreeName(nameToken);
    // `texture fur;` — version 2 (D21): a texture of the material's own, in
    // its slot table, bound as `material_fur`.
    if (kind == MaterialStageKind.surface && skipIf(';')) {
      if (version < materialLanguageStagesVersion) {
        fail(
          'a texture of a material\'s own is version 2; start the file with '
          '"f3dmat 2", or bind one the engine binds: '
          '${materialTextureBindings.join(', ')}',
          where: nameToken,
        );
      }
      textures.add(
        MaterialTextureSlot(
          nameToken.text,
          '$materialOwnTexturePrefix${nameToken.text}',
        ),
      );
      return;
    }
    expectToken('=', '"=" and the engine binding this slot reads');
    final binding = expectToken('name', 'the engine binding\'s name');
    if (kind != MaterialStageKind.surface) {
      // A full-screen stage or a kernel is bound by whoever draws it, by
      // the names it declares — `FullscreenEffect.textures` — so the slot
      // is the author's to name, short of the names the stage already uses.
      if (_reservedNames.contains(binding.text) ||
          materialVersion2ReservedNames.contains(binding.text) ||
          binding.text.startsWith('gl_') ||
          binding.text.startsWith('f3d_')) {
        fail(
          '"${binding.text}" is a name the generated stage already uses; '
          'bind the texture under another.',
          where: binding,
        );
      }
      if (textures.any((slot) => slot.bindingName == binding.text)) {
        fail('"${binding.text}" is bound twice.', where: binding);
      }
    } else if (!materialTextureBindings.contains(binding.text)) {
      fail(
        '"${binding.text}" is not a texture this engine binds. It binds '
        '${materialTextureBindings.join(', ')}; a texture of the material\'s '
        'own is declared without one, "texture ${nameToken.text};", and '
        'bound from RenderMaterial.extraTextures.',
        where: binding,
      );
    }
    expectToken(';', '";" after the texture');
    textures.add(MaterialTextureSlot(nameToken.text, binding.text));
  }

  /// The inputs a name may not take: every one the source could read
  /// somewhere, for a declaration, and the body's own for a `let`.
  ///
  /// A version 1 file keeps the set it always had — the surface's, the
  /// light's and `lit` — so a name it bound then binds now.
  ///
  /// An input arrives with the version that adds it ([MaterialInput.since]),
  /// so one a later version adds never takes a name from an older source.
  List<MaterialInput> takenInputs() => <MaterialInput>[
    for (final input in switch (kind) {
      MaterialStageKind.fullscreen => materialFullscreenInputs,
      MaterialStageKind.compute => materialComputeInputs,
      _ => <MaterialInput>[
        ...materialInputs,
        ...materialLightInputs,
        materialLitInput,
        if (standard) materialStandardLightInput,
        ...switch (block) {
          null => _surfaceVersion2Inputs,
          final body => body.inputs,
        },
      ],
    })
      if (input.since <= version) input,
  ];

  /// The builtin called [name] in this source's version: one a later
  /// version adds ([materialBuiltinVersions]) is neither called nor takes a
  /// name from an older source.
  @override
  ExpressionBuiltin? builtinNamed(String name) =>
      switch (super.builtinNamed(name)) {
        final builtin?
            when (materialBuiltinVersions[builtin.name] ?? 1) <= version =>
          builtin,
        _ => null,
      };

  /// A name may not shadow an input, a builtin or an earlier declaration.
  ///
  /// GLSL would allow some of this and the result is a material whose author
  /// thinks they are reading the surface normal and is reading their own
  /// variable — a bug that looks like the lighting being wrong.
  void checkFreeName(ExpressionToken token) {
    final name = token.text;
    for (final input in takenInputs()) {
      if (input.name == name) {
        fail(
          kind == MaterialStageKind.surface
              ? '"$name" is one of the surface inputs.'
              : '"$name" is one of the inputs.',
          where: token,
        );
      }
    }
    if (kind == MaterialStageKind.fullscreen && name == 'scene') {
      fail(
        '"scene" is the picture a full-screen stage draws over.',
        where: token,
      );
    }
    if (builtinNamed(name) != null || name == 'sample') {
      fail('"$name" is a builtin function.', where: token);
    }
    if (ExpressionType.numeric.values.any((t) => t.name == name)) {
      fail('"$name" is a type.', where: token);
    }
    for (final parameter in parameters) {
      if (parameter.name == name) {
        fail('"$name" is declared twice.', where: token);
      }
    }
    for (final slot in textures) {
      if (slot.name == name) fail('"$name" is declared twice.', where: token);
    }
    if (locals.containsKey(name)) {
      fail('"$name" is already bound in this body.', where: token);
    }
  }

  ExpressionType parseType() {
    final token = expectToken('name', 'a type');
    for (final type in ExpressionType.numeric.values) {
      if (type.name == token.text) return type;
    }
    fail(
      '"${token.text}" is not a type: float, vec2, vec3 and vec4 are.',
      where: token,
    );
  }

  /// A parameter's default: a literal, or a constructor of literals.
  List<double> parseConstant(ExpressionType type) {
    final expression = parseExpression();
    if (expression is! ExpressionConstant) {
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
    expectToken('{', '"{" after "${body.opening}"');
    locals.clear();
    outputs.clear();
    block = body;
    final statements = <MaterialStatement>[];
    while (!skipIf('}')) {
      if (current.kind == 'end') fail('the $what is never closed.');
      if (skipWordIf('let')) {
        final nameToken = expectToken('name', 'the name being bound');
        checkFreeName(nameToken);
        // Only a `let` is written into the shader under its own name; a
        // parameter is folded to a number and a slot to its binding.
        final name = nameToken.text;
        if (_reservedNames.contains(name) ||
            name.startsWith('gl_') ||
            (version >= materialLanguageStagesVersion &&
                (name.startsWith('f3d_') ||
                    materialVersion2ReservedNames.contains(name))) ||
            (body.isVertex && materialVertexReservedNames.contains(name)) ||
            (body.isVertex &&
                version >= materialLanguageVariantsVersion &&
                materialVariantReservedNames.contains(name)) ||
            (version >= materialLanguageUpdatesVersion &&
                materialVersion3ReservedNames.contains(name))) {
          fail(
            '"$name" is a name the generated shader already uses — GLSL, '
            '`surface.glsl` or the emitter itself — so a binding of it would '
            'not compile, or would quietly replace what the engine reads.',
            where: nameToken,
          );
        }
        expectToken('=', '"=" after the name');
        final value = parseExpression();
        if (!value.type.isNumeric) {
          fail('a "let" binds a number or a vector, not a ${value.type}.');
        }
        expectToken(';', '";" after the binding');
        locals[nameToken.text] = value.type;
        statements.add(MaterialLet(nameToken.text, value));
      } else if (body.writes && skipWordIf('out')) {
        statements.add(parseOutput());
      } else if (!body.writes && skipWordIf('return')) {
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
        expectToken(';', '";" after the returned value');
        statements.add(MaterialReturn(value));
        if (current.kind != '}') {
          fail('nothing follows the return in a $what.');
        }
      } else {
        fail(
          body.writes
              ? '"${current.text}" is not a statement: a $what is "let" '
                    'bindings and "out" outputs.'
              : '"${current.text}" is not a statement: a $what is "let" '
                    'bindings and one "return".',
        );
      }
    }
    if (body.writes) {
      if (outputs.isEmpty) {
        fail(
          body.isVertex
              ? 'the vertex block writes nothing: give it an "out" — '
                    'position, world or normal — or leave the block out and '
                    'keep the engine\'s vertex stage.'
              : 'the surface block writes nothing: give it an "out" — '
                    '${body.outputs.map((o) => o.name).join(', ')} — or '
                    'leave the block out and keep the surface the engine '
                    'read.',
        );
      }
    } else if (statements.isEmpty || statements.last is! MaterialReturn) {
      fail('the $what has no "return".');
    }
    block = null;
    return statements;
  }

  /// `out name = value;` in a `vertex` block — version 2 — or a `surface`
  /// block — version 3.
  MaterialOutput parseOutput() {
    final nameToken = expectToken('name', 'the output\'s name');
    final name = nameToken.text;
    final body = block!;
    final output =
        body.outputs.where((o) => o.name == name).firstOrNull ??
        fail(
          '"$name" is not an output: a ${body.what} writes '
          '${body.outputs.map((o) => o.name).join(', ')}.',
          where: nameToken,
        );
    if (!outputs.add(name)) fail('"$name" is written twice.', where: nameToken);
    if (body.isVertex &&
        outputs.contains('position') &&
        outputs.contains('world')) {
      fail(
        'a vertex block writes "position", before the model transform, or '
        '"world", after it — not both.',
        where: nameToken,
      );
    }
    expectToken('=', '"=" after the output');
    final value = parseExpression();
    if (value.type != output.type) {
      fail('"$name" is a ${output.type}, and this is a ${value.type}.');
    }
    expectToken(';', '";" after the output');
    return MaterialOutput(output, value);
  }

  /// `sample(slot, uv)`, the one call that reads something outside the
  /// material.
  @override
  Expression? parseSpecialCall(ExpressionToken name) =>
      name.text == 'sample' ? sampleCall(name) : null;

  /// A material's names, in the order a body sees them: its `let`s, its
  /// parameters, then the inputs of the body being read; and a sentence
  /// naming where a name it cannot read here is read instead.
  @override
  Expression resolveName(ExpressionToken token) {
    final name = token.text;
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
    if (inLight && lightTypes.containsKey(name)) {
      return MaterialInputRef(materialLightTypeInput(name));
    }
    for (final input in body.inputs) {
      if (input.name == name && input.since <= version) {
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
        where: token,
      );
    }
    if (surface && name == materialLitInput.name) {
      if (inLight) {
        fail(
          '"lit" is every light gathered through this block, so the block '
          'cannot read it; the fragment body does.',
          where: token,
        );
      }
      if (!identical(body, fragmentBlock)) {
        fail(
          '"lit" is what the light, ambient and composite blocks add up, so '
          'the ${body.what} cannot read it; the fragment body does.',
          where: token,
        );
      }
      litAt ??= token;
      inputsUsed.add(name);
      return MaterialInputRef(materialLitInput);
    }
    if (textureNamed(name) != null) {
      fail(
        '"$name" is a texture; it is read with sample($name, uv).',
        where: token,
      );
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
        if (version < materialLanguageStagesVersion) {
          fail(
            '"$name" is read from material language version 2: open the '
            'file with "f3dmat 2".',
            where: token,
          );
        }
        fail(
          '"$name" is read in the $other, not in the ${body.what}.',
          where: token,
        );
      }
    }
    fail('"$name" is not bound here.', where: token);
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

  Expression sampleCall(ExpressionToken token) {
    final body = block;
    if (body != null && !body.samples) {
      fail(
        'a ${body.what} cannot sample a texture: the vertex stage binds '
        'none, and a displacement read from a map is a fragment\'s work or '
        'a uniform\'s.',
        where: token,
      );
    }
    expectToken('(', '"(" after sample');
    final slotToken = expectToken('name', 'the texture slot');
    final slot = textureNamed(slotToken.text);
    if (slot == null) {
      fail(
        '"${slotToken.text}" is not a texture this material declares.',
        where: slotToken,
      );
    }
    sampled.add(slot.name);
    expectToken(',', '"," and the coordinates');
    final uv = parseExpression();
    if (uv.type != ExpressionType.vec2) {
      fail(
        'sample takes a vec2 of coordinates, not a ${uv.type}.',
        where: token,
      );
    }
    expectToken(')', '")" after sample');
    return MaterialSample(slot, uv);
  }
}
