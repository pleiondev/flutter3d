part of 'scene_widgets.dart';

// -------------------------------------------------------------- materials

/// A material, as a widget — `P10`: the meshes below it that name no
/// material of their own are drawn with it.
///
///     Material3D(
///       baseColor: Vector4(0.8, 0.3, 0.2, 1.0),
///       roughness: 0.4,
///       children: <Widget>[
///         Mesh3D(shape: CuboidShape(), position: ...),
///         Mesh3D(shape: SphereShape(), position: ...),
///       ],
///     )
///
/// **One engine [engine.Material], made once and changed in place.** A
/// rebuild with other properties writes them into the same object, so the
/// meshes keep drawing with it and the renderer's batching keeps seeing one
/// material — which is what lets a field of crates under one [Material3D] be
/// one draw. As with every widget here, a key keeps it across a rebuild.
///
/// A property left null is left as the material has it, so a game may still
/// change the object imperatively — through [onCreated] — and the widget
/// will not put it back unless it says what it should be.
class Material3D extends StatefulWidget {
  const Material3D({
    super.key,
    this.lighting = LightingModel.pbr,
    this.baseColor,
    this.metallic,
    this.roughness,
    this.emissive,
    this.emissiveStrength,
    this.albedo,
    this.normal,
    this.metallicRoughness,
    this.occlusion,
    this.emissiveTexture,
    this.alphaMode,
    this.alphaCutoff,
    this.doubleSided,
    this.parameters = const <String, List<double>>{},
    this.name,
    this.onCreated,
    this.children = const <Widget>[],
  });

  /// How it is lit: one of the engine's models, or one a bundle describes —
  /// `BundledMaterials`.
  final LightingModel lighting;

  /// Linear RGBA.
  final Vector4? baseColor;
  final double? metallic;
  final double? roughness;

  /// Linear RGB.
  final Vector3? emissive;
  final double? emissiveStrength;
  final TextureHandle? albedo;
  final TextureHandle? normal;
  final TextureHandle? metallicRoughness;
  final TextureHandle? occlusion;
  final TextureHandle? emissiveTexture;
  final MaterialAlphaMode? alphaMode;
  final double? alphaCutoff;
  final bool? doubleSided;

  /// Values for the `uniform`s of a material written in the language — `P8`:
  /// written into `Material.parameters` on every build. A name not given is
  /// left as the material has it.
  final Map<String, List<double>> parameters;
  final String? name;

  /// Called once with the material, when it is made.
  final void Function(engine.Material material)? onCreated;

  final List<Widget> children;

  @override
  State<Material3D> createState() => _Material3DState();
}

class _Material3DState extends State<Material3D> {
  late final engine.Material _material = engine.Material(
    name: widget.name,
    lighting: widget.lighting,
  );

  @override
  void initState() {
    super.initState();
    _apply();
    widget.onCreated?.call(_material);
  }

  @override
  void didUpdateWidget(Material3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    _apply();
  }

  void _apply() {
    final m = _material..lighting = widget.lighting;
    if (widget.baseColor case final c?) m.baseColor.setFrom(c);
    if (widget.metallic case final v?) m.metallic = v;
    if (widget.roughness case final v?) m.roughness = v;
    if (widget.emissive case final c?) m.emissive.setFrom(c);
    if (widget.emissiveStrength case final v?) m.emissiveStrength = v;
    if (widget.albedo case final t?) m.albedo = t;
    if (widget.normal case final t?) m.normal = t;
    if (widget.metallicRoughness case final t?) m.metallicRoughness = t;
    if (widget.occlusion case final t?) m.occlusion = t;
    if (widget.emissiveTexture case final t?) m.emissiveTexture = t;
    if (widget.alphaMode case final v?) m.alphaMode = v;
    if (widget.alphaCutoff case final v?) m.alphaCutoff = v;
    if (widget.doubleSided case final v?) m.doubleSided = v;
    for (final MapEntry(:key, :value) in widget.parameters.entries) {
      m.parameters[key] = Float32List.fromList(value);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _MaterialScope(material: _material, child: _Children(widget.children));
}

class _MaterialScope extends InheritedWidget {
  const _MaterialScope({required this.material, required super.child});

  final engine.Material material;

  static engine.Material? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MaterialScope>()?.material;

  @override
  bool updateShouldNotify(_MaterialScope oldWidget) =>
      !identical(material, oldWidget.material);
}

// ------------------------------------------------------- probes and decals

/// A reflection probe: the scene around [position] captured into a cube that
/// the surfaces within [radius] reflect — `ReflectionProbeNode`.
///
/// [faceSize], [levels], [near] and [far] shape the capture and are read when
/// the probe is first built; [radius] and [intensity] follow every build.
class ReflectionProbe3D extends Spatial3D {
  const ReflectionProbe3D({
    super.key,
    super.position,
    this.radius = 0.0,
    this.intensity = 1.0,
    this.faceSize = 64,
    this.levels = 4,
    this.near = 0.05,
    this.far = 200.0,
    this.name,
  });

  /// How far the probe reaches; nought reaches everything.
  final double radius;
  final double intensity;
  final int faceSize;
  final int levels;
  final double near;
  final double far;
  final String? name;

  @override
  State<ReflectionProbe3D> createState() => _ReflectionProbe3DState();
}

class _ReflectionProbe3DState
    extends _SpatialState<ReflectionProbe3D, ReflectionProbeNode> {
  @override
  ReflectionProbeNode createNode(_Scene3DScope scope) => ReflectionProbeNode(
    radius: widget.radius,
    intensity: widget.intensity,
    faceSize: widget.faceSize,
    levels: widget.levels,
    near: widget.near,
    far: widget.far,
    name: widget.name,
  );

  @override
  void apply(ReflectionProbeNode node, _Scene3DScope scope) {
    node
      ..radius = widget.radius
      ..intensity = widget.intensity;
  }
}

/// A decal: [texture], tinted [color], stamped down the node's local y axis
/// onto whatever lies inside its box — `DecalNode`. The box is the node's
/// scale, a unit cube at scale one: x and z are the picture's size, y how
/// deep it reaches, so one with no rotation lies on the floor.
class Decal3D extends Spatial3D {
  const Decal3D({
    super.key,
    super.position,
    super.rotation,
    super.scale,
    super.visible,
    this.texture,
    this.color,
    this.emissive,
    this.region,
    this.order = 0,
    this.angleLimit = 1.3,
    this.angleFade = 0.2,
    this.depthFade = 0.1,
    this.name,
  });

  final TextureHandle? texture;

  /// Linear RGBA; white if null.
  final Vector4? color;

  /// Linear RGB; none if null.
  final Vector3? emissive;

  /// The part of [texture] it shows, as `(u0, v0, u1, v1)`; all of it if null.
  final Vector4? region;

  /// Higher draws over lower where two decals overlap.
  final int order;
  final double angleLimit;
  final double angleFade;
  final double depthFade;
  final String? name;

  @override
  State<Decal3D> createState() => _Decal3DState();
}

class _Decal3DState extends _SpatialState<Decal3D, DecalNode> {
  @override
  DecalNode createNode(_Scene3DScope scope) => DecalNode(name: widget.name);

  @override
  void apply(DecalNode node, _Scene3DScope scope) {
    node
      ..texture = widget.texture
      ..color = widget.color?.clone() ?? Vector4(1.0, 1.0, 1.0, 1.0)
      ..emissive = widget.emissive?.clone() ?? Vector3.zero()
      ..region = widget.region?.clone() ?? Vector4(0.0, 0.0, 1.0, 1.0)
      ..order = widget.order
      ..angleLimit = widget.angleLimit
      ..angleFade = widget.angleFade
      ..depthFade = widget.depthFade;
  }
}

// ----------------------------------------------------------------- mirrors

/// A flat mirror — `PlanarReflectorNode`. The [Mesh3D]s directly below it
/// are the surfaces it is seen in, each joining and leaving as its widget
/// does; the mirror's plane is theirs.
///
/// Planar reflections are drawn when the frame's `ReflectionSettings` ask
/// for them, as for an imperatively built mirror.
class Mirror3D extends Spatial3D {
  const Mirror3D({
    super.key,
    super.position,
    super.rotation,
    super.scale,
    super.visible,
    this.reflectance = 1.0,
    this.strength = 1.0,
    this.tint,
    this.resolution = 0.5,
    this.clipOffset = 0.01,
    this.name,
    super.children,
  });

  /// F0 at normal incidence: one is a perfect mirror.
  final double reflectance;
  final double strength;

  /// Linear RGB the reflection is multiplied by; white if null.
  final Vector3? tint;

  /// The reflection's size as a fraction of the view's.
  final double resolution;
  final double clipOffset;
  final String? name;

  @override
  State<Mirror3D> createState() => _Mirror3DState();
}

class _Mirror3DState extends _SpatialState<Mirror3D, PlanarReflectorNode> {
  @override
  PlanarReflectorNode createNode(_Scene3DScope scope) =>
      PlanarReflectorNode(name: widget.name);

  @override
  void apply(PlanarReflectorNode node, _Scene3DScope scope) {
    node
      ..reflectance = widget.reflectance
      ..strength = widget.strength
      ..resolution = widget.resolution
      ..clipOffset = widget.clipOffset;
    node.tint.setFrom(widget.tint ?? Vector3(1.0, 1.0, 1.0));
  }
}

// ------------------------------------------------- contributors, particles

/// Draws [contributor] with the scene while this widget is in the tree —
/// `Renderer.addContributor` and `removeContributor`, kept by Flutter's
/// reconciliation. For a contributor this package has no widget for.
class Contributor3D extends StatefulWidget {
  const Contributor3D({super.key, required this.contributor});

  final PassContributor contributor;

  @override
  State<Contributor3D> createState() => _Contributor3DState();
}

class _Contributor3DState extends State<Contributor3D> {
  _SceneHost? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = _Scene3DScope.of(context).host;
    if (identical(host, _host)) return;
    _host?.renderer.removeContributor(widget.contributor);
    host.renderer.addContributor(widget.contributor);
    _host = host;
  }

  @override
  void didUpdateWidget(Contributor3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.contributor, widget.contributor)) return;
    final renderer = _host?.renderer;
    if (renderer == null) return;
    renderer
      ..removeContributor(oldWidget.contributor)
      ..addContributor(widget.contributor);
  }

  @override
  void dispose() {
    _host?.renderer.removeContributor(widget.contributor);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Particles emitted at this node's place — `P10`: [effect] at [perSecond]
/// a second, simulated between frames and drawn as billboards, through a
/// `ParticleSystem` and a `ParticleContributor` this widget owns.
///
/// [perSecond] and [effect] follow every build, so a torch is lit by raising
/// one and a different flame by passing another; emission stops at nought
/// and what was already in the air finishes its life. Moving the node moves
/// where new particles are born. [system], when given, is simulated and
/// drawn in place of one of this widget's own — for a game that also bursts
/// into it imperatively.
class Particles3D extends Spatial3D {
  const Particles3D({
    super.key,
    super.position,
    super.visible,
    required this.effect,
    this.perSecond = 0.0,
    this.capacity = 512,
    this.seed = 0,
    this.texture,
    this.system,
    super.children,
  });

  final ParticleEffect effect;
  final double perSecond;

  /// How many particles can be alive at once; read when first built.
  final int capacity;

  /// Makes the simulation reproducible; read when first built.
  final int seed;

  /// A sprite for every particle; the procedural disc if null.
  final TextureHandle? texture;
  final ParticleSystem? system;

  @override
  State<Particles3D> createState() => _Particles3DState();
}

class _Particles3DState extends _SpatialState<Particles3D, SceneNode>
    implements _Animated {
  late final ParticleSystem _system =
      widget.system ??
      ParticleSystem(capacity: widget.capacity, seed: widget.seed);
  ParticleContributor? _contributor;
  _SceneHost? _host;

  @override
  SceneNode createNode(_Scene3DScope scope) {
    final host = scope.host;
    _contributor = host.renderer.addContributor(
      ParticleContributor(_system, texture: widget.texture),
    );
    host.animated.add(this);
    _host = host;
    return SceneNode(name: 'particles');
  }

  @override
  void advance(double seconds) {
    final node = _node;
    if (node == null) return;
    _system
      ..emit(
        this,
        widget.effect,
        node.readWorldPosition(),
        perSecond: widget.visible ? widget.perSecond : 0.0,
      )
      ..advance(seconds);
  }

  @override
  void dispose() {
    final host = _host;
    if (host != null) {
      host.animated.remove(this);
      if (_contributor case final contributor?) {
        host.renderer.removeContributor(contributor);
      }
    }
    super.dispose();
  }
}
