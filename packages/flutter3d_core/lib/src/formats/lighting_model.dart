import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        NameTakenException,
        PluginException,
        PluginRegistry,
        PluginScope,
        Registration;

import 'material_extensions.dart';
import 'material_language/material_slots.dart';

/// A lighting model: one pre-built fragment shader and what the engine may
/// bind to it.
///
/// **A value class rather than an enum, so this list is not closed.** Shaders
/// are compiled ahead of time, so a material graph cannot be assembled at run
/// time — but an application that builds its own bundle can add an entry to it
/// and describe it here, and the renderer will cache a pipeline for it like any
/// other. What it cannot do is add a shader to a bundle it does not build; that
/// is the remaining limit, and it belongs to the bundle rather than to this
/// type.
///
/// Two properties used to be derived by comparing against particular constants,
/// which is the sort of thing that works exactly until somebody adds a seventh
/// model. They are declared now.
///
/// Shaders are compiled ahead of time into the bundle, so a material graph
/// cannot be assembled at runtime. Switching models therefore means switching
/// shader — and switching shader means a different `RenderPipeline`, which is
/// why the renderer caches pipelines by [shaderName].
///
/// The `uses…` flags are declared rather than detected. Shader reflection cannot
/// answer the question: it reports a uniform block as present because the GLSL
/// *declared* it, even when the compiled shader binds no buffer for it, and
/// binding that phantom block segfaults inside Metal with no Dart stack trace.
/// The same applies to samplers — the compiler drops one whose result never
/// reaches the output, which is why Lambert does not sample the metal-rough map
/// even though the header declares it.
///
/// The truth is printed by `tool/build_shaders.sh` after every build, as a table
/// of what each entry point actually kept. When this metadata and that table
/// disagree, the table is right.
///
/// **And since 0.8.0 the table is what binds — `gfx-92n`.** Every backend hands
/// the engine's own stages that table as `ShaderHandle.kept`, the renderer asks
/// it first, and an encoder refuses anything it names as dropped. The binding
/// flags below are the answer only for a stage the device cannot answer for —
/// one from an application's own bundle, or a material language stage — and
/// on the built-in models they are the fallback a device without the table
/// would use. `usesMaterialParameters` and `usesMetallic` are not about
/// binding at all: they tell an editor which controls do something.
final class LightingModel {
  /// A model shown as [label] and drawn with the fragment stage
  /// [shaderName]; the flags default to what a lit stage binds. Asserts
  /// that a model sampling the metallic-roughness map samples the material
  /// maps.
  const LightingModel(
    this.label,
    this.shaderName, {
    this.vertexShaderName,
    this.usesFragInfo = true,
    this.usesAlbedoTexture = true,
    this.usesMaterialMaps = true,
    this.usesMetallicRoughnessMap = true,
    this.usesMaterialParameters = true,
    this.usesMetallic = false,
    this.usesEnvironment = false,
    this._usesLightList,
    this._usesFogInfo,
    this.vertexStageMorphs = true,
    this.usesSceneDepth = false,
    this.vertexStageInDepthPasses = false,
    this.slots = MaterialSlotTable.none,
    this.vertexVariants = const <VertexStageVariant>{},
    this.lightTypeMembers = const <String, String>{},
  }) : assert(
         !usesMetallicRoughnessMap || usesMaterialMaps,
         'the metallic-roughness map is one of the material maps, so a model '
         'that samples no maps cannot sample it either. Getting this pair '
         'wrong is not a warning at run time: the renderer binds a texture '
         'the compiled shader has no slot for, and the bind fails. Unlit sat '
         'in exactly that state until a golden caught it.',
       );

  /// The base colour as it is, with no light: no material maps, no
  /// parameters.
  static const LightingModel unlit = LightingModel(
    'Unlit',
    'Unlit',
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );

  /// [unlit] with the surface buffer taken away, and the x-ray stage's alone.
  ///
  /// **Deliberately absent from [builtIn]**, which is the list a picker offers
  /// and `fmat` writes a material's shader name from. This is not a way to
  /// light a material; it is the fragment stage
  /// `renderer_xray_pass.dart` draws its two extra passes with, and a material
  /// asking for it in a scene file would be asking for a surface that lies
  /// about itself to every screen-space effect. The flags match [unlit]
  /// exactly, because `xray.frag` is `unlit.frag` with one `#define` in front
  /// of it.
  static const LightingModel xray = LightingModel(
    'X-ray',
    'Xray',
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );

  /// A planar reflector's surface drawn again with the mirrored picture over
  /// it — `P4`, the stage `renderer_planar_pass.dart` draws with.
  ///
  /// Absent from [builtIn] for [xray]'s reason: it is not a way to light a
  /// material but a second draw over one, and a material asking for it would
  /// be a surface with nothing under its reflection. It reads no maps, no
  /// lights and no `FragInfo` — the eye is the fog block's — and declares no
  /// surface buffer, so it leaves what the surface below it wrote there.
  static const LightingModel planarReflection = LightingModel(
    'Planar reflection',
    'PlanarReflection',
    usesFragInfo: false,
    usesFogInfo: true,
    usesAlbedoTexture: false,
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );

  /// A line of constant screen width — `gfx-86n`: [unlit]'s fragment stage
  /// behind the engine's own `PolylineVertex`, which widens `buildPolyline`'s
  /// geometry by the number of pixels each point carries.
  ///
  /// **Unlit on purpose.** A route drawn over terrain is a mark on a map
  /// rather than a surface in the world, and a lit band would darken where the
  /// ground turns away from the sun — the gradient an application draws with
  /// per-point colour would come back as that colour times a shadow term
  /// nobody asked for. The vertex colour is multiplied into the albedo by
  /// `ReadSurface`, so the colour at each point is the colour on screen.
  ///
  /// Absent from [builtIn] for the reason [xray] is: it is not a way to light
  /// a model, and a picker offering it would offer to draw a cube as a line.
  static const LightingModel polyline = LightingModel(
    'Polyline',
    'Unlit',
    vertexShaderName: 'PolylineVertex',
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
    vertexStageMorphs: false,
  );

  /// An octahedral impostor's card — `C4`: its own `ImpostorVertex`, which
  /// turns the card to the eye, and the `Impostor` stage, which reads the
  /// albedo atlas from the base colour slot and the normal-depth atlas from
  /// the normal map slot and lights the result diffusely.
  ///
  /// Absent from [builtIn] for the reason [polyline] is: it draws one kind of
  /// geometry, and a picker offering it would offer to draw a cube as a card.
  static const LightingModel impostor = LightingModel(
    'Impostor',
    'Impostor',
    vertexShaderName: 'ImpostorVertex',
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
    vertexStageMorphs: false,
  );

  /// Diffuse light alone, no highlight; samples no metallic-roughness map.
  static const LightingModel lambert = LightingModel(
    'Lambert',
    'Lambert',
    usesMetallicRoughnessMap: false,
  );

  /// Diffuse light and a Blinn-Phong highlight.
  static const LightingModel blinnPhong = LightingModel(
    'Blinn-Phong',
    'BlinnPhong',
  );

  /// glTF's metal-rough model with a GGX highlight, reading metallic and
  /// the environment light.
  static const LightingModel pbr = LightingModel(
    'PBR (GGX)',
    'Pbr',
    usesMetallic: true,
    usesEnvironment: true,
  );

  /// [pbr] with the layers glTF adds on top of it — `M1`–`M3`: a clear coat,
  /// a specular strength and tint, an index of refraction, a sheen,
  /// anisotropy, transmission through a volume, dispersion and a thin film.
  /// See
  /// `MaterialExtensions` for what each is.
  ///
  /// **A model of its own rather than a branch in [pbr]**, so a plain
  /// metal-rough surface keeps its cost and its samplers: the layered stage
  /// reads a block and a packed coat map the plain one never declares, and
  /// the lit stages have two samplers left under WebGL2's sixteen. It is
  /// `pbr.frag` compiled a second time with `F3D_LAYERED` defined, so the
  /// two cannot drift apart below the layers. A loader hands it to a
  /// material whose layers change its shading; with every layer at its
  /// default it draws what [pbr] draws.
  ///
  /// Absent from [builtIn], for the reason [xray] is: it is not a choice a
  /// picker offers, it is what a material's own layers ask for.
  static const LightingModel pbrLayered = LightingModel(
    'PBR (layered)',
    'PbrLayered',
    usesMetallic: true,
    usesEnvironment: true,
  );

  /// Cel shading: the light in a few hard bands and a rim.
  ///
  /// **Owned by `flutter3d_post/style.dart`**, whose `toonLighting` is this same
  /// constant and whose `ToonLightingAddon` registers it through
  /// [LightingModels] as any plugin's model is registered. Kept here as a
  /// stable alias and in [builtIn] for the whole of 1.x, because its stages
  /// are still compiled into every backend's engine bundle and the CPU
  /// rasteriser, and documents written since 0.1 name `Toon` without any
  /// addon: a material asking for it reads and draws with or without the
  /// addon installed. The stages leave the engine bundle with 2.0.
  static const LightingModel toon = LightingModel('Toon', 'Toon');

  /// A debug view: the surface normal drawn as a colour, binding nothing
  /// of the material.
  static const LightingModel normals = LightingModel(
    'Normals',
    'Normals',
    usesFragInfo: false,
    usesAlbedoTexture: false,
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );

  /// Every value this version names, in declaration order. A later
  /// version appends; nothing is removed or renamed within a major.
  static const List<LightingModel> values = <LightingModel>[
    unlit,
    xray,
    planarReflection,
    polyline,
    impostor,
    lambert,
    blinnPhong,
    pbr,
    pbrLayered,
    toon,
    normals,
  ];

  /// The built-in model a document calls [name], or null for a name this
  /// version does not know, which is what a file written by a later
  /// version can carry.
  static LightingModel? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The word a document names this model by: `<namespace>.<Name>` for a
  /// plugin's (`acme_ink.Ink`), whose [shaderName] is `<namespace>__<Name>`
  /// ([shaderNameOf]); the [shaderName] itself for a built-in model and one
  /// an application describes from its own bundle (`Pbr`).
  ///
  /// **A name like every other registration's**, with the dot a shader's
  /// entry point cannot carry made `__` in the stage, so the two are one
  /// word spelled twice. `__` is refused in plugin ids and in model names
  /// (`PluginManifest.idProblem`, [LightingModels.register]), which keeps
  /// the spelling one to one: `acme` + `ink__Glow` and `acme_ink` + `Glow`
  /// cannot both exist.
  String get name => switch (shaderName.lastIndexOf('__')) {
    -1 => shaderName,
    final at =>
      '${shaderName.substring(0, at)}.${shaderName.substring(at + 2)}',
  };

  /// The [shaderName] a model called [name] is compiled under: every `.`
  /// made `__`, so `acme_ink.Ink` is the stage `acme_ink__Ink`, and its
  /// vertex stages `acme_ink__InkVertex` and so on.
  static String shaderNameOf(String name) => name.replaceAll('.', '__');

  /// The models this engine ships, in the order a picker should show them.
  ///
  /// `builtIn` and not `values`: there is no longer a complete list to have.
  /// The name says which question it answers — "what came with the engine" —
  /// rather than implying nothing else can exist.
  static const List<LightingModel> builtIn = <LightingModel>[
    unlit,
    lambert,
    blinnPhong,
    pbr,
    toon,
    normals,
  ];

  /// The model a surface with [layers] is drawn with, when it asked for this
  /// one: [pbrLayered] in place of [pbr] when a layer changes the shading,
  /// and this model unchanged otherwise — `M1`. Every other model has no
  /// layered form, and a surface that picked one keeps it.
  ///
  /// [textureTransforms] asks for the layered model too — `C8`: it is the
  /// one that reads a transform per map at the sampler.
  LightingModel withLayers(
    MaterialExtensions? layers, {
    bool textureTransforms = false,
  }) => identical(this, pbr) && ((layers?.shades ?? false) || textureTransforms)
      ? pbrLayered
      : this;

  /// Shown in the UI.
  final String label;

  /// Entry name inside whichever bundle the backend supplied.
  ///
  /// This is the contract the engine cannot abstract away: it names shaders,
  /// and every backend must ship a bundle containing them under these names.
  /// Every backend package lists them in its own bundle manifest, and a
  /// backend that answers to a name the engine does not ask for is unused
  /// weight while one that misses a name the engine does ask for fails at
  /// `Renderer.create`, which names the missing entry.
  final String shaderName;

  /// The vertex stage this material brings with it, or null for the engine's
  /// own — `gfx-75n`.
  ///
  /// **The seam a material could not reach across.** Everything above names a
  /// *fragment* stage; the vertex side was `MeshVertex` and `MeshSkinnedVertex`
  /// by fixed name, so vertex displacement, an ocean, wind and a per-material
  /// morph hook were all outside what a material could express — not a missing
  /// feature in a table, but the thing that decides whether somebody writes an
  /// effect or forks the engine.
  ///
  /// **One name, two stages.** A skinned draw needs the skinned variant, and a
  /// material that named only one would draw correctly on a prop and put a
  /// character back in its bind pose. So the name given here is the unskinned
  /// entry point and `'${vertexShaderName}Skinned'` is the skinned one, the
  /// same relationship `MeshVertex` and `MeshSkinnedVertex` already have. A
  /// material drawn only on unskinned geometry need not ship the second; the
  /// renderer asks for it when a skinned draw reaches it and says which name it
  /// wanted when the bundle has not got it.
  ///
  /// Instanced and lightmapped draws keep the engine's stages unless the
  /// material lists them in [vertexVariants]. Both read a second buffer whose
  /// layout the engine declares — the instance rows, the lightmap coordinate
  /// — so a stage of one's own for them is written against that layout
  /// (`MeshVertexLayouts.instanced`), and says so by listing the variant.
  ///
  /// The stage must write the varyings the fragment side reads and take the
  /// same `FrameInfo` block. `MeshVertex` in `flutter3d_shaders` is the
  /// reference, and `mesh_displace.vert` beside it is the smallest thing that
  /// is not a copy of it.
  final String? vertexShaderName;

  /// Whether the shader reads the `FragInfo` uniform block.
  final bool usesFragInfo;

  /// Whether the shader samples `base_color_texture`.
  final bool usesAlbedoTexture;

  /// Whether the shader samples the normal, occlusion and emissive maps.
  ///
  /// The three travel together: every lit model applies all of them, and no
  /// unlit or debug model applies any.
  final bool usesMaterialMaps;

  /// Whether the shader samples `shadow_texture`.
  ///
  /// The same set as [usesMaterialMaps] today — every lit model shadows and no
  /// debug model does — but kept separate because the two answer different
  /// questions and will diverge the moment an unlit-but-shadowed model exists.
  bool get usesShadowMap => usesMaterialMaps;

  /// Whether the shader reads the `PointShadow` block and the two cube atlases.
  ///
  /// The same set again, and for the same reason kept its own name. It is a
  /// separate flag rather than a reuse because it was missing entirely: point
  /// shadows were added binding the block and both atlases to every model with
  /// a [usesFragInfo], which includes Unlit — and the compiled Unlit shader
  /// keeps none of the three, since it calls no lighting loop to reach them.
  /// The build script's table is what says so, and `lighting-unlit` is what
  /// noticed.
  bool get usesPointShadow => usesMaterialMaps;

  /// Whether the shader reads the light list: the `LightListInfo` block and
  /// `light_list_texture`.
  ///
  /// The same set once more, and again its own name because it was missing.
  /// The list was bound to every draw, and Unlit keeps neither half: it
  /// accumulates no lights, so the compiled Metal function has no index for
  /// either, and binding them crashed inside the driver on the first frame of
  /// any scene with an unlit or polyline material. Vulkan took the same bind
  /// without complaint.
  ///
  /// Defaults to [usesMaterialMaps], which is right for every model this
  /// package ships. A stage that samples maps and still gathers no lights,
  /// such as one emitted from the material language, says `false`.
  bool get usesLightList => _usesLightList ?? usesMaterialMaps;
  final bool? _usesLightList;

  /// Whether the shader reads the `FogInfo` block: the fog, the eye, and the
  /// view axis the surface buffer measures depth along.
  ///
  /// `lib/color.glsl` declares it, so a stage that writes its colour through
  /// `WriteSurface` keeps it whether or not it reads `FragInfo`. It was bound
  /// only beside `FragInfo`, and a stage of one's own that reads no material
  /// inputs was drawn with the block unbound: no fog, and a surface depth of
  /// nought. WebGL2 named it at every draw of the `loaded-shader` golden.
  ///
  /// Defaults to [usesFragInfo], which is right for every model this package
  /// ships; the engine's own stages are answered by their compiled bindings
  /// anyway. A stage of one's own that includes `color.glsl` and skips
  /// `FragInfo` says `true`.
  bool get usesFogInfo => _usesFogInfo ?? usesFragInfo;
  final bool? _usesFogInfo;

  /// Whether the material's own vertex stage declares the morph block and
  /// texture, and so has to be handed them on every draw.
  ///
  /// **True by default**, because a stage of one's own is written from
  /// `MeshVertex`, and `mesh.vert` includes `lib/morph.glsl`: the block and the
  /// sampler are declared whether or not the node morphs, and a stage that
  /// declares them and is not handed them reads another draw's weights on the
  /// software backend and garbage on WebGL, and is a native failure on Metal.
  /// False for [polyline], whose `PolylineVertex` declares neither; binding
  /// the texture to it is a thrown "Failed to bind texture" on Impeller.
  /// Ignored when [vertexShaderName] is null: the engine's own mesh stages all
  /// declare them.
  final bool vertexStageMorphs;

  /// Whether the fragment stage reads the scene behind it — the material
  /// language's `sceneDepth` and `scenePosition`, version 2: the
  /// `scene_depth_texture` sampler and the `SceneDepthInfo` block.
  ///
  /// **A binding flag, for [usesEnvironment]'s reason**: a sampler bound to
  /// a stage that has none, or declared and left unbound, is a native crash
  /// on Metal. It also moves the draw: a surface reading the scene is drawn
  /// after the opaque half, in a pass where the surface buffer is bound
  /// rather than attached — the one soft particles are drawn in. False for
  /// every model the engine ships.
  final bool usesSceneDepth;

  /// Whether the depth pre-draw and the shadow passes draw through
  /// [vertexShaderName] too, rather than through the engine's own mesh
  /// stage — the material language's `vertex` block, version 2.
  ///
  /// **So that geometry the stage moves casts the shadow it draws.** False
  /// by default, which is what every stage written before the block had: a
  /// polyline widened on screen, or a card turned to the eye, means nothing
  /// to a light. Ignored when [vertexShaderName] is null.
  final bool vertexStageInDepthPasses;

  /// The variants of [vertexShaderName] this material ships beyond the
  /// plain and the skinned stage, each `<vertexShaderName><suffix>` (D22b).
  ///
  /// **What lets a material's vertex stage reach instanced and lightmapped
  /// geometry.** Those draws read a second buffer whose layout the engine
  /// declares — `MeshVertexLayouts.instanced` for the instance rows, the
  /// lightmap coordinate for a baked level — and a stage that declares it
  /// draws them: an instanced draw of this material goes through
  /// `<name>Instanced` when [VertexStageVariant.instanced] is here, and a
  /// lightmapped one through `<name>Lightmapped`. Without them both keep the
  /// engine's stages, as before. Ignored when [vertexShaderName] is null.
  final Set<VertexStageVariant> vertexVariants;

  /// The members of the stage's `MaterialParams` that hold a light type's
  /// code, each to the type's name (`acme.tube`) — a `lighttype`
  /// declaration of the material language, version 3. The renderer fills
  /// each on every draw with the code it gave that type
  /// (`LightTypes.codeNamed`), minus one where no hook packs it, since codes
  /// are handed out per renderer and no stage could be compiled with one.
  final Map<String, String> lightTypeMembers;

  /// What the stage binds beyond the engine's own blocks and samplers: its
  /// uniform blocks — `MaterialParams` and blocks of its own — and its own
  /// textures, in the order a backend numbers them (D21).
  ///
  /// **What lets a plugin's lit model bring more than the engine's five
  /// textures.** The renderer binds each block from
  /// `RenderMaterial.parameters`, the members that belong to it, and each
  /// texture from `RenderMaterial.extraTextures` under its binding. Empty for
  /// every model the engine ships and for one described by hand, which
  /// binds `RenderMaterial.parameterBlock` as it always did.
  final MaterialSlotTable slots;

  /// Whether the shader samples `metallic_roughness_texture`.
  ///
  /// Separate from [usesMaterialMaps] because Lambert is purely diffuse: it has
  /// no response to metallic or roughness, so the compiler drops the sampler
  /// and the engine must not try to bind it.
  final bool usesMetallicRoughnessMap;

  /// Whether the material's numeric parameters reach the shader, so a UI can
  /// disable the sliders that would do nothing.
  ///
  /// Declared rather than derived. It used to read `this != unlit && this !=
  /// normals`, which was true of the six models that existed and wrong for any
  /// seventh — a custom model would have been told its own parameters mattered
  /// because it was not one of two names.
  final bool usesMaterialParameters;

  /// A small stable number for grouping draws that share a pipeline.
  ///
  /// **Not `shaderName.hashCode`.** Dart does not promise a string's hash is
  /// the same from one run to the next, and the draw sort uses this — so the
  /// order two lighting models are drawn in would have varied between runs.
  /// Two goldens caught it at 25% and 0.6% of their pixels, which is what a
  /// nondeterministic sort looks like once anything blends.
  ///
  /// FNV-1a over the name, folded to six bits, because that is what the key has
  /// room for. A collision costs one extra pipeline switch and nothing else:
  /// grouping is an optimisation, and the key is allowed to be approximate
  /// about it in a way it is not allowed to be unstable about.
  int get pipelineGroup {
    var hash = 0x811c9dc5;
    for (var i = 0; i < shaderName.length; i++) {
      hash = ((hash ^ shaderName.codeUnitAt(i)) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x3F;
  }

  /// Whether the shader interprets metallic. Only a physical model does.
  ///
  /// Declared for the same reason: `this == pbr` answered a question about the
  /// shader by checking which constant it happened to be.
  final bool usesMetallic;

  /// Whether the shader declares the environment cube and samples it.
  ///
  /// Only the physical model does: image-based lighting is an answer to the
  /// rendering equation, and Lambert, Blinn-Phong and toon are not asking it.
  ///
  /// The renderer binds by this flag rather than by which constant a material
  /// holds, for the reason above it — and because binding a texture a compiled
  /// shader has no slot for is a native crash, not a no-op.
  final bool usesEnvironment;
}

/// A variant of a material's own vertex stage, for geometry that reads
/// more than the standard vertex (D22b).
///
/// An open set (S0): a class with constants, so a variant a later minor adds
/// (a morphed stage, a stage for points) breaks no `switch`.
final class VertexStageVariant {
  const VertexStageVariant._(this.name, this.suffix);

  /// A skinned draw: joints and weights beside the standard vertex. Every
  /// material stage has it, as `<name>Skinned`; listed for completeness.
  static const VertexStageVariant skinned = VertexStageVariant._(
    'skinned',
    'Skinned',
  );

  /// An instanced draw: the instance rows in a second buffer, stepped per
  /// instance — `MeshVertexLayouts.instanced`.
  static const VertexStageVariant instanced = VertexStageVariant._(
    'instanced',
    'Instanced',
  );

  /// A lightmapped draw: a level's baked coordinate beside the standard
  /// vertex.
  static const VertexStageVariant lightmapped = VertexStageVariant._(
    'lightmapped',
    'Lightmapped',
  );

  /// Every variant this version names, in declaration order.
  static const List<VertexStageVariant> values = <VertexStageVariant>[
    skinned,
    instanced,
    lightmapped,
  ];

  /// The variant called [name], or null for one this version does not know.
  static VertexStageVariant? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  /// What the stage's entry point adds to the material's vertex stage name.
  final String suffix;

  @override
  String toString() => 'VertexStageVariant.$name';
}

/// The lighting models a document may name in one engine: the engine's
/// [LightingModel.builtIn] and every model a plugin registered — the open
/// registry, one per engine (D23, D43).
///
/// **How a plugin adds a way to light a surface.** It describes the model —
/// by hand, or with `MaterialBindings.lightingModel` from a `.f3dmat` whose
/// `light` and composite hooks are the model — and registers it through the
/// one entrance, `host.registry<LightingModels>()` (a `LightingModelAddon`
/// does this), with its stages through `RendererSteps.addMaterials`. From
/// then on a material file read against this engine's table naming the
/// model's [LightingModel.name] reads as that model, and a picker
/// walking [all] offers it. Cancelling the registration takes the name back
/// out. The renderer's own table is `Renderer.lightingModels`, and a host
/// handed `renderer.renderSteps` finds it among that registry's companions.
///
/// **One per engine, not one per process.** Two engines in one isolate —
/// an editor and the game it plays — install their plugins apart, and a
/// model one of them registered is not a name in the other's documents. A
/// document read with no engine at hand (an importer, a server, a tool)
/// reads against [shipped], the built-in models alone; one that names a
/// plugin's model by name then warns and falls back as for any unknown
/// name, and one that describes the model as an object reads anywhere.
///
/// **A plugin's name is compared exactly; a built-in one in any case.** A
/// name matched in any case could not tell two plugins' apart, so
/// `acme_ink.Ink` is not `acme_ink.ink`. The built-in models are a fixed set
/// with names that differ in more than case, and material files have always
/// named them so (`"lighting": "pbr"`), so `pbr` still reads as `Pbr`.
///
/// **A plugin's model is in its namespace, `<namespace>.<Name>`**, like
/// every other registration ([LightingModel.name]). A shader's entry point
/// cannot carry a dot, so its [LightingModel.shaderName] is the same word
/// with the dot made `__` — `acme_ink__Ink` for `acme_ink.Ink` — and a model
/// the engine adds in a minor (which never does) cannot take its name. The
/// built-in names stay the built-in models: one is refused unless it is
/// that very constant, which is how `flutter3d_post/style.dart` registers
/// [LightingModel.toon].
///
/// **The words from before the dot still read.** Files written then name a
/// plugin's model by its old stage name, `<namespace>_<Name>`
/// (`acme_ink_Ink`); [named] finds the registered model that word meant, so
/// `.fmat` and `.f3d` stay at their versions — the word is a value, not a
/// key — and are written in the new word from then on.
final class LightingModels extends PluginRegistry {
  /// An engine's table: the built-in models, and nothing registered yet.
  LightingModels() : _store = _ModelStore(), _scope = null;

  LightingModels._scoped(this._store, this._scope);

  LightingModels._shipped() : _store = _ModelStore(frozen: true), _scope = null;

  /// The built-in models alone, with nothing registerable: the table a
  /// document read with no engine's at hand is read against.
  static final LightingModels shipped = LightingModels._shipped();

  final _ModelStore _store;
  final PluginScope? _scope;

  /// Every model a document may name: [LightingModel.builtIn] in its order,
  /// then the registered ones not already among them, in the order they
  /// were first registered.
  List<LightingModel> get all => List<LightingModel>.unmodifiable(
    <LightingModel>[...LightingModel.builtIn, ...registered],
  );

  /// The models plugins registered, other than the built-in ones.
  List<LightingModel> get registered =>
      List<LightingModel>.unmodifiable(<LightingModel>[
        for (final entry in _store.registered.values)
          if (!LightingModel.builtIn.contains(entry.model)) entry.model,
      ]);

  /// The model called [name], or null: a built-in one matched in any case,
  /// a registered one exactly — by its [LightingModel.name]
  /// (`acme_ink.Ink`), its [LightingModel.shaderName] (`acme_ink__Ink`), or
  /// the stage name a file wrote before the dot (`acme_ink_Ink`).
  LightingModel? named(String name) {
    final lower = name.toLowerCase();
    for (final model in LightingModel.builtIn) {
      if (model.shaderName.toLowerCase() == lower) return model;
    }
    final registered =
        _store.registered[LightingModel.shaderNameOf(name)]?.model;
    if (registered != null) return registered;
    for (final entry in _store.registered.values) {
      if (entry.model.name.replaceFirst('.', '_') == name) {
        return entry.model;
      }
    }
    return null;
  }

  /// Makes [model] one a document read against this table may name, until
  /// the result is cancelled.
  ///
  /// Throws a [NameTakenException] when another model already answers to
  /// its [LightingModel.shaderName] — built in, or registered by somebody
  /// else — and, through a plugin's view, a [PluginException] for a name outside
  /// the plugin's namespace. Registering the same model again is counted,
  /// not refused. [shipped] takes nothing.
  Registration register(LightingModel model) {
    if (_store.frozen) {
      throw StateError(
        'LightingModels.shipped is the built-in models alone; register '
        '"${model.shaderName}" in an engine\'s table '
        '(Renderer.lightingModels)',
      );
    }
    final name = model.shaderName;
    for (final built in LightingModel.builtIn) {
      if (built.shaderName == name && !identical(built, model)) {
        throw NameTakenException(
          name,
          what: 'the lighting model',
          owner: 'the engine',
          detail:
              'it is a built-in model; a plugin replaces its stage only as '
              'a RenderStepAddon declaring it in `replacesStages`',
        );
      }
    }
    final scope = _scope;
    if (scope != null &&
        !LightingModel.builtIn.any((built) => identical(built, model))) {
      final manifest = scope.manifest;
      if (!manifest.isEngine) {
        final word = model.name;
        final rest = word.contains('.')
            ? word.substring(word.indexOf('.') + 1)
            : '';
        final problem =
            manifest.nameProblem(word, what: 'the lighting model') ??
            (rest.contains('__') || rest.contains('.') || rest.startsWith('_')
                ? 'plugin "${manifest.id}" registered the lighting model '
                      '"$word": a model\'s name after its namespace has no '
                      '"__", no "." and no leading "_", because its shader is '
                      'named with the dot made "__"'
                : null);
        if (problem != null) {
          throw PluginException(
            '$problem. A plugin\'s model is "${manifest.namespace}.<Name>", '
            'compiled as the stage "${manifest.namespace}__<Name>" '
            '(LightingModel.shaderNameOf)',
          );
        }
      }
    }
    final existing = _store.registered[name];
    if (existing != null && !identical(existing.model, model)) {
      throw NameTakenException(
        model.name,
        what: 'the lighting model',
        detail: 'a different model is registered under its stage "$name"',
      );
    }
    final entry =
        existing ?? (_store.registered[name] = _RegisteredModel(model));
    entry.count++;
    final registration = Registration(() {
      entry.count--;
      if (entry.count == 0) _store.registered.remove(name);
    });
    scope?.track(registration);
    return registration;
  }

  @override
  LightingModels forPlugin(PluginScope scope) =>
      LightingModels._scoped(_store, scope);
}

final class _ModelStore {
  _ModelStore({this.frozen = false});

  final bool frozen;

  // Insertion order: a picker lists the models in the order they came.
  final Map<String, _RegisteredModel> registered = <String, _RegisteredModel>{};
}

final class _RegisteredModel {
  _RegisteredModel(this.model);
  final LightingModel model;
  int count = 0;
}
