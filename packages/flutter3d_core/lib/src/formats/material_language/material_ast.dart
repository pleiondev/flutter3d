/// What a material written as source *is*, once it has been read — `gfx-84n`.
///
/// **The thing both backends read, rather than two transcriptions of it.** A
/// lighting model reaches four backends today as four separate texts: GLSL
/// that `impellerc` compiles, the same GLSL through `glsl_translate.dart` and
/// through `glsl_to_wgsl.dart`, and a hand-written Dart transcription for the
/// software rasteriser. The first three are one source translated, which is
/// why they cannot drift; the fourth is a person reading GLSL and writing
/// Dart, which is why it can. A material written in this language has neither
/// problem: the emitter turns this tree into GLSL and the software backend
/// evaluates the same tree, so there is nothing for two people to disagree
/// about.
///
/// **Sealed, so adding a node breaks every reader at compile time.** An
/// emitter that quietly skipped a node it did not know would produce a shader
/// that is missing a term — visible as a slightly wrong colour, in one backend,
/// with nothing red.
library;

import 'dart:math' as math;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show CompareFunction;

/// A type in the material language.
///
/// A `final class` with const instances rather than an `enum`, which is the
/// rule for anything a published package exports: a later row adds `mat3` and
/// `int`, and adding a value to an exported enum breaks every `switch` written
/// against it. Nothing switches on these anyway — [components] is what every
/// reader actually asks.
final class MaterialType {
  const MaterialType._(this.name, this.components);

  /// One number.
  static const MaterialType float = MaterialType._('float', 1);
  static const MaterialType vec2 = MaterialType._('vec2', 2);
  static const MaterialType vec3 = MaterialType._('vec3', 3);
  static const MaterialType vec4 = MaterialType._('vec4', 4);

  /// A texture slot. Not a value: it can be sampled and nothing else, which is
  /// why its [components] is zero rather than some number of channels.
  static const MaterialType texture = MaterialType._('texture', 0);

  /// The numeric types, by how many components they have — `numeric[3]` is
  /// [vec3]. Index zero is absent on purpose: there is no zero-component
  /// number, and [texture] taking that slot would make an arithmetic mistake
  /// resolve to a texture instead of failing.
  static const Map<int, MaterialType> numeric = <int, MaterialType>{
    1: float,
    2: vec2,
    3: vec3,
    4: vec4,
  };

  final String name;

  /// Zero for [texture].
  final int components;

  bool get isNumeric => components > 0;

  @override
  String toString() => name;
}

/// One declared parameter: a name, a type and the value a variant that says
/// nothing about it gets.
///
/// **A compile-time constant.** What `gfx-84n` asks the toolchain to generate
/// is "the entry points, the variants and the binding metadata", and a variant
/// *is* a set of parameter values compiled into its own entry point.
///
/// **What this is not is the only way a value could reach the shader**, and an
/// earlier version of this comment said it was. It claimed a parameter that
/// changed per frame would need a new uniform block per material, which the
/// engine could not have. The engine already has one: `RenderMaterial.parameters`
/// is bound as `MaterialParams` to the fragment stage, and since `gfx-86n` to
/// a vertex stage the material brought as well. A runtime parameter in this
/// language would be a member of that block; it is not written, and the reason
/// is scope rather than impossibility.
final class MaterialParameter {
  const MaterialParameter(
    this.name,
    this.type,
    this.defaultValue, {
    this.uniform = false,
  });

  final String name;
  final MaterialType type;

  /// As many numbers as [type] has components.
  final List<double> defaultValue;

  /// Declared with `uniform` rather than `param` — `P8`: not folded, but a
  /// member of the `MaterialParams` block, read from `RenderMaterial.parameters`
  /// on every draw, so a game sets it without a second entry point. A
  /// variant cannot set one; [defaultValue] is what a material that names
  /// no value is given.
  final bool uniform;
}

/// One texture slot the material samples, by the name the engine binds it
/// under.
final class MaterialTextureSlot {
  const MaterialTextureSlot(this.name, this.bindingName);

  /// What the source calls it.
  final String name;

  /// What the engine binds — `base_color_texture` and the rest. A material
  /// cannot invent a slot, for the same reason it cannot invent a uniform
  /// block, so the parser holds the source name to one the engine already
  /// binds and says which names those are when it does not.
  final String bindingName;
}

/// One value the fragment body can read.
///
/// The set is the intersection of what `surface.glsl`'s `Surface` carries and
/// what `cpu_shaders_surface.dart`'s `Surface` carries, which is the same
/// struct written twice — so an input here is a field both already have, never
/// something one side would have to compute.
final class MaterialInput {
  const MaterialInput(this.name, this.type, this.glsl);

  final String name;
  final MaterialType type;

  /// The GLSL that reads it, given a `Surface s` in scope.
  final String glsl;
}

/// Every input, and the single list of them.
///
/// The software backend's evaluator has to know each one by name, and a test
/// walks this list to check that it does — a backend that silently returned
/// zero for an input it had not heard of would draw a material that is subtly
/// wrong on one backend only.
const List<MaterialInput> materialInputs = <MaterialInput>[
  MaterialInput('albedo', MaterialType.vec3, 's.albedo'),
  MaterialInput('alpha', MaterialType.float, 's.alpha'),
  MaterialInput('normal', MaterialType.vec3, 's.n'),
  MaterialInput('view', MaterialType.vec3, 's.v'),
  MaterialInput('nDotV', MaterialType.float, 's.n_dot_v'),
  MaterialInput('metallic', MaterialType.float, 's.metallic'),
  MaterialInput('roughness', MaterialType.float, 's.roughness'),
  MaterialInput('occlusion', MaterialType.float, 's.occlusion'),
  MaterialInput('emissive', MaterialType.vec3, 's.emissive'),
  MaterialInput('ambient', MaterialType.vec3, 's.ambient'),
  MaterialInput('uv', MaterialType.vec2, 'v_texcoord'),
  MaterialInput('world', MaterialType.vec3, 'v_world_position'),
  // `P8`: an instance's own four numbers, `InstancedMeshNode.setInstanceData`
  // — nought for a draw that is not instanced. The emitted stage declares
  // the varying only when the source reads it.
  MaterialInput('instance', MaterialType.vec4, 'v_instance'),
];

/// What the `light` block reads about the one light it is shading for, on
/// top of [materialInputs] — `P8`, the lighting hook.
///
/// `surface.glsl`'s `LightSample` and `cpu_shaders_lighting.dart`'s, the same
/// struct written twice, as the surface inputs are. Read only inside the
/// block: outside it there is no one light to read them of.
const List<MaterialInput> materialLightInputs = <MaterialInput>[
  MaterialInput('lightDir', MaterialType.vec3, 'light.l'),
  MaterialInput('halfDir', MaterialType.vec3, 'light.h'),
  MaterialInput('nDotL', MaterialType.float, 'light.n_dot_l'),
  MaterialInput('nDotH', MaterialType.float, 'light.n_dot_h'),
  MaterialInput('vDotH', MaterialType.float, 'light.v_dot_h'),
];

/// What a fragment body of version 2 reads of the scene behind it — item 9
/// of `tasks/1.0-scope-additions.md`, for soft edges, fog and water.
///
/// **Only a translucent material reads them**, and the parser holds it to
/// that: the scene behind a surface is the opaque half's depth, which the
/// engine lends a translucent draw after that half is done. `sceneDepth` is
/// how far the opaque surface behind this fragment lies along the view axis,
/// in metres, and a million where nothing was drawn behind — the sky is far;
/// `viewDepth` is this fragment's own depth along the same axis, so
/// `sceneDepth - viewDepth` is the thickness of what lies between;
/// `scenePosition` is where, in the world, that opaque surface is.
const List<MaterialInput> materialSceneInputs = <MaterialInput>[
  MaterialInput('sceneDepth', MaterialType.float, 'f3d_scene_depth'),
  MaterialInput('viewDepth', MaterialType.float, 'f3d_view_depth'),
  MaterialInput('scenePosition', MaterialType.vec3, 'f3d_scene_position'),
];

/// What a `vertex` block reads — version 2.
///
/// The vertex as the engine has it once morphed, and skinned on a skinned
/// draw: `position` and `objectNormal` in the mesh's own space (the pose's,
/// for a skinned mesh), `world` and `normal` after the model transform, the
/// first texture coordinate, the vertex colour, and `origin`, the model
/// transform's translation — where the object stands, so a field of grass
/// sways out of step blade by blade.
const List<MaterialInput> materialVertexInputs = <MaterialInput>[
  MaterialInput('position', MaterialType.vec3, 'f3d_position'),
  MaterialInput('objectNormal', MaterialType.vec3, 'f3d_object_normal'),
  MaterialInput('world', MaterialType.vec3, 'f3d_world'),
  MaterialInput('normal', MaterialType.vec3, 'f3d_normal'),
  MaterialInput('uv', MaterialType.vec2, 'texcoord'),
  MaterialInput('color', MaterialType.vec4, 'color'),
  MaterialInput('origin', MaterialType.vec3, 'frame_info.model[3].xyz'),
];

/// What a `vertex` block may write, with `out name = value;` — version 2.
///
/// `position` is the vertex in the mesh's own space, which the model
/// transform then carries into the world; `world` is where it ends up, the
/// transform already applied; one or the other, not both. `normal` is the
/// world-space normal the surface is lit by. What the block does not write
/// keeps the engine's own answer.
const List<MaterialInput> materialVertexOutputs = <MaterialInput>[
  MaterialInput('position', MaterialType.vec3, 'f3d_out_position'),
  MaterialInput('world', MaterialType.vec3, 'f3d_out_world'),
  MaterialInput('normal', MaterialType.vec3, 'f3d_out_normal'),
];

/// What an `ambient` block reads on top of [materialInputs] — version 2:
/// the level's baked light at this fragment, which the engine's own ambient
/// adds to the hemisphere.
const List<MaterialInput> materialAmbientInputs = <MaterialInput>[
  MaterialInput('lightmap', MaterialType.vec3, 'f3d_lightmap'),
];

/// What a `composite` block reads on top of [materialInputs] — version 2:
/// the lights gathered through the `light` block, and the light the
/// `ambient` block (or the engine's own ambient) gave, neither yet under the
/// occlusion.
const List<MaterialInput> materialCompositeInputs = <MaterialInput>[
  MaterialInput('direct', MaterialType.vec3, 'f3d_direct'),
  MaterialInput('indirect', MaterialType.vec3, 'f3d_indirect'),
];

/// What a `fullscreen` stage's fragment body reads — version 2: where on the
/// screen it is, nought to one from the top left, and the depth the scene
/// left there along the view axis, in metres, a million where nothing was
/// drawn. The picture itself is the texture `scene`, read with
/// `sample(scene, uv)`.
const List<MaterialInput> materialFullscreenInputs = <MaterialInput>[
  MaterialInput('uv', MaterialType.vec2, 'v_uv'),
  MaterialInput('sceneDepth', MaterialType.float, 'f3d_scene_depth'),
];

/// What a `compute` stage's kernel reads — version 2: the texel of its
/// target this invocation writes, the target's size in texels, and the
/// texel's centre as nought to one.
const List<MaterialInput> materialComputeInputs = <MaterialInput>[
  MaterialInput('cell', MaterialType.vec2, 'f3d_cell'),
  MaterialInput('size', MaterialType.vec2, 'f3d_size'),
  MaterialInput('uv', MaterialType.vec2, 'f3d_uv'),
];

/// What a source is — version 2 adds the two kinds after `material`.
///
/// * [surface], `material`: a surface the engine draws a mesh with.
/// * [fullscreen]: one full-screen fragment stage over the picture — what a
///   `FullscreenEffect` and a plugin's render step draw.
/// * [compute]: a kernel run once per texel of a storage texture it writes.
///
/// A `final class` with const instances, for [MaterialType]'s reason.
final class MaterialStageKind {
  const MaterialStageKind._(this.name);

  static const MaterialStageKind surface = MaterialStageKind._('material');
  static const MaterialStageKind fullscreen = MaterialStageKind._('fullscreen');
  static const MaterialStageKind compute = MaterialStageKind._('compute');

  static const List<MaterialStageKind> all = <MaterialStageKind>[
    surface,
    fullscreen,
    compute,
  ];

  /// The word the source opens with.
  final String name;

  @override
  String toString() => name;
}

/// How a surface is combined with what is behind it — a `state` block's
/// `blend` — version 2.
///
/// [opaque], [mask] and [hashed] are `MaterialAlphaMode`'s three that write
/// depth; [alpha] is its blend, over straight colour; [additive] adds the
/// colour, times its alpha, to what is there; [premultiplied] is over on a
/// colour the material already multiplied by its alpha.
final class MaterialBlend {
  const MaterialBlend._(this.name, {required this.translucent});

  static const MaterialBlend opaque = MaterialBlend._(
    'opaque',
    translucent: false,
  );
  static const MaterialBlend mask = MaterialBlend._('mask', translucent: false);
  static const MaterialBlend hashed = MaterialBlend._(
    'hashed',
    translucent: false,
  );
  static const MaterialBlend alpha = MaterialBlend._(
    'alpha',
    translucent: true,
  );
  static const MaterialBlend additive = MaterialBlend._(
    'additive',
    translucent: true,
  );
  static const MaterialBlend premultiplied = MaterialBlend._(
    'premultiplied',
    translucent: true,
  );

  static const List<MaterialBlend> all = <MaterialBlend>[
    opaque,
    mask,
    hashed,
    alpha,
    additive,
    premultiplied,
  ];

  static MaterialBlend? byName(String name) {
    for (final blend in all) {
      if (blend.name == name) return blend;
    }
    return null;
  }

  /// What the `state` block calls it.
  final String name;

  /// Whether it is drawn in the transparent half, over what is behind it.
  final bool translucent;

  @override
  String toString() => name;
}

/// The depth tests a `state` block's `depthCompare` names, and the
/// [CompareFunction] each becomes.
///
/// **An explicit table, not `CompareFunction.values.byName`.** The words are
/// the file's, and they were the Dart names of the values on the day the
/// language was written; a rename of a value in a later release must not
/// change which word a `.f3dmat` file has to say. A new compare function gets
/// a new word here, and an old word never changes meaning.
const Map<String, CompareFunction> materialDepthCompareWire =
    <String, CompareFunction>{
      'never': CompareFunction.never,
      'less': CompareFunction.less,
      'equal': CompareFunction.equal,
      'lessEqual': CompareFunction.lessEqual,
      'greater': CompareFunction.greater,
      'notEqual': CompareFunction.notEqual,
      'greaterEqual': CompareFunction.greaterEqual,
      'always': CompareFunction.always,
    };

/// The words of [materialDepthCompareWire], in its order.
const List<String> materialDepthCompares = <String>[
  'never',
  'less',
  'equal',
  'lessEqual',
  'greater',
  'notEqual',
  'greaterEqual',
  'always',
];

/// The furthest a `state` block's `depthLayer` reaches either way.
const int materialDepthLayerLimit = 16;

/// What a material's `state` block says — version 2: how it is drawn, and
/// which light its stage leaves out.
///
/// **Two kinds of setting in one block.** Everything but the last two is
/// draw state, which `BundledMaterials.material` copies onto the `RenderMaterial`
/// it makes — a game can still change it there. [environment] and
/// [directional] are compile-time switches: they change the stage itself, so
/// they are answered once, here, and nothing at run time turns them back on.
///
/// Null is "the file says nothing", which leaves `RenderMaterial`'s own default.
final class MaterialFileState {
  const MaterialFileState({
    this.blend,
    this.cutoff,
    this.depthWrite,
    this.depthTest,
    this.depthCompare,
    this.alphaToCoverage,
    this.doubleSided,
    this.depthLayer,
    this.effectsDepth,
    this.environment = true,
    this.directional = true,
  });

  /// A file with no `state` block.
  static const MaterialFileState none = MaterialFileState();

  final MaterialBlend? blend;

  /// The alpha a [MaterialBlend.mask] surface is cut at, nought to one.
  final double? cutoff;
  final bool? depthWrite;

  /// `off` is a depth test that always passes — `depthCompare always`.
  final bool? depthTest;

  /// One of [materialDepthCompares].
  final String? depthCompare;

  /// A masked edge as multisample coverage — `RenderMaterial.alphaToCoverage`.
  final bool? alphaToCoverage;
  final bool? doubleSided;

  /// Which of two coplanar surfaces wins — `RenderMaterial.depthLayer`.
  final int? depthLayer;

  /// Whether a translucent surface puts its depth and normal into the
  /// surface buffer the screen-space effects read — `RenderMaterial.effectsDepth`.
  final bool? effectsDepth;

  /// False compiles the environment's light out of `lit`: the hemisphere,
  /// the irradiance field and the lightmap. A switch, not draw state.
  final bool environment;

  /// False compiles the directional lights — the sun — out of `lit`. A
  /// switch, not draw state.
  final bool directional;

  /// Whether the blend draws the surface in the transparent half.
  bool get isTranslucent => blend?.translucent ?? false;
}

/// The surface lit as the engine lights it, through the material's own
/// `light` block — `P8`. Read in the fragment body of a material that has
/// one.
///
/// **Everything a lit model of the engine's adds up, not the lights alone**:
/// every light through the block, by its radiance, `n·l` and shadow, then the
/// ambient and the lightmap, then the emissive, with the occlusion over the
/// first two — what `lambert.frag` writes. Whole, because a compiled shader
/// keeps a sampler only if something reads it, and the engine binds the maps
/// and the shadow atlases to a lit model: a material whose output skipped
/// the emissive would leave its map unread and the bind refused. A material
/// adds to it what is not lighting — a rim, a glow.
const MaterialInput materialLitInput = MaterialInput(
  'lit',
  MaterialType.vec3,
  'lit',
);

/// A function the language knows, its type rule and how to compute it.
///
/// **One table, read by the emitter and by the evaluator.** A builtin that
/// existed on one side and not the other is the exact failure this whole row
/// is against, so neither side has its own list: the emitter takes [glsl] and
/// the software backend takes [apply], from the same const instance.
final class MaterialBuiltin {
  const MaterialBuiltin._(
    this.name, {
    required this.arity,
    required this.glsl,
    required this.apply,
    this.componentWise = true,
    this.resultComponents,
  });

  final String name;
  final int arity;

  /// The GLSL name, which is the same word for all of these — the language's
  /// vocabulary is GLSL's on purpose, so that an author who knows one knows the
  /// other and the emitted shader reads like the source.
  final String glsl;

  /// The value, given each argument's components. Arguments are already
  /// broadcast to a common width when [componentWise] is set, so an
  /// implementation here never has to think about `mix(vec3, vec3, float)`.
  final List<double> Function(List<List<double>> arguments) apply;

  /// Whether a float argument beside a vector one is spread across it —
  /// `clamp(v, 0.0, 1.0)` and `mix(a, b, t)`. False for the ones that collapse
  /// a vector to a number, where a float argument means something else.
  final bool componentWise;

  /// Fixed for the collapsing ones, and null when the result is as wide as the
  /// widest argument.
  final int? resultComponents;

  // `dot` and `length` collapse a vector to a number, so — as [componentWise]
  // says of them — a float beside a vector is not spread: GLSL has no
  // `dot(vec3, float)`, and accepting one here parsed a material whose shader
  // then failed to compile.
  static const MaterialBuiltin dot = MaterialBuiltin._(
    'dot',
    arity: 2,
    glsl: 'dot',
    apply: _dot,
    componentWise: false,
    resultComponents: 1,
  );
  static const MaterialBuiltin length = MaterialBuiltin._(
    'length',
    arity: 1,
    glsl: 'length',
    apply: _length,
    componentWise: false,
    resultComponents: 1,
  );
  static const MaterialBuiltin normalize = MaterialBuiltin._(
    'normalize',
    arity: 1,
    glsl: 'normalize',
    apply: _normalize,
    componentWise: false,
  );
  static const MaterialBuiltin mix = MaterialBuiltin._(
    'mix',
    arity: 3,
    glsl: 'mix',
    apply: _mix,
  );
  static const MaterialBuiltin clamp = MaterialBuiltin._(
    'clamp',
    arity: 3,
    glsl: 'clamp',
    apply: _clamp,
  );
  static const MaterialBuiltin smoothstep = MaterialBuiltin._(
    'smoothstep',
    arity: 3,
    glsl: 'smoothstep',
    apply: _smoothstep,
  );
  static const MaterialBuiltin step = MaterialBuiltin._(
    'step',
    arity: 2,
    glsl: 'step',
    apply: _step,
  );
  static const MaterialBuiltin pow = MaterialBuiltin._(
    'pow',
    arity: 2,
    glsl: 'pow',
    apply: _pow,
  );
  static const MaterialBuiltin min = MaterialBuiltin._(
    'min',
    arity: 2,
    glsl: 'min',
    apply: _min,
  );
  static const MaterialBuiltin max = MaterialBuiltin._(
    'max',
    arity: 2,
    glsl: 'max',
    apply: _max,
  );
  static const MaterialBuiltin abs = MaterialBuiltin._(
    'abs',
    arity: 1,
    glsl: 'abs',
    apply: _abs,
  );
  static const MaterialBuiltin sqrt = MaterialBuiltin._(
    'sqrt',
    arity: 1,
    glsl: 'sqrt',
    apply: _sqrt,
  );
  static const MaterialBuiltin floor = MaterialBuiltin._(
    'floor',
    arity: 1,
    glsl: 'floor',
    apply: _floor,
  );
  static const MaterialBuiltin fract = MaterialBuiltin._(
    'fract',
    arity: 1,
    glsl: 'fract',
    apply: _fract,
  );
  static const MaterialBuiltin sin = MaterialBuiltin._(
    'sin',
    arity: 1,
    glsl: 'sin',
    apply: _sin,
  );
  static const MaterialBuiltin cos = MaterialBuiltin._(
    'cos',
    arity: 1,
    glsl: 'cos',
    apply: _cos,
  );

  static const List<MaterialBuiltin> all = <MaterialBuiltin>[
    dot,
    length,
    normalize,
    mix,
    clamp,
    smoothstep,
    step,
    pow,
    min,
    max,
    abs,
    sqrt,
    floor,
    fract,
    sin,
    cos,
  ];

  static MaterialBuiltin? byName(String name) {
    for (final builtin in all) {
      if (builtin.name == name) return builtin;
    }
    return null;
  }
}

/// An expression, typed by the parser rather than by whoever reads it later.
sealed class MaterialExpression {
  const MaterialExpression(this.type);

  final MaterialType type;
}

/// A literal, and the one place a `vec3(1.0, 0.0, 0.0)` that is entirely
/// constant ends up: the parser folds a constructor whose arguments are all
/// literals, because a parameter is a constant too and folding is what makes a
/// variant's value reach the shader as a number.
final class MaterialConstant extends MaterialExpression {
  const MaterialConstant(this.value, MaterialType type) : super(type);

  final List<double> value;
}

/// One of [materialInputs].
final class MaterialInputRef extends MaterialExpression {
  MaterialInputRef(this.input) : super(input.type);

  final MaterialInput input;
}

/// A declared parameter, before a variant has said what it is.
///
/// Kept as a reference through parsing and folded to a [MaterialConstant] by
/// [specializeMaterial] — the source is parsed once and every variant is a
/// fold of the same tree, rather than a parse per variant that could differ in
/// some other way than the numbers.
final class MaterialParamRef extends MaterialExpression {
  MaterialParamRef(this.parameter) : super(parameter.type);

  final MaterialParameter parameter;
}

/// A `let` bound earlier in the body.
final class MaterialLocalRef extends MaterialExpression {
  const MaterialLocalRef(this.name, MaterialType type) : super(type);

  final String name;
}

/// `vec3(...)`, `vec4(...)` and the rest, with arguments that are not all
/// constant.
///
/// GLSL's own rule, kept: the arguments' components are laid end to end and
/// must add up to the result's width, so `vec4(rgb, a)` works and `vec4(rgb)`
/// does not.
final class MaterialConstruct extends MaterialExpression {
  const MaterialConstruct(this.arguments, MaterialType type) : super(type);

  final List<MaterialExpression> arguments;
}

/// `.x`, `.rgb`, `.xy` — component indices into the target.
final class MaterialSwizzle extends MaterialExpression {
  const MaterialSwizzle(this.target, this.components, MaterialType type)
    : super(type);

  final MaterialExpression target;

  /// Zero-based, in the order written.
  final List<int> components;
}

/// Unary minus. The only unary operator, because `!` needs a bool type the
/// language has not got.
final class MaterialNegate extends MaterialExpression {
  MaterialNegate(this.operand) : super(operand.type);

  final MaterialExpression operand;
}

/// `+ - * /`, with GLSL's broadcasting: a float beside a vector spreads.
final class MaterialBinary extends MaterialExpression {
  const MaterialBinary(this.op, this.left, this.right, MaterialType type)
    : super(type);

  final String op;
  final MaterialExpression left;
  final MaterialExpression right;
}

/// A call to one of [MaterialBuiltin.all].
final class MaterialCall extends MaterialExpression {
  const MaterialCall(this.builtin, this.arguments, MaterialType type)
    : super(type);

  final MaterialBuiltin builtin;
  final List<MaterialExpression> arguments;
}

/// `sample(slot, uv)`.
///
/// Its own node rather than a [MaterialBuiltin] because it is the one
/// expression that reads something outside the material: a builtin's [
/// MaterialBuiltin.apply] takes numbers and returns numbers, and this one
/// needs whatever the backend binds textures with.
final class MaterialSample extends MaterialExpression {
  const MaterialSample(this.slot, this.uv) : super(MaterialType.vec4);

  final MaterialTextureSlot slot;
  final MaterialExpression uv;
}

sealed class MaterialStatement {
  const MaterialStatement();
}

/// `let name = expr;` — single assignment, so nothing here is a variable.
final class MaterialLet extends MaterialStatement {
  const MaterialLet(this.name, this.value);

  final String name;
  final MaterialExpression value;
}

/// `return expr;` — a `vec4`, rgb being the light the surface emits and a its
/// opacity, which is what `WriteSurface` takes.
final class MaterialReturn extends MaterialStatement {
  const MaterialReturn(this.value);

  final MaterialExpression value;
}

/// `out name = expr;` — one of [materialVertexOutputs], written by a
/// `vertex` block — version 2. Each at most once, and the block's only way
/// to say anything: it has no `return`.
final class MaterialOutput extends MaterialStatement {
  const MaterialOutput(this.output, this.value);

  final MaterialInput output;
  final MaterialExpression value;
}

/// A material read from source: its name, what it declares, and its body.
final class MaterialProgram {
  const MaterialProgram({
    required this.name,
    required this.parameters,
    required this.textures,
    required this.body,
    required this.inputsUsed,
    this.light,
    this.languageVersion = 1,
    this.kind = MaterialStageKind.surface,
    this.state = MaterialFileState.none,
    this.vertex,
    this.ambient,
    this.composite,
    this.workgroupSize = (8, 8),
  });

  final String name;

  /// The material language version the source was written in: its
  /// `f3dmat <version>` line, or 1 when it has none. See
  /// `materialLanguageVersion`.
  final int languageVersion;

  /// What the source is: a surface, a full-screen stage or a compute
  /// kernel — version 2. Every version 1 file is a surface.
  final MaterialStageKind kind;

  /// The `state` block — version 2. [MaterialFileState.none] without one.
  final MaterialFileState state;

  /// The `vertex` block — version 2: `let`s and [MaterialOutput]s, run for
  /// every vertex in the scene pass, the depth pre-draw and the shadow
  /// passes alike, so geometry it moves casts the shadow it draws. Null for
  /// a material that keeps the engine's vertex stage.
  final List<MaterialStatement>? vertex;

  /// The `ambient` block — version 2: the light the surface takes from its
  /// surroundings, a `vec3`, in place of the engine's
  /// `albedo * (ambient + lightmap)`. Only beside a `light` block.
  final List<MaterialStatement>? ambient;

  /// The `composite` block — version 2: how `lit` is added up from
  /// `direct`, `indirect` and the surface, a `vec3`, in place of the
  /// engine's `(direct + indirect) * occlusion + emissive`. Only beside a
  /// `light` block.
  final List<MaterialStatement>? composite;

  /// A [MaterialStageKind.compute] kernel's workgroup, x by y — its
  /// `workgroup` line, eight by eight without one.
  final (int, int) workgroupSize;

  final List<MaterialParameter> parameters;
  final List<MaterialTextureSlot> textures;
  final List<MaterialStatement> body;

  /// The `light` block, or null for a material that gathers no lights —
  /// `P8`. Run once per light, its return a `vec3`: how the surface responds
  /// to that light, which the engine multiplies by the light's radiance, its
  /// `n·l` and its shadow, as it does `ShadeLight` of every lit model. The
  /// sum reaches the fragment body as [materialLitInput].
  final List<MaterialStatement>? light;

  /// Which of [materialInputs] the body actually reads.
  ///
  /// **This is the binding metadata `gfx-84n` asks the toolchain to
  /// generate.** `LightingModel`'s `uses…` flags are declared by hand today,
  /// with a comment saying reflection cannot answer the question — a uniform
  /// block is reported present because the GLSL declared it, even when the
  /// compiled shader binds nothing for it, and binding that phantom block
  /// segfaults inside Metal. A material whose source this package parsed does
  /// not have that problem: what it reads is what is written down.
  final Set<String> inputsUsed;

  /// Whether the stage gathers lights: a surface with a `light` block.
  bool get isLit => light != null;

  /// Whether the fragment body reads the scene behind it —
  /// [materialSceneInputs], or a full-screen stage's `sceneDepth`.
  bool get readsSceneDepth =>
      inputsUsed.contains('sceneDepth') || inputsUsed.contains('scenePosition');

  /// The vertex stage the build makes of the `vertex` block, or null for a
  /// material without one: the material's name with `Vertex` after it. The
  /// skinned half is this with `Skinned` after it, as `LightingModel`'s
  /// `vertexShaderName` says.
  String? get vertexStageName => vertex == null ? null : '${name}Vertex';

  MaterialParameter? parameter(String name) {
    for (final parameter in parameters) {
      if (parameter.name == name) return parameter;
    }
    return null;
  }
}

/// One compiled entry point: a program with its parameters pinned.
///
/// The name is the entry point a `LightingModel` asks the bundle for, so two
/// variants of one source are two shaders on the GPU and two stages on the
/// software backend — which is what they have to be, since a parameter is a
/// constant folded into the code.
final class MaterialVariant {
  const MaterialVariant(this.name, [this.values = const {}]);

  final String name;

  /// Parameter name to value. Anything not named keeps its default; a
  /// `uniform` cannot be named here.
  final Map<String, List<double>> values;
}

/// [program] with [variant]'s parameter values folded in, ready to emit or to
/// evaluate.
///
/// **Folding is what makes a variant an entry point rather than a setting.**
/// Every [MaterialParamRef] becomes the number the variant gives it, and a
/// subtree that is then entirely constant collapses — so `pow(x, rimPower)`
/// with `rimPower = 2.0` reaches the GPU as `pow(x, 2.0)` and reaches the
/// software backend as the same multiplication, from one decision.
///
/// Throws [ArgumentError] for a value of the wrong width or a name the program
/// does not declare: a variant that set `rimPowr` would otherwise compile to
/// the default and look like the parameter not working.
MaterialProgram specializeMaterial(
  MaterialProgram program,
  MaterialVariant variant,
) {
  for (final MapEntry(:key, :value) in variant.values.entries) {
    final parameter = program.parameter(key);
    if (parameter == null) {
      throw ArgumentError(
        'Variant "${variant.name}" sets "$key", which '
        '"${program.name}" does not declare.',
      );
    }
    if (value.length != parameter.type.components) {
      throw ArgumentError(
        'Variant "${variant.name}" gives "$key" ${value.length} components, '
        'and it is a ${parameter.type}.',
      );
    }
  }

  for (final key in variant.values.keys) {
    if (program.parameter(key)!.uniform) {
      throw ArgumentError(
        'Variant "${variant.name}" sets "$key", which "${program.name}" '
        'declares as a uniform: set it on the material, in '
        'Material.parameters, rather than in a variant.',
      );
    }
  }

  List<MaterialStatement> fold(
    List<MaterialStatement> body,
  ) => <MaterialStatement>[
    for (final statement in body)
      switch (statement) {
        MaterialLet(:final name, :final value) => MaterialLet(
          name,
          _fold(value, variant),
        ),
        MaterialReturn(:final value) => MaterialReturn(_fold(value, variant)),
        MaterialOutput(:final output, :final value) => MaterialOutput(
          output,
          _fold(value, variant),
        ),
      },
  ];

  List<MaterialStatement>? foldOptional(List<MaterialStatement>? body) =>
      body == null ? null : fold(body);

  return MaterialProgram(
    name: variant.name,
    parameters: program.parameters,
    textures: program.textures,
    body: fold(program.body),
    light: foldOptional(program.light),
    vertex: foldOptional(program.vertex),
    ambient: foldOptional(program.ambient),
    composite: foldOptional(program.composite),
    inputsUsed: program.inputsUsed,
    languageVersion: program.languageVersion,
    kind: program.kind,
    state: program.state,
    workgroupSize: program.workgroupSize,
  );
}

MaterialExpression _fold(MaterialExpression expression, MaterialVariant v) {
  switch (expression) {
    case MaterialConstant():
    case MaterialInputRef():
    case MaterialLocalRef():
      return expression;
    // A uniform stays a reference: its value arrives with each draw.
    case MaterialParamRef(:final parameter) when parameter.uniform:
      return expression;
    case MaterialParamRef(:final parameter):
      return MaterialConstant(
        v.values[parameter.name] ?? parameter.defaultValue,
        parameter.type,
      );
    case MaterialConstruct(:final arguments, :final type):
      final folded = <MaterialExpression>[
        for (final argument in arguments) _fold(argument, v),
      ];
      if (folded.every((f) => f is MaterialConstant)) {
        return MaterialConstant(<double>[
          for (final f in folded) ...(f as MaterialConstant).value,
        ], type);
      }
      return MaterialConstruct(folded, type);
    case MaterialSwizzle(:final target, :final components, :final type):
      final folded = _fold(target, v);
      if (folded is MaterialConstant) {
        return MaterialConstant(<double>[
          for (final index in components) folded.value[index],
        ], type);
      }
      return MaterialSwizzle(folded, components, type);
    case MaterialNegate(:final operand):
      final folded = _fold(operand, v);
      if (folded is MaterialConstant) {
        return MaterialConstant(<double>[
          for (final component in folded.value) -component,
        ], folded.type);
      }
      return MaterialNegate(folded);
    case MaterialBinary(:final op, :final left, :final right, :final type):
      final a = _fold(left, v);
      final b = _fold(right, v);
      if (a is MaterialConstant && b is MaterialConstant) {
        return MaterialConstant(applyBinary(op, a.value, b.value), type);
      }
      return MaterialBinary(op, a, b, type);
    case MaterialCall(:final builtin, :final arguments, :final type):
      final folded = <MaterialExpression>[
        for (final argument in arguments) _fold(argument, v),
      ];
      if (folded.every((f) => f is MaterialConstant)) {
        return MaterialConstant(
          builtin.apply(
            broadcastArguments(<List<double>>[
              for (final f in folded) (f as MaterialConstant).value,
            ], builtin),
          ),
          type,
        );
      }
      return MaterialCall(builtin, folded, type);
    case MaterialSample(:final slot, :final uv):
      return MaterialSample(slot, _fold(uv, v));
  }
}

/// `+ - * /` on two values, with GLSL's broadcasting.
///
/// Exported because the software backend evaluates the same operators and a
/// second implementation of "what does vec3 * float mean" is exactly the drift
/// this language exists to remove.
List<double> applyBinary(String op, List<double> a, List<double> b) {
  final width = a.length > b.length ? a.length : b.length;
  double at(List<double> value, int i) =>
      value.length == 1 ? value[0] : value[i];
  return <double>[
    for (var i = 0; i < width; i++)
      switch (op) {
        '+' => at(a, i) + at(b, i),
        '-' => at(a, i) - at(b, i),
        '*' => at(a, i) * at(b, i),
        '/' => at(a, i) / at(b, i),
        _ => throw ArgumentError('"$op" is not an operator.'),
      },
  ];
}

/// Spreads a one-component argument across the widest one, for the builtins
/// that take a float beside a vector.
///
/// Shared by the folder and the software backend, for the reason
/// [applyBinary] is.
List<List<double>> broadcastArguments(
  List<List<double>> arguments,
  MaterialBuiltin builtin,
) {
  if (!builtin.componentWise) return arguments;
  var width = 1;
  for (final argument in arguments) {
    if (argument.length > width) width = argument.length;
  }
  return <List<double>>[
    for (final argument in arguments)
      argument.length == width
          ? argument
          : List<double>.filled(width, argument.single),
  ];
}

List<double> _dot(List<List<double>> a) {
  var sum = 0.0;
  for (var i = 0; i < a[0].length; i++) {
    sum += a[0][i] * a[1][i];
  }
  return <double>[sum];
}

List<double> _length(List<List<double>> a) {
  var sum = 0.0;
  for (final component in a[0]) {
    sum += component * component;
  }
  return <double>[math.sqrt(sum)];
}

List<double> _normalize(List<List<double>> a) {
  final length = _length(a)[0];
  // GLSL's own behaviour is undefined at zero length; zero is the answer that
  // does not put a NaN through the rest of the shader, and it is what
  // `vector_math`'s `normalize` does too, so the two backends agree.
  if (length == 0) return List<double>.filled(a[0].length, 0);
  return <double>[for (final component in a[0]) component / length];
}

List<double> _mix(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[0][i] + (a[1][i] - a[0][i]) * a[2][i],
];

List<double> _clamp(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++)
    a[0][i] < a[1][i]
        ? a[1][i]
        : a[0][i] > a[2][i]
        ? a[2][i]
        : a[0][i],
];

List<double> _smoothstep(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++)
    _smoothstepAt(a[0][i], a[1][i], a[2][i]),
];

double _smoothstepAt(double edge0, double edge1, double x) {
  if (edge0 == edge1) return x < edge0 ? 0 : 1;
  var t = (x - edge0) / (edge1 - edge0);
  t = t < 0 ? 0 : (t > 1 ? 1 : t);
  return t * t * (3 - 2 * t);
}

List<double> _step(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[1][i] < a[0][i] ? 0.0 : 1.0,
];

List<double> _pow(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) math.pow(a[0][i], a[1][i]).toDouble(),
];

List<double> _min(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[0][i] < a[1][i] ? a[0][i] : a[1][i],
];

List<double> _max(List<List<double>> a) => <double>[
  for (var i = 0; i < a[0].length; i++) a[0][i] > a[1][i] ? a[0][i] : a[1][i],
];

List<double> _abs(List<List<double>> a) => <double>[
  for (final component in a[0]) component < 0 ? -component : component,
];

List<double> _sqrt(List<List<double>> a) => <double>[
  for (final component in a[0]) math.sqrt(component),
];

List<double> _floor(List<List<double>> a) => <double>[
  for (final component in a[0]) component.floorToDouble(),
];

List<double> _fract(List<List<double>> a) => <double>[
  for (final component in a[0]) component - component.floorToDouble(),
];

List<double> _sin(List<List<double>> a) => <double>[
  for (final component in a[0]) math.sin(component),
];

List<double> _cos(List<List<double>> a) => <double>[
  for (final component in a[0]) math.cos(component),
];
