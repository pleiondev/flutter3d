import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../scene/light_node.dart' show Photometric;

/// How a material treats the alpha channel, mirroring glTF's `alphaMode`.
///
/// The renderer uses this to split draws into the opaque and transparent halves
/// of the render list, which are sorted differently.
enum MaterialAlphaMode {
  opaque,
  mask,
  blend,

  /// Kept or dropped per pixel against noise instead of a threshold —
  /// `gfx-16n`'s own row, and the one mode here that glTF has no word for.
  ///
  /// **What it is for: foliage and nets.** A leaf texture at 40% opacity is
  /// either entirely there or entirely gone under [mask], so a fern comes out
  /// as a hard-edged cut-out; [blend] draws it correctly and needs the
  /// geometry sorted, which costs a sort per frame and defeats instancing.
  /// Hashed keeps 40% of the *pixels* and resolves as 40% opacity to anything
  /// that averages several of them.
  ///
  /// It is drawn in the opaque half, writes depth, and needs no sorting —
  /// which is the whole point — at the price of visible noise anywhere the
  /// result is not averaged down. Without temporal accumulation this engine
  /// does not have, that price is real: it suits a supersampled render or a
  /// distant canopy better than a leaf held up to the camera.
  ///
  /// The noise is anchored to world position rather than to the screen, so a
  /// moving branch keeps its verdict instead of sparkling as it passes
  /// through a fixed pattern. See `surface.glsl`, which does the work.
  hashed,
}

/// How a blended surface is combined with what is behind it — read only when
/// [RenderMaterial.alphaMode] is [MaterialAlphaMode.blend].
///
/// A `final class` with const instances rather than an enum, the rule for a
/// type a published package exports and may grow.
final class MaterialBlendMode {
  const MaterialBlendMode._(this.name);

  /// Over, on straight colour: glTF's blend, and what a blended material has
  /// always drawn with. The stage weighs its colour by its alpha.
  static const MaterialBlendMode alpha = MaterialBlendMode._('alpha');

  /// The colour, times its alpha, added to what is there — light that adds:
  /// a glow, a beam, a spark. Commutative, so it needs no order.
  static const MaterialBlendMode additive = MaterialBlendMode._('additive');

  /// Over, on a colour the stage already multiplied by its alpha, so a
  /// stage can add light and cover at once. **Honoured by a stage that says
  /// so** — a material-language stage whose state block reads
  /// `blend premultiplied` leaves its colour as it returned it. The engine's
  /// own lighting models weigh their colour by their alpha whatever this
  /// says, so on them it draws as [alpha] does.
  static const MaterialBlendMode premultiplied = MaterialBlendMode._(
    'premultiplied',
  );

  static const List<MaterialBlendMode> values = <MaterialBlendMode>[
    alpha,
    additive,
    premultiplied,
  ];

  final String name;

  @override
  String toString() => 'MaterialBlendMode.$name';
}

/// Surface appearance as plain data.
///
/// Materials carry no GPU objects beyond textures: the shader is selected by
/// [lighting], because shaders are compiled ahead of time and a material
/// cannot assemble one at runtime. That makes [lighting] the pipeline key, and
/// the pipeline the most expensive state change in a pass — which is why it is
/// the high-order term when the render list is sorted.
final class RenderMaterial {
  RenderMaterial({
    this.name,
    this.lighting = LightingModel.pbr,
    LinearColor baseColor = LinearColor.white,
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.albedo,
    this.albedoSampler,
    this.normal,
    this.normalSampler,
    this.normalScale = 1.0,
    this.metallicRoughness,
    this.metallicRoughnessSampler,
    this.occlusion,
    this.occlusionSampler,
    this.occlusionStrength = 1.0,
    this.emissiveTexture,
    this.emissiveSampler,
    this.emissive = LinearColor.black,
    this.emissiveStrength = Photometric.legacyNits,
    this.alphaMode = MaterialAlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.alphaToCoverage = false,
    this.doubleSided = false,
    this.fogged = true,
    this.extensions,
    this.coatMap,
    this.coatMapSampler,
    this.sheenMap,
    this.sheenMapSampler,
    Map<MaterialMap, TextureTransform>? textureTransforms,
    this.drawBucket = 0,
    this.depthWrite,
    this.depthCompare,
    this.parameterBlock = 'MaterialParams',
    Map<String, Float32List>? parameters,
    Map<String, TextureHandle>? extraTextures,
    this.blendMode = MaterialBlendMode.alpha,
    this.depthLayer = 0,
    this.effectsDepth = false,
  }) : _baseColor = baseColor, // ignore: prefer_initializing_formals
       parameters = parameters ?? <String, Float32List>{},
       textureTransforms =
           textureTransforms ?? <MaterialMap, TextureTransform>{},
       extraTextures = extraTextures ?? const <String, TextureHandle>{};

  /// The material a `buildPolyline` mesh is drawn with — `gfx-86n`.
  ///
  /// [viewportWidth] and [viewportHeight] are the render target in pixels, the
  /// same pixels the line's width was given in. They are the one thing the
  /// vertex stage needs that no engine block carries, so they travel as this
  /// material's own parameter; on a resize, write the new size into
  /// [polylineViewport] rather than rebuilding anything.
  ///
  /// **Double-sided, and not as a preference.** Which way a band's triangles
  /// wind on screen depends on which way the line is heading relative to the
  /// camera, so half of any route faces away and back-face culling would
  /// delete it segment by segment as the camera turned.
  ///
  /// **No depth bias.** A line behind a hill is hidden by the hill, which is
  /// what the depth test does by itself; an overlay that pushes towards the
  /// eye, the way `MeshOverlay.biasPixels` does so an edge sits on its own
  /// face, would draw a route through the mountain. A line laid exactly on the
  /// ground it follows will fight that ground for depth, and the answer there
  /// is to lift the points, not to bias the pass.
  factory RenderMaterial.polyline({
    String? name,
    required double viewportWidth,
    required double viewportHeight,
  }) => RenderMaterial(
    name: name,
    lighting: LightingModel.polyline,
    doubleSided: true,
    parameters: <String, Float32List>{
      'viewport': Float32List.fromList(<double>[
        viewportWidth,
        viewportHeight,
        0,
        0,
      ]),
    },
  );

  /// The material an `ImpostorNode` is drawn with — `C4`.
  ///
  /// [albedo] is the baked colour and coverage, [normalDepth] the baked
  /// normals and depths, each [impostorGrid] views to a side. They ride in
  /// the albedo and normal map slots, which [LightingModel.impostor]'s stage
  /// reads as atlases rather than as ordinary maps.
  ///
  /// **Opaque, not masked.** The stage discards by its own blended coverage;
  /// a mask here would have the shared surface code discard first against a
  /// read of the atlas at the card's own corner coordinates, which is not
  /// any view at all.
  factory RenderMaterial.impostor({
    String? name,
    required TextureHandle albedo,
    required TextureHandle normalDepth,
  }) => RenderMaterial(
    name: name,
    lighting: LightingModel.impostor,
    albedo: albedo,
    normal: normalDepth,
    roughness: 1.0,
    doubleSided: true,
  );

  /// The render target size a [RenderMaterial.polyline] widens its line against, as
  /// the list the renderer binds — so writing to it takes effect on the next
  /// frame, with nothing rebuilt. Null for any other material.
  Float32List? get polylineViewport =>
      lighting == LightingModel.polyline ? parameters['viewport'] : null;

  final String? name;

  /// The uniform block an application's own shader reads its parameters from.
  ///
  /// Meaningless for the models this engine ships — they read `FragInfo` — and
  /// used only when [parameters] has something in it.
  final String parameterBlock;

  /// What an application's own shader is configured with.
  ///
  /// **This is the half of a custom material that is not the shader.** A
  /// [LightingModel] can already name a stage the engine never heard of; this
  /// is how that stage is told a wave height, a tint ramp or a scroll speed
  /// without the engine knowing what any of them mean.
  ///
  /// Safe to fill in even when the shader has no such block: the encoder skips
  /// members a compiled shader does not read and reports an absent block rather
  /// than taking the process down — see `CommandEncoder.bindUniformBlock`,
  /// where that distinction is spelled out.
  ///
  /// Every uniform in this engine is a float vector, a matrix or an array of
  /// either, so a `Float32List` is the only value there is. An integer or a
  /// boolean is encoded as a float, the same way the built-in shaders do it.
  ///
  /// **A map of the material's own, empty by default and open to additions**
  /// — `P8`. It was a shared constant, so a material made without parameters
  /// could not be given any: a model's surfaces, handed a material written
  /// in the language after loading, had nowhere to put its uniforms.
  final Map<String, Float32List> parameters;

  /// Textures an application's own shader samples, by slot name.
  ///
  /// **Unlike [parameters], a wrong name here is fatal**, and that asymmetry is
  /// the encoder's rather than this class's: binding a sampler slot a compiled
  /// shader does not have is a native crash with no Dart stack, while a missing
  /// uniform block is merely reported. The material that names the shader is
  /// the same object that lists these, so the two are the author's to keep in
  /// step — there is nothing here that could check it for them.
  final Map<String, TextureHandle> extraTextures;

  /// Selects the pre-built fragment shader, and therefore the pipeline.
  LightingModel lighting;

  /// RGBA tint applied on top of [albedo], in linear light with straight
  /// alpha, as every colour the engine takes is.
  ///
  /// **Linear since 1.0.** It was a `Vector4` holding the sRGB-encoded
  /// colour a paint program shows; the colour a person picked is now said as
  /// `LinearColor.fromSrgb(0.9, 0.35, 0.12)` (bytes 230, 90, 30), and the
  /// renderer encodes it once, where the shaders' `toLinear(tint)` expects
  /// the encoded value, so the picture is the one it was.
  ///
  /// Assigned whole: a [LinearColor] is immutable, so a change is
  /// `material.baseColor = …`, which the next frame draws.
  LinearColor get baseColor => _baseColor;
  set baseColor(LinearColor value) {
    _baseColor = value;
    _baseColorEncoded = null;
  }

  LinearColor _baseColor;

  /// [baseColor]'s red, green and blue sRGB-encoded, worked out once per
  /// assignment rather than once per draw.
  ({double r, double g, double b, double a})? _baseColorEncoded;

  /// A 0..1 fraction.
  double metallic;

  /// Perceptual roughness, a 0..1 fraction.
  double roughness;

  TextureHandle? albedo;
  SamplerDescriptor? albedoSampler;

  /// Tangent-space normal map. Null means the geometric normal is used.
  ///
  /// A missing map is a *neutral* texture at bind time, not a flag: the renderer
  /// binds a flat 1x1 normal, a white ORM, a white occlusion and a white
  /// emissive when a slot is empty. Flags would have to agree with the shader in
  /// two places; a neutral texel is right by construction, and the branch it
  /// would have cost is worth more than the sample.
  TextureHandle? normal;
  SamplerDescriptor? normalSampler;

  /// Scales the tangent-space xy of the normal map, per glTF's `normalScale`.
  double normalScale;

  /// glTF's ORM packing: roughness in green, metallic in blue.
  TextureHandle? metallicRoughness;
  SamplerDescriptor? metallicRoughnessSampler;

  /// Ambient occlusion in red.
  TextureHandle? occlusion;
  SamplerDescriptor? occlusionSampler;

  /// How much of the occlusion map to apply, from 0 (ignore) to 1 (in full).
  double occlusionStrength;

  TextureHandle? emissiveTexture;
  SamplerDescriptor? emissiveSampler;

  /// The level's baked lightmap, sampled at the vertex's second coordinate.
  ///
  /// Only a mesh drawn with `MeshNode.lightmapped` has a second coordinate
  /// to sample at; a material with a map on a mesh without one samples the
  /// map's corner. Null binds a one-texel black, which adds nothing, so every
  /// lit model samples the slot and nothing branches.
  TextureHandle? lightmap;
  SamplerDescriptor? lightmapSampler;

  /// Linear emissive factor, multiplied by the emissive map. Black by default,
  /// so a material with a map but no factor emits nothing — which is what glTF
  /// specifies. Alpha is not read.
  LinearColor emissive;

  /// How bright [emissive] is, in **nits** (cd/m²) since 1.0: an emissive of
  /// white shines at this luminance, and a colour at its share of it.
  ///
  /// 1 843.2 by default, `Photometric.legacyNits`, the luminance the old
  /// default of one stood for, so a glowing surface looks as it did; a
  /// material loaded from a file multiplies the file's own strength
  /// (`KHR_materials_emissive_strength`, a plain multiple) by it. A screen
  /// is a few hundred nits, a lit sign a few thousand. Multiply a pre-1.0
  /// strength by `Photometric.legacyNits`.
  double emissiveStrength;

  MaterialAlphaMode alphaMode;

  /// A 0..1 fraction: in the mask mode, alpha below it is cut away.
  double alphaCutoff;

  /// A masked surface's edge antialiased by the multisample resolve rather
  /// than cut at [alphaCutoff] — `P7`.
  ///
  /// Read only under [MaterialAlphaMode.mask]. The alpha is sharpened round
  /// the cutoff to a pixel's width and handed to the hardware as coverage, so
  /// a leaf, a fence or a grille is as smooth at its edge as a triangle is.
  /// **Two backends of four can**: WebGL2 and WebGPU, in a multisampled scene
  /// pass. Elsewhere — Impeller, the software rasteriser, a scene pass that
  /// gave its multisampling up — the material draws the hard cutoff it draws
  /// without this, and `FrameResult.alphaToCoverageDeclined` says so. Off by
  /// default.
  bool alphaToCoverage;
  bool doubleSided;

  /// Whether the frame's fog reaches this material. True for almost
  /// everything; false for what is meant to stand beyond the fog: a far
  /// horizon of hills, a moon, a skyline painted on a backdrop.
  ///
  /// **For the layer behind the weather.** Enduro's mountains stay on the
  /// horizon through fog and dusk while the road and the cars fade into it;
  /// with fog on every material they faded first, being furthest away, and
  /// the horizon became a flat wall of fog colour.
  bool fogged;

  /// The layers beyond metal-rough — clear coat, specular, index of
  /// refraction, sheen, anisotropy, transmission and the rest — `M1`–`M3`.
  /// Read only by [LightingModel.pbrLayered]: a material that has them and
  /// asks for [LightingModel.pbr] is drawn without them, which is why the
  /// loaders hand such a material the layered model.
  ///
  /// Only the factors are read from here; the texture bindings it carries
  /// are the document's and reach the renderer packed into [coatMap] and
  /// [sheenMap].
  MaterialExtensions? extensions;

  /// The coat map: red the clear coat, green its roughness, blue the
  /// transmission and alpha the thickness, each multiplying its factor in
  /// [extensions]. Null binds white, which leaves the factors as they are.
  ///
  /// One texture for what glTF gives as up to four, because the layered
  /// stage has two samplers left under WebGL2's sixteen and this is one of
  /// them — see `binding_budget_test.dart`.
  TextureHandle? coatMap;
  SamplerDescriptor? coatMapSampler;

  /// The sheen map — `M2`: the sheen colour in red, green and blue, sRGB as
  /// it was authored, and its roughness in alpha, each multiplying its factor
  /// in [extensions]. Null binds white. The layered stage's sixteenth sampler,
  /// and its last.
  TextureHandle? sheenMap;
  SamplerDescriptor? sheenMapSampler;

  /// `KHR_texture_transform` per map, applied at the sampler — `C8`. A map
  /// with no entry is read at the vertex's own coordinate.
  ///
  /// **Read only by [LightingModel.pbrLayered]**, whose block has the room: a
  /// matrix per map for every draw of every model would be a widening of the
  /// block six stages share, for a feature most models never meet. What most
  /// models do meet — one transform on every map, an atlas export — is baked
  /// into the coordinates at upload and leaves this empty; a loader fills it
  /// for the material whose maps disagree, or whose offset a clip moves, and
  /// hands that material the layered model. Mutable, so a clip moves an
  /// [TextureTransform.offset] in place.
  final Map<MaterialMap, TextureTransform> textureTransforms;

  /// Coarse manual ordering: it outranks every other
  /// sort term, so a skybox or an overlay can be forced to a fixed position
  /// without touching the sorting policy.
  ///
  /// Signed, and negative is the useful half: ordinary materials sit at zero,
  /// so the only way to be drawn *before* the scene is to ask for less than it.
  /// The usable range is −128 to 127 and values outside it are clamped.
  /// [MeshNode.drawOrder] adds to it, for an order between nodes that share
  /// this material.
  int drawBucket;

  /// Overrides whether this surface writes depth. Null lets transparency
  /// decide, which is what every ordinary material wants.
  ///
  /// Null rather than `true` for the same reason [PassState]'s fields are
  /// optional: unset means *the pass's own answer*, and the pass's answer is
  /// "opaque writes, blended does not". Saying `false` here is a different
  /// statement from being transparent — it is a surface that is drawn and then
  /// stops existing as far as everything after it is concerned.
  ///
  /// What it is for: a backdrop. A sky drawn on a small dome around the camera
  /// is nearer than everything it is supposed to be behind, so it must be drawn
  /// first and leave the depth buffer untouched. Without this the dome writes a
  /// few metres of depth across the whole frame and the level behind it is
  /// clipped away.
  bool? depthWrite;

  /// Overrides the depth test. Null keeps the pass's own, which is
  /// [CompareFunction.less].
  ///
  /// The other half of a backdrop: with [depthWrite] off and this left alone a
  /// dome still has to *pass* the test to be drawn, which it does only where
  /// nothing has been drawn yet — fine when the sky goes first, wrong the
  /// moment anything wants to be drawn after the scene. [CompareFunction.always]
  /// is the honest statement for a surface whose depth is not a fact about the
  /// world.
  ///
  /// Applies to the scene pass only. The shadow pass draws casters with its own
  /// state and has no use for either of these — a surface that should not
  /// occlude in a shadow map says so with `MeshNode.castsShadow`.
  CompareFunction? depthCompare;

  /// How a blended surface meets what is behind it — read only under
  /// [MaterialAlphaMode.blend]. [MaterialBlendMode.alpha] by default, which
  /// is what every blended material drew with before there was a choice.
  ///
  /// Under weighted blended transparency (`TransparencyMode.weightedBlended`)
  /// every blended surface is a layer of the weighted average, and this is
  /// not read.
  MaterialBlendMode blendMode;

  /// Which of two coplanar surfaces wins: the higher layer, wherever the two
  /// meet at one depth — a decal on a wall, a road's markings on the road, a
  /// puddle on the floor. Nought for every ordinary surface; from
  /// −[materialDepthLayerLimit] to [materialDepthLayerLimit], clamped.
  ///
  /// **How the renderer honours it.** Where the device has
  /// `DeviceFeature.depthBias`, a layered draw is pulled towards the eye by
  /// a small constant and slope-scaled bias per layer — four of the depth
  /// format's smallest steps and one slope each, the depth turned round
  /// under reversed-Z as every bias is. Wherever it does not — Impeller
  /// today — the order is stable instead: the opaque half draws its layered
  /// surfaces after the rest, lowest layer first, and tests them
  /// `lessEqual`, so the later of two equal depths wins. Both apply where
  /// both can, so coplanar faces that rasterise to the very same depth and
  /// faces a hair apart are ordered alike. Applies to the scene pass; a
  /// shadow does not care which of two coplanar faces casts it.
  int depthLayer;

  /// Whether a translucent surface writes its normal and depth into the
  /// surface buffer — the depth the screen-space effects read: depth of
  /// field, ambient occlusion, the fog march, soft particles, outlines.
  /// False by default, which leaves the buffer the opaque scene's.
  ///
  /// **For a surface that is the scene to those effects**: water a camera
  /// focuses on, or the soft particles that should fade against its top
  /// rather than the river bed. Read only under [MaterialAlphaMode.blend],
  /// in a frame that sorts its transparency, on a device with
  /// `DeviceFeature.independentBlend` — the buffer is then written whole
  /// while the colour blends. Elsewhere it is not honoured, and the
  /// surface stays out of the buffer as before.
  bool effectsDepth;

  bool get isTransparent => alphaMode == MaterialAlphaMode.blend;

  /// An independent copy: the vectors are cloned, the textures are shared.
  ///
  /// Here rather than where it is used, and that is the whole point of moving
  /// it. It lived in `ModelAsset` as a private helper listing every field by
  /// hand, so each new field was a field that copied silently as its default —
  /// `depthWrite` and `depthCompare` were lost the day they were added, and the
  /// symptom would have been a model whose materials behave differently from
  /// the ones it was built from, in one game, on one asset. A copy that lives
  /// beside the fields is a copy the next field is added next to.
  ///
  /// Textures are shared on purpose: they are device handles, and two materials
  /// pointing at one uploaded image is the arrangement everything downstream
  /// already assumes. The [parameters] lists are cloned like the vectors,
  /// because they are written in place — [polylineViewport] is one — and a
  /// copy sharing them would resize its original.
  RenderMaterial copy() =>
      RenderMaterial(
          name: name,
          parameterBlock: parameterBlock,
          parameters: <String, Float32List>{
            for (final entry in parameters.entries)
              entry.key: Float32List.fromList(entry.value),
          },
          extraTextures: Map<String, TextureHandle>.of(extraTextures),
          lighting: lighting,
          baseColor: baseColor,
          metallic: metallic,
          roughness: roughness,
          albedo: albedo,
          albedoSampler: albedoSampler,
          normal: normal,
          normalSampler: normalSampler,
          normalScale: normalScale,
          metallicRoughness: metallicRoughness,
          metallicRoughnessSampler: metallicRoughnessSampler,
          occlusion: occlusion,
          occlusionSampler: occlusionSampler,
          occlusionStrength: occlusionStrength,
          emissiveTexture: emissiveTexture,
          emissiveSampler: emissiveSampler,
          emissive: emissive,
          emissiveStrength: emissiveStrength,
          alphaMode: alphaMode,
          alphaCutoff: alphaCutoff,
          alphaToCoverage: alphaToCoverage,
          doubleSided: doubleSided,
          fogged: fogged,
          extensions: extensions,
          coatMap: coatMap,
          coatMapSampler: coatMapSampler,
          sheenMap: sheenMap,
          sheenMapSampler: sheenMapSampler,
          textureTransforms: <MaterialMap, TextureTransform>{
            for (final MapEntry(:key, :value) in textureTransforms.entries)
              key: value.clone(),
          },
          drawBucket: drawBucket,
          depthWrite: depthWrite,
          depthCompare: depthCompare,
          blendMode: blendMode,
          depthLayer: depthLayer,
          effectsDepth: effectsDepth,
        )
        ..lightmap = lightmap
        ..lightmapSampler = lightmapSampler;
}

/// A [RenderMaterial] drawn with a bundle's material, its file's state on it —
/// item 9 of `tasks/1.0-scope-additions.md`.
/// What the renderer reads off a material that a caller does not. Not
/// exported by `flutter3d_core.dart`.
extension RenderMaterialInternals on RenderMaterial {
  /// [RenderMaterial.baseColor] with red, green and blue sRGB-encoded, the
  /// form every material shader's `toLinear(tint)` takes.
  ({double r, double g, double b, double a}) get baseColorEncoded =>
      _baseColorEncoded ??= _baseColor.toSrgb();
}

extension BundledMaterialLooks on BundledMaterials {
  /// A new [RenderMaterial] drawn with material [name]: its lighting model, its
  /// uniforms at their defaults ([BundledMaterials.parameters]), and what
  /// its `state` block says — the blend, the cutoff, the depth write and
  /// test, alpha to coverage, double-sidedness, the depth layer and the
  /// effects depth. What the file leaves unsaid keeps [RenderMaterial]'s own
  /// default, and every field stays the game's to change.
  ///
  /// [materialName] names the material, [name] when null.
  RenderMaterial material(String name, {String? materialName}) {
    final state = this.state(name);
    final blend = state.blend;
    final compare = switch ((state.depthTest, state.depthCompare)) {
      (false, _) => CompareFunction.always,
      // The file's word, through the format's table: a rename of a value
      // must not change what a `.f3dmat` says.
      (_, final String named) => materialDepthCompareWire[named],
      _ => null,
    };
    return RenderMaterial(
      name: materialName ?? name,
      lighting: this[name],
      parameters: parameters(name),
      alphaMode: switch (blend) {
        MaterialBlend.mask => MaterialAlphaMode.mask,
        MaterialBlend.hashed => MaterialAlphaMode.hashed,
        final b? when b.translucent => MaterialAlphaMode.blend,
        _ => MaterialAlphaMode.opaque,
      },
      blendMode: switch (blend) {
        MaterialBlend.additive => MaterialBlendMode.additive,
        MaterialBlend.premultiplied => MaterialBlendMode.premultiplied,
        _ => MaterialBlendMode.alpha,
      },
      alphaCutoff: state.cutoff ?? 0.5,
      alphaToCoverage: state.alphaToCoverage ?? false,
      doubleSided: state.doubleSided ?? false,
      depthWrite: state.depthWrite,
      depthCompare: compare,
      depthLayer: state.depthLayer ?? 0,
      effectsDepth: state.effectsDepth ?? false,
    );
  }
}

/// Assigns small dense integers to materials for use as a sort key.
///
/// An owned registry rather than a static counter on [RenderMaterial]: global mutable
/// state is the least testable kind of static, and ids only need to be unique
/// within the thing that sorts by them. The renderer owns one.
/// **Weakly, which it was not.** A `Map<RenderMaterial, int>` filled on every draw
/// and emptied by nobody is a strong reference to every material the renderer
/// has ever seen, for as long as the renderer lives — and a [RenderMaterial] holds
/// its base colour, normal, metallic-roughness, occlusion and emissive
/// textures. That defeated `ResourceCache.evictUnused` outright: a game could
/// load level two, drop level one and evict it, and level one's textures still
/// could not be collected, because this map was holding the materials that
/// referenced them. It was the one leak that was the same on all three
/// backends, and the `clear()` that would have relieved it had no caller
/// anywhere in the repository.
///
/// An [Expando] is the fix and costs nothing: it is a weak-keyed side table on
/// both the VM and the web, so a material that nothing else refers to is
/// collected with its id, and this registry stops being a reason anything
/// stays alive.
final class MaterialSortIds {
  Expando<int> _ids = Expando<int>('material sort id');

  /// How many ids have been handed out.
  ///
  /// The count of assignments rather than of live materials, which is the only
  /// number a weak table can answer honestly — asking how many keys survive
  /// would be asking when the collector last ran.
  int get length => _assigned;
  int _assigned = 0;

  /// Id for [material], assigning one on first sight.
  ///
  /// Bounded by [limit] because the id is packed into a bit field; wrapping is
  /// better than corrupting neighbouring fields, and a collision only costs
  /// sort quality, never correctness.
  int idOf(RenderMaterial material, {int limit = 0x7FFFFF}) {
    final existing = _ids[material];
    if (existing != null) return existing;
    final id = (++_assigned) % limit;
    _ids[material] = id;
    return id;
  }

  /// Forgets every assignment, by replacing the table rather than walking it —
  /// a weak table has no keys to walk.
  void clear() {
    _ids = Expando<int>('material sort id');
    _assigned = 0;
  }
}
