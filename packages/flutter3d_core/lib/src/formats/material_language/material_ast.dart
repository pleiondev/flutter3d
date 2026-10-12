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
/// **Read through a visitor, so a node no reader knows is refused by name.**
/// An emitter that quietly skipped a node it did not know would produce a
/// shader that is missing a term — visible as a slightly wrong colour, in
/// one backend, with nothing red; each translator's `visitUnknown` refuses
/// it instead (D24).
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show
        ExpressionBuiltin,
        ExpressionCall,
        ExpressionConditional,
        ExpressionConstant,
        ExpressionConstruct,
        ExpressionBinary,
        ExpressionNegate,
        ExpressionNot,
        ExpressionSwizzle,
        ExpressionType,
        ExpressionVariable,
        ExpressionVisitor,
        Expression,
        Flutter3dFormatException,
        MaterialParameterSchema,
        ParameterDeclaration;
import 'package:flutter3d_foundation/internal.dart'
    show applyExpressionOperator, broadcastExpressionArguments;
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show CompareFunction;

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
    this._block,
  });

  final String name;
  final ExpressionType type;

  /// As many numbers as [type] has components.
  final List<double> defaultValue;

  /// Declared with `uniform` rather than `param` — `P8`: not folded, but a
  /// member of the `MaterialParams` block, read from `RenderMaterial.parameters`
  /// on every draw, so a game sets it without a second entry point. A
  /// variant cannot set one; [defaultValue] is what a material that names
  /// no value is given.
  final bool uniform;

  /// The uniform block a [uniform] is a member of: [materialParametersBlock]
  /// unless the source names one of the material's own — `uniform(Hair)
  /// vec3 tint = …;`, version 2 (D21). Null for a `param`, which is in no
  /// block.
  String? get block => uniform ? _block ?? materialParametersBlock : null;
  final String? _block;
}

/// The block every `uniform` is a member of unless it names another, and
/// the one `RenderMaterial.parameterBlock` names by default.
const String materialParametersBlock = 'MaterialParams';

/// One texture slot the material samples, by the name the engine binds it
/// under.
final class MaterialTextureSlot {
  const MaterialTextureSlot(this.name, this.bindingName);

  /// What the source calls it.
  final String name;

  /// What the engine binds — `base_color_texture` and the rest — or, for a
  /// texture of the material's own ([isOwn], version 2), `material_<name>`,
  /// the name `RenderMaterial.extraTextures` hands it under.
  final String bindingName;

  /// Whether this is a texture of the material's own rather than one of the
  /// engine's five — `texture fur;` in a surface, version 2 (D21): a slot in
  /// the material's [MaterialSlotTable], which the emitted stage declares
  /// and each backend's binding plan binds.
  bool get isOwn => bindingName.startsWith(materialOwnTexturePrefix);
}

/// What the binding of a texture of a material's own starts with:
/// `texture fur;` is bound as `material_fur`.
const String materialOwnTexturePrefix = 'material_';

/// One value the fragment body can read.
///
/// The set is the intersection of what `surface.glsl`'s `Surface` carries and
/// what `cpu_shaders_surface.dart`'s `Surface` carries, which is the same
/// struct written twice — so an input here is a field both already have, never
/// something one side would have to compute.
final class MaterialInput {
  const MaterialInput(this.name, this.type, this.glsl, {required this.since});

  final String name;
  final ExpressionType type;

  /// The GLSL that reads it, given a `Surface s` in scope.
  final String glsl;

  /// The language version it arrived in: a source of an older `f3dmat N`
  /// neither reads it nor has the name taken from it.
  ///
  /// **How a minor adds an input without refusing a source that parsed
  /// before.** A name is refused for a declaration or a `let` only where the
  /// source's version has the input, so `let tangent = …` in an `f3dmat 3`
  /// file stays legal when a later version adds a `tangent` input. Required,
  /// so no entry of any list can be added without saying it.
  final int since;
}

/// Every input, and the single list of them.
///
/// The software backend's evaluator has to know each one by name, and a test
/// walks this list to check that it does — a backend that silently returned
/// zero for an input it had not heard of would draw a material that is subtly
/// wrong on one backend only.
const List<MaterialInput> materialInputs = <MaterialInput>[
  MaterialInput('albedo', ExpressionType.vec3, 's.albedo', since: 1),
  MaterialInput('alpha', ExpressionType.float, 's.alpha', since: 1),
  MaterialInput('normal', ExpressionType.vec3, 's.n', since: 1),
  MaterialInput('view', ExpressionType.vec3, 's.v', since: 1),
  MaterialInput('nDotV', ExpressionType.float, 's.n_dot_v', since: 1),
  MaterialInput('metallic', ExpressionType.float, 's.metallic', since: 1),
  MaterialInput('roughness', ExpressionType.float, 's.roughness', since: 1),
  MaterialInput('occlusion', ExpressionType.float, 's.occlusion', since: 1),
  MaterialInput('emissive', ExpressionType.vec3, 's.emissive', since: 1),
  MaterialInput('ambient', ExpressionType.vec3, 's.ambient', since: 1),
  MaterialInput('uv', ExpressionType.vec2, 'v_texcoord', since: 1),
  MaterialInput('world', ExpressionType.vec3, 'v_world_position', since: 1),
  // `P8`: an instance's own four numbers, `InstancedMeshNode.setInstanceData`
  // — nought for a draw that is not instanced. The emitted stage declares
  // the varying only when the source reads it.
  MaterialInput('instance', ExpressionType.vec4, 'v_instance', since: 1),
];

/// What the `light` block reads about the one light it is shading for, on
/// top of [materialInputs] — `P8`, the lighting hook.
///
/// `surface.glsl`'s `LightSample` and `cpu_shaders_lighting.dart`'s, the same
/// struct written twice, as the surface inputs are. Read only inside the
/// block: outside it there is no one light to read them of.
const List<MaterialInput> materialLightInputs = <MaterialInput>[
  MaterialInput('lightDir', ExpressionType.vec3, 'light.l', since: 1),
  MaterialInput('halfDir', ExpressionType.vec3, 'light.h', since: 1),
  MaterialInput('nDotL', ExpressionType.float, 'light.n_dot_l', since: 1),
  MaterialInput('nDotH', ExpressionType.float, 'light.n_dot_h', since: 1),
  MaterialInput('vDotH', ExpressionType.float, 'light.v_dot_h', since: 1),
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
  MaterialInput(
    'sceneDepth',
    ExpressionType.float,
    'f3d_scene_depth',
    since: 2,
  ),
  MaterialInput('viewDepth', ExpressionType.float, 'f3d_view_depth', since: 2),
  MaterialInput(
    'scenePosition',
    ExpressionType.vec3,
    'f3d_scene_position',
    since: 2,
  ),
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
  MaterialInput('position', ExpressionType.vec3, 'f3d_position', since: 2),
  MaterialInput(
    'objectNormal',
    ExpressionType.vec3,
    'f3d_object_normal',
    since: 2,
  ),
  MaterialInput('world', ExpressionType.vec3, 'f3d_world', since: 2),
  MaterialInput('normal', ExpressionType.vec3, 'f3d_normal', since: 2),
  MaterialInput('uv', ExpressionType.vec2, 'texcoord', since: 2),
  MaterialInput('color', ExpressionType.vec4, 'color', since: 2),
  MaterialInput(
    'origin',
    ExpressionType.vec3,
    'frame_info.model[3].xyz',
    since: 2,
  ),
];

/// What a `vertex` block may write, with `out name = value;` — version 2.
///
/// `position` is the vertex in the mesh's own space, which the model
/// transform then carries into the world; `world` is where it ends up, the
/// transform already applied; one or the other, not both. `normal` is the
/// world-space normal the surface is lit by. What the block does not write
/// keeps the engine's own answer.
const List<MaterialInput> materialVertexOutputs = <MaterialInput>[
  MaterialInput('position', ExpressionType.vec3, 'f3d_out_position', since: 2),
  MaterialInput('world', ExpressionType.vec3, 'f3d_out_world', since: 2),
  MaterialInput('normal', ExpressionType.vec3, 'f3d_out_normal', since: 2),
];

/// What an `ambient` block reads on top of [materialInputs] — version 2:
/// the level's baked light at this fragment, which the engine's own ambient
/// adds to the hemisphere.
const List<MaterialInput> materialAmbientInputs = <MaterialInput>[
  MaterialInput('lightmap', ExpressionType.vec3, 'f3d_lightmap', since: 2),
];

/// What a `composite` block reads on top of [materialInputs] — version 2:
/// the lights gathered through the `light` block, and the light the
/// `ambient` block (or the engine's own ambient) gave, neither yet under the
/// occlusion.
const List<MaterialInput> materialCompositeInputs = <MaterialInput>[
  MaterialInput('direct', ExpressionType.vec3, 'f3d_direct', since: 2),
  MaterialInput('indirect', ExpressionType.vec3, 'f3d_indirect', since: 2),
];

/// What a `fullscreen` stage's fragment body reads — version 2: where on the
/// screen it is, nought to one from the top left, and the depth the scene
/// left there along the view axis, in metres, a million where nothing was
/// drawn. The picture itself is the texture `scene`, read with
/// `sample(scene, uv)`.
const List<MaterialInput> materialFullscreenInputs = <MaterialInput>[
  MaterialInput('uv', ExpressionType.vec2, 'v_uv', since: 2),
  MaterialInput(
    'sceneDepth',
    ExpressionType.float,
    'f3d_scene_depth',
    since: 2,
  ),
];

/// What a `compute` stage's kernel reads — version 2: the texel of its
/// target this invocation writes, the target's size in texels, and the
/// texel's centre as nought to one.
const List<MaterialInput> materialComputeInputs = <MaterialInput>[
  MaterialInput('cell', ExpressionType.vec2, 'f3d_cell', since: 2),
  MaterialInput('size', ExpressionType.vec2, 'f3d_size', since: 2),
  MaterialInput('uv', ExpressionType.vec2, 'f3d_uv', since: 2),
];

/// What a source is — version 2 adds the two kinds after `material`.
///
/// * [surface], `material`: a surface the engine draws a mesh with.
/// * [fullscreen]: one full-screen fragment stage over the picture — what a
///   `FullscreenEffect` and a plugin's render step draw.
/// * [compute]: a kernel run once per texel of a storage texture it writes.
///
/// A `final class` with const instances, for [ExpressionType]'s reason.
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
  ExpressionType.vec3,
  'lit',
  since: 1,
);

/// The builtins a material may call, the sixteen versions 1 and 2 have:
/// `dot`, `length`, `normalize`, `mix`, `clamp`, `smoothstep`, `step`,
/// `pow`, `min`, `max`, `abs`, `sqrt`, `floor`, `fract`, `sin` and `cos`.
///
/// **Fewer than the expression language has**, because each one is also a
/// word every backend's shading language must have under the same name;
/// `exp` and `atan2` join when a version of the material language says so.
/// A name outside this list stays free for a `let`, as it always was.
const List<ExpressionBuiltin> materialBuiltins = <ExpressionBuiltin>[
  ExpressionBuiltin.dot,
  ExpressionBuiltin.length,
  ExpressionBuiltin.normalize,
  ExpressionBuiltin.mix,
  ExpressionBuiltin.clamp,
  ExpressionBuiltin.smoothstep,
  ExpressionBuiltin.step,
  ExpressionBuiltin.pow,
  ExpressionBuiltin.min,
  ExpressionBuiltin.max,
  ExpressionBuiltin.abs,
  ExpressionBuiltin.sqrt,
  ExpressionBuiltin.floor,
  ExpressionBuiltin.fract,
  ExpressionBuiltin.sin,
  ExpressionBuiltin.cos,
];

/// The language version each of [materialBuiltins] arrived in, by name:
/// all sixteen are version 1's. A builtin a later version adds is written
/// here with that version, and a source of an older one neither calls it
/// nor has the name taken from a `let` or a parameter of its own.
const Map<String, int> materialBuiltinVersions = <String, int>{
  'dot': 1,
  'length': 1,
  'normalize': 1,
  'mix': 1,
  'clamp': 1,
  'smoothstep': 1,
  'step': 1,
  'pow': 1,
  'min': 1,
  'max': 1,
  'abs': 1,
  'sqrt': 1,
  'floor': 1,
  'fract': 1,
  'sin': 1,
  'cos': 1,
};

/// The expression language's [ExpressionVisitor], with a method for each
/// kind a material adds: its inputs, parameters and `let`s, and `sample`.
///
/// **One tree, two languages.** A material's expressions are read by the
/// expression language's parser, so the arithmetic nodes are that
/// language's own ([ExpressionConstant], [ExpressionBinary] and the rest,
/// with [ExpressionType] for their types), and only what a material adds is
/// a kind of its own: [MaterialInputRef], [MaterialParamRef] and
/// [MaterialLocalRef], which are variables to a reader that knows only the
/// expression language, and [MaterialSample]. A kind a later minor adds (or
/// a plugin's own) arrives at [ExpressionVisitor.visitUnknown], so a
/// translator written against 1.0 keeps compiling and refuses the node by
/// name instead of breaking.
///
/// **This is the visitor of the expression language**, so a translator of
/// materials is a translator of that language with four methods more; the
/// three kinds a material never contains (a bare variable, `!` and `? :`)
/// answer [visitUnknown] unless a translator says otherwise.
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class MaterialExpressionVisitor<R> extends ExpressionVisitor<R> {
  const MaterialExpressionVisitor();

  R visitInputRef(MaterialInputRef expression);
  R visitParamRef(MaterialParamRef expression);
  R visitLocalRef(MaterialLocalRef expression);
  R visitSample(MaterialSample expression);

  /// A variable a material did not bind: none the parser makes.
  @override
  R visitVariable(ExpressionVariable expression) => visitUnknown(expression);

  /// `!`, which a material does not have.
  @override
  R visitNot(ExpressionNot expression) => visitUnknown(expression);

  /// `? :`, which a material does not have.
  @override
  R visitConditional(ExpressionConditional expression) =>
      visitUnknown(expression);
}

/// One of [materialInputs].
final class MaterialInputRef extends ExpressionVariable {
  MaterialInputRef(this.input) : super(input.name, input.type);

  final MaterialInput input;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) =>
      visitor is MaterialExpressionVisitor<R>
      ? visitor.visitInputRef(this)
      : visitor.visitVariable(this);
}

/// A declared parameter, before a variant has said what it is.
///
/// Kept as a reference through parsing and folded to a [ExpressionConstant] by
/// [specializeMaterial] — the source is parsed once and every variant is a
/// fold of the same tree, rather than a parse per variant that could differ in
/// some other way than the numbers.
final class MaterialParamRef extends ExpressionVariable {
  MaterialParamRef(this.parameter) : super(parameter.name, parameter.type);

  final MaterialParameter parameter;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) =>
      visitor is MaterialExpressionVisitor<R>
      ? visitor.visitParamRef(this)
      : visitor.visitVariable(this);
}

/// A `let` bound earlier in the body.
final class MaterialLocalRef extends ExpressionVariable {
  const MaterialLocalRef(super.name, super.type);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) =>
      visitor is MaterialExpressionVisitor<R>
      ? visitor.visitLocalRef(this)
      : visitor.visitVariable(this);
}

/// `sample(slot, uv)`.
///
/// Its own node rather than a [ExpressionBuiltin] because it is the one
/// expression that reads something outside the material: a builtin's
/// [ExpressionBuiltin.apply] takes numbers and returns numbers, and this one
/// needs whatever the backend binds textures with. A reader that knows only
/// the expression language meets it at [ExpressionVisitor.visitUnknown].
final class MaterialSample extends Expression {
  const MaterialSample(this.slot, this.uv) : super(ExpressionType.vec4);

  final MaterialTextureSlot slot;
  final Expression uv;

  @override
  R accept<R>(ExpressionVisitor<R> visitor) =>
      visitor is MaterialExpressionVisitor<R>
      ? visitor.visitSample(this)
      : visitor.visitUnknown(this);
}

/// One statement of a block: a `let`, a `return`, an `out`.
///
/// **An open set, read through a visitor**, for [Expression]'s
/// reason: a statement kind a later minor adds (or a plugin's own) arrives
/// at [MaterialStatementVisitor.visitUnknown], and a translator written
/// against 1.0 refuses it by name rather than breaking.
abstract base class MaterialStatement {
  const MaterialStatement();

  /// Hands this statement to the [visitor]'s method for its kind;
  /// [MaterialStatementVisitor.visitUnknown] by default.
  R accept<R>(MaterialStatementVisitor<R> visitor) =>
      visitor.visitUnknown(this);
}

/// Something that reads every kind of [MaterialStatement]. One abstract
/// method per kind 1.0 knows; a kind added later defaults to
/// [visitUnknown], as [MaterialExpressionVisitor] explains.
///
/// Extendable outside this package, and stays so through 1.x.
abstract base class MaterialStatementVisitor<R> {
  const MaterialStatementVisitor();

  R visitLet(MaterialLet statement);
  R visitReturn(MaterialReturn statement);
  R visitOutput(MaterialOutput statement);

  /// What a kind this visitor has no method for answers.
  R visitUnknown(MaterialStatement statement);
}

/// `let name = expr;` — single assignment, so nothing here is a variable.
final class MaterialLet extends MaterialStatement {
  const MaterialLet(this.name, this.value);

  final String name;
  final Expression value;

  @override
  R accept<R>(MaterialStatementVisitor<R> visitor) => visitor.visitLet(this);
}

/// `return expr;` — a `vec4`, rgb being the light the surface emits and a its
/// opacity, which is what `WriteSurface` takes.
final class MaterialReturn extends MaterialStatement {
  const MaterialReturn(this.value);

  final Expression value;

  @override
  R accept<R>(MaterialStatementVisitor<R> visitor) => visitor.visitReturn(this);
}

/// `out name = expr;` — one of [materialVertexOutputs], written by a
/// `vertex` block — version 2. Each at most once, and the block's only way
/// to say anything: it has no `return`.
final class MaterialOutput extends MaterialStatement {
  const MaterialOutput(this.output, this.value);

  final MaterialInput output;
  final Expression value;

  @override
  R accept<R>(MaterialStatementVisitor<R> visitor) => visitor.visitOutput(this);
}

/// One step of a material's `updates` block — language version 3: how a
/// parameter value written for a version before [version] changes on the
/// way to it.
///
/// **An open set**: an `abstract base class` whose kinds each say what they
/// do in [apply], so a kind a later minor adds (a unit change, a split of
/// one parameter into two) needs nothing of a reader but to call it.
abstract base class MaterialUpdate {
  const MaterialUpdate(this.version);

  /// The material version this step leads to: it applies to a value
  /// written for any version before it.
  final int version;

  /// [values], keyed by parameter name, after this step. May return
  /// [values] itself, changed.
  Map<String, List<double>> apply(Map<String, List<double>> values);
}

/// `2: rename ink -> inkColor;` — the value of [from] is [to]'s from
/// [version] on.
final class MaterialRenameUpdate extends MaterialUpdate {
  const MaterialRenameUpdate(super.version, this.from, this.to);

  final String from;
  final String to;

  @override
  Map<String, List<double>> apply(Map<String, List<double>> values) {
    final value = values.remove(from);
    if (value != null) values[to] = value;
    return values;
  }

  @override
  String toString() => '$version: rename $from -> $to';
}

/// `3: scale roughness 0.5;` — every component of [name]'s value is
/// multiplied by [factor] from [version] on: a parameter whose meaning
/// changed scale (a roughness that became perceptual, a size in another
/// unit).
final class MaterialScaleUpdate extends MaterialUpdate {
  const MaterialScaleUpdate(super.version, this.name, this.factor);

  final String name;

  /// What the value is multiplied by: a pure number, a fraction or a
  /// multiple.
  final double factor;

  @override
  Map<String, List<double>> apply(Map<String, List<double>> values) {
    final value = values[name];
    if (value != null) {
      values[name] = <double>[for (final v in value) v * factor];
    }
    return values;
  }

  @override
  String toString() => '$version: scale $name $factor';
}

/// `4: remove sheen;` — [name] has no meaning from [version] on, and an
/// instance's value for it is dropped rather than kept for a parameter
/// that a later version may declare again with another meaning.
final class MaterialRemoveUpdate extends MaterialUpdate {
  const MaterialRemoveUpdate(super.version, this.name);

  final String name;

  @override
  Map<String, List<double>> apply(Map<String, List<double>> values) =>
      values..remove(name);

  @override
  String toString() => '$version: remove $name';
}

/// The material language version of a file with no `f3dmat` line: every
/// file written before the line existed.
const int materialLanguageFirstVersion = 1;

/// The version of a material that says none (`material Hatch { … }` rather
/// than `material Hatch version 3 { … }`), and of an instance that
/// predates material versions. A material's versions count from it.
const int firstMaterialVersion = 1;

/// An instance written for a version of a material this build does not
/// have: a newer one, or none at all.
final class MaterialVersionException extends Flutter3dFormatException {
  const MaterialVersionException(this.material, this.written, this.current);

  /// The material's name.
  final String material;

  /// The version the instance says it was written for.
  final int written;

  /// The version the material is at in this build.
  final int current;

  @override
  String get message => written < firstMaterialVersion
      ? 'an instance of "$material" says it was written for version '
            '$written, and versions count from $firstMaterialVersion'
      : 'an instance of "$material" was written for its version $written, '
            'and this build has version $current: update the material, or '
            'the build, to one that has version $written';

  @override
  String toString() => 'MaterialVersionException: $message';
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
    this.languageVersion = materialLanguageFirstVersion,
    this.kind = MaterialStageKind.surface,
    this.state = MaterialFileState.none,
    this.vertex,
    this.ambient,
    this.composite,
    this.workgroupSize = (8, 8),
    this.version = firstMaterialVersion,
    this.updates = const <MaterialUpdate>[],
  });

  final String name;

  /// What the source declares a draw may set, or folds: each `uniform` and
  /// `param`, with its width and default. A source says no unit yet, so
  /// none is filled in.
  MaterialParameterSchema get schema =>
      MaterialParameterSchema(<ParameterDeclaration>[
        for (final parameter in parameters)
          ParameterDeclaration(
            parameter.name,
            components: parameter.type.components,
            defaultValue: List<double>.unmodifiable(parameter.defaultValue),
            isUniform: parameter.uniform,
          ),
      ]);

  /// The material language version the source was written in: its
  /// `f3dmat <version>` line, or 1 when it has none. See
  /// `materialLanguageVersion`.
  final int languageVersion;

  /// The material's own version — `material Hatch version 3 { … }`,
  /// language version 3 — or 1 for a material that says none.
  ///
  /// Not the language's: this counts the changes to one material's
  /// parameters (a rename, a new scale), so that what a level or a saved
  /// instance set for an older version is carried forward by [updates]
  /// rather than silently read under the new meaning.
  final int version;

  /// How a parameter value written for an older [version] becomes one for
  /// this version, in the order the `updates` block says them; [lift]
  /// applies them.
  final List<MaterialUpdate> updates;

  /// [values], parameter values an instance set for version [from] of this
  /// material, carried to [version] through every update after [from], in
  /// version order and, within a version, in the order written.
  ///
  /// A value no update names is kept as it is, under its name, so a value
  /// for a parameter this material no longer has is still there for its
  /// reader to report. Throws [MaterialVersionException] for a [from] newer
  /// than [version] or below 1: an instance from a newer material cannot be
  /// read back into an older one.
  Map<String, List<double>> lift(
    Map<String, List<double>> values, {
    required int from,
  }) {
    if (from > version || from < firstMaterialVersion) {
      throw MaterialVersionException(name, from, version);
    }
    // By version, and within a version in the order written.
    final ordered =
        <(int, MaterialUpdate)>[
          for (final (index, update) in updates.indexed)
            if (update.version > from) (index, update),
        ]..sort(
          (a, b) => a.$2.version != b.$2.version
              ? a.$2.version.compareTo(b.$2.version)
              : a.$1.compareTo(b.$1),
        );
    return ordered.fold(
      Map<String, List<double>>.of(values),
      (lifted, step) => step.$2.apply(lifted),
    );
  }

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
  const MaterialVariant(this.name, {this.values = const {}});

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

  final folder = _Folder(variant);
  List<MaterialStatement> fold(
    List<MaterialStatement> body,
  ) => <MaterialStatement>[
    for (final statement in body) statement.accept(_StatementFolder(folder)),
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
    version: program.version,
    updates: program.updates,
  );
}

/// Each statement with its expression folded by [folder].
final class _StatementFolder
    extends MaterialStatementVisitor<MaterialStatement> {
  const _StatementFolder(this.folder);

  final _Folder folder;

  @override
  MaterialStatement visitLet(MaterialLet statement) =>
      MaterialLet(statement.name, statement.value.accept(folder));

  @override
  MaterialStatement visitReturn(MaterialReturn statement) =>
      MaterialReturn(statement.value.accept(folder));

  @override
  MaterialStatement visitOutput(MaterialOutput statement) =>
      MaterialOutput(statement.output, statement.value.accept(folder));

  @override
  MaterialStatement visitUnknown(MaterialStatement statement) =>
      throw ArgumentError.value(
        statement,
        'statement',
        'not a statement this build of the material language knows',
      );
}

/// An expression with a variant's parameters folded in, and every subtree
/// that is then constant collapsed to a [ExpressionConstant].
final class _Folder extends MaterialExpressionVisitor<Expression> {
  const _Folder(this.variant);

  final MaterialVariant variant;

  @override
  Expression visitConstant(ExpressionConstant expression) => expression;

  @override
  Expression visitInputRef(MaterialInputRef expression) => expression;

  @override
  Expression visitLocalRef(MaterialLocalRef expression) => expression;

  // A uniform stays a reference: its value arrives with each draw.
  @override
  Expression visitParamRef(MaterialParamRef expression) {
    final parameter = expression.parameter;
    if (parameter.uniform) return expression;
    return ExpressionConstant(
      variant.values[parameter.name] ?? parameter.defaultValue,
      parameter.type,
    );
  }

  @override
  Expression visitConstruct(ExpressionConstruct expression) {
    final folded = <Expression>[
      for (final argument in expression.arguments) argument.accept(this),
    ];
    if (folded.every((f) => f is ExpressionConstant)) {
      return ExpressionConstant(<double>[
        for (final f in folded) ...(f as ExpressionConstant).value,
      ], expression.type);
    }
    return ExpressionConstruct(folded, expression.type);
  }

  @override
  Expression visitSwizzle(ExpressionSwizzle expression) {
    final folded = expression.target.accept(this);
    if (folded is ExpressionConstant) {
      return ExpressionConstant(<double>[
        for (final index in expression.components) folded.value[index],
      ], expression.type);
    }
    return ExpressionSwizzle(folded, expression.components, expression.type);
  }

  @override
  Expression visitNegate(ExpressionNegate expression) {
    final folded = expression.operand.accept(this);
    if (folded is ExpressionConstant) {
      return ExpressionConstant(<double>[
        for (final component in folded.value) -component,
      ], folded.type);
    }
    return ExpressionNegate(folded);
  }

  @override
  Expression visitBinary(ExpressionBinary expression) {
    final a = expression.left.accept(this);
    final b = expression.right.accept(this);
    if (a is ExpressionConstant && b is ExpressionConstant) {
      return ExpressionConstant(
        applyBinary(expression.op, a.value, b.value),
        expression.type,
      );
    }
    return ExpressionBinary(expression.op, a, b, expression.type);
  }

  @override
  Expression visitCall(ExpressionCall expression) {
    final folded = <Expression>[
      for (final argument in expression.arguments) argument.accept(this),
    ];
    if (folded.every((f) => f is ExpressionConstant)) {
      return ExpressionConstant(
        expression.builtin.apply(
          broadcastArguments(<List<double>>[
            for (final f in folded) (f as ExpressionConstant).value,
          ], expression.builtin),
        ),
        expression.type,
      );
    }
    return ExpressionCall(expression.builtin, folded, expression.type);
  }

  @override
  Expression visitSample(MaterialSample expression) =>
      MaterialSample(expression.slot, expression.uv.accept(this));

  @override
  Expression visitUnknown(Expression expression) => throw ArgumentError.value(
    expression,
    'expression',
    'not an expression this build of the material language knows',
  );
}

/// `+ - * /` on two values, with GLSL's broadcasting: the expression
/// language's [applyExpressionOperator].
///
/// Exported because the software backend evaluates the same operators and a
/// second implementation of "what does vec3 * float mean" is exactly the drift
/// this language exists to remove.
List<double> applyBinary(String op, List<double> a, List<double> b) =>
    applyExpressionOperator(op, a, b);

/// Spreads a one-component argument across the widest one, for the builtins
/// that take a float beside a vector: the expression language's
/// [broadcastExpressionArguments].
List<List<double>> broadcastArguments(
  List<List<double>> arguments,
  ExpressionBuiltin builtin,
) => broadcastExpressionArguments(arguments, builtin);
