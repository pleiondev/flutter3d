/// What a debug view shows in place of the light, and where on the frame —
/// `P6`, with the geometry, identity and validation channels of `A5.21` and
/// the two-channel wipe of `A5.22`.
///
/// Its own file rather than a stretch of `render_settings.dart`, which
/// re-exports it: these types are the shader contract of `WriteDebugView` in
/// `surface.glsl` as much as they are settings.
library;

/// What kind of question a [DebugView] answers, for a tool that lists them
/// in groups.
///
/// **A final class with const instances rather than an enum**, so a kind
/// added later breaks no switch anybody has written over these.
final class DebugViewKind {
  const DebugViewKind._(this.name);

  /// The name it is written down as.
  final String name;

  /// The lit picture: [DebugView.off] alone.
  static const DebugViewKind lit = DebugViewKind._('lit');

  /// A material's own numbers after its maps: albedo, roughness and the rest.
  static const DebugViewKind material = DebugViewKind._('material');

  /// The mesh under the material: its normals, tangents, coordinates,
  /// winding and vertex colour.
  static const DebugViewKind geometry = DebugViewKind._('geometry');

  /// A flat colour per object or per material, to tell draws apart.
  static const DebugViewKind identity = DebugViewKind._('identity');

  /// A check that paints what breaks a rule red and what keeps it calm.
  static const DebugViewKind validation = DebugViewKind._('validation');

  /// All of them, in the order a tool lists them.
  static const List<DebugViewKind> values = <DebugViewKind>[
    lit,
    material,
    geometry,
    identity,
    validation,
  ];

  @override
  String toString() => 'DebugViewKind.$name';
}

/// What a debug view shows in place of the light — `P6`.
///
/// **A final class with const instances rather than an enum**, for the reason
/// `ViewportShading` is one: [code] is what `FragInfo.debug_view` carries
/// to four backends, a number this type owns.
///
/// **A registry by name.** [values] lists every view, [byName] finds one
/// from what a tool, a level file or an MCP call wrote down, and [toJson]
/// describes one with the sentence a tool shows beside it.
final class DebugView {
  const DebugView._(this.name, this.code, this.kind, this.description);

  /// The name it is written down as, and what [byName] takes.
  final String name;

  /// What goes into `FragInfo.debug_view`. Part of the shader contract.
  final double code;

  /// Which group a tool lists it under.
  final DebugViewKind kind;

  /// One sentence on what the view paints and how to read it.
  final String description;

  /// The lit picture, untouched — the default, and an exact no-op.
  static const DebugView off = DebugView._(
    'off',
    0.0,
    DebugViewKind.lit,
    'The lit picture, untouched.',
  );

  /// The base colour after its texture, tint and vertex colour, as the sRGB
  /// colour a texture is painted in.
  static const DebugView albedo = DebugView._(
    'albedo',
    1.0,
    DebugViewKind.material,
    'The base colour after its texture, tint and vertex colour, in sRGB.',
  );

  /// The shading normal, after the normal map, as `n · 0.5 + 0.5` in world
  /// space — the normal map's work, which the surface buffer's geometric
  /// normal does not show.
  static const DebugView normal = DebugView._(
    'normal',
    2.0,
    DebugViewKind.geometry,
    'The shading normal after the normal map, n * 0.5 + 0.5 in world space.',
  );

  /// Perceptual roughness as a grey, after the metal-rough map.
  static const DebugView roughness = DebugView._(
    'roughness',
    3.0,
    DebugViewKind.material,
    'Perceptual roughness as a grey, after the metal-rough map.',
  );

  /// Metalness as a grey, after the metal-rough map.
  static const DebugView metallic = DebugView._(
    'metallic',
    4.0,
    DebugViewKind.material,
    'Metalness as a grey, after the metal-rough map.',
  );

  /// The occlusion map's share of light left, as a grey.
  static const DebugView occlusion = DebugView._(
    'occlusion',
    5.0,
    DebugViewKind.material,
    'The share of light the occlusion map leaves, as a grey.',
  );

  /// Emission as its sRGB colour, clipped at one.
  static const DebugView emissive = DebugView._(
    'emissive',
    6.0,
    DebugViewKind.material,
    'Emission as its sRGB colour, clipped at one.',
  );

  /// The base colour map's coordinate, its fraction in red and green: a seam
  /// is a step in colour, a stretched island a long gradient.
  static const DebugView uv = DebugView._(
    'uv',
    7.0,
    DebugViewKind.geometry,
    'The base colour map coordinate, its fraction in red and green.',
  );

  /// Magenta wherever the light came out NaN or infinite, over the light's
  /// own luminance in a dark grey — where a bad normal, a zero-length vector
  /// or a division by nought turned shading into nothing.
  static const DebugView nonFinite = DebugView._(
    'nonFinite',
    8.0,
    DebugViewKind.validation,
    'Magenta where the light is NaN or infinite, over its luminance in grey.',
  );

  /// The vertex tangent, re-orthogonalised against the normal, as
  /// `t · 0.5 + 0.5` in world space. Black where the mesh has no usable
  /// tangent; see [missingTangents] for that question asked directly.
  static const DebugView tangent = DebugView._(
    'tangent',
    9.0,
    DebugViewKind.geometry,
    'The vertex tangent, t * 0.5 + 0.5 in world space; black where none.',
  );

  /// A checkerboard of eight squares a unit of the base colour map's
  /// coordinate, its cells tinted by where in the unit square they sit.
  ///
  /// **Squares should stay square.** A stretched cell is a stretched island,
  /// a cell twice the size of its neighbours is texel density halved, and a
  /// seam shows as the pattern jumping. The tint says which tile of a
  /// repeating coordinate a cell belongs to, so a mirrored island reads as
  /// its colours running backwards.
  static const DebugView uvChecker = DebugView._(
    'uvChecker',
    10.0,
    DebugViewKind.geometry,
    'A checkerboard on the base colour map coordinate: stretch, density '
        'and seams.',
  );

  /// Blue where the camera sees a triangle's front, red where it sees its
  /// back — the back of a double-sided surface, or a mesh whose winding is
  /// inside out. A single-sided material culls its backs, so they never
  /// reach this view; set `RenderMaterial.doubleSided` to see them.
  static const DebugView faceOrientation = DebugView._(
    'faceOrientation',
    11.0,
    DebugViewKind.geometry,
    'Blue for a front face, red for a back face.',
  );

  /// The vertex colour as authored, linear per glTF, shown as sRGB, with its
  /// alpha as the coverage. White where the mesh carries none.
  static const DebugView vertexColor = DebugView._(
    'vertexColor',
    12.0,
    DebugViewKind.geometry,
    'The vertex colour as authored, shown in sRGB; white where there is none.',
  );

  /// A flat colour per drawn node, picked from its identity: two nodes side
  /// by side are two colours, one node split across draws is one.
  ///
  /// The colour is stable for the life of the node and not across runs: it
  /// tells draws apart, it does not name them. Shaded a little by the normal
  /// so a shape still reads as a shape.
  static const DebugView objectIdentity = DebugView._(
    'objectIdentity',
    13.0,
    DebugViewKind.identity,
    'A flat colour per node: which surfaces are one object.',
  );

  /// A flat colour per material, as [objectIdentity] is per node: a hundred
  /// crates that share a material are one colour, and the one that does not
  /// stands out.
  static const DebugView materialIdentity = DebugView._(
    'materialIdentity',
    14.0,
    DebugViewKind.identity,
    'A flat colour per material: which surfaces share one.',
  );

  /// The albedo checked against the range a physically based material
  /// keeps, in sRGB: a non-metal darker than 30 of 255 is painted blue, one
  /// with a channel brighter than 240 red, and a metal whose colour is
  /// darker than 180 yellow. Everything inside the range shows its own
  /// luminance as a grey.
  ///
  /// The bounds are the usual ones for an albedo meant to be lit: charcoal
  /// is about 30, fresh snow about 240, and no real metal reflects less than
  /// about seventy per cent. A texture outside them still renders; it will
  /// read too dark or too bright under any light the scene is given.
  static const DebugView albedoRange = DebugView._(
    'albedoRange',
    15.0,
    DebugViewKind.validation,
    'Albedo out of range: blue too dark, red too bright, yellow a dark metal.',
  );

  /// Metalness checked for being a switch: nought shows dark grey, one shows
  /// white, and anything more than a twentieth from either is orange.
  ///
  /// A surface is a metal or it is not. A map with greys in it is usually a
  /// metalness map read as sRGB, or one painted soft at the edges of a
  /// scratch, and both shade as a material that does not exist.
  static const DebugView metalBinary = DebugView._(
    'metalBinary',
    16.0,
    DebugViewKind.validation,
    'Metalness that is neither nought nor one, in orange.',
  );

  /// Red where the material has a normal map and the mesh no usable tangent
  /// to read it along, green where it has both, and grey where the material
  /// has no normal map and a tangent would not be read.
  ///
  /// A missing tangent does not fail loudly: the shader keeps the vertex
  /// normal, and the relief the map was painted with is simply not there.
  static const DebugView missingTangents = DebugView._(
    'missingTangents',
    17.0,
    DebugViewKind.validation,
    'Red where a normal map has no tangent to read it along.',
  );

  /// All of them, off first, in [code] order.
  static const List<DebugView> values = <DebugView>[
    off,
    albedo,
    normal,
    roughness,
    metallic,
    occlusion,
    emissive,
    uv,
    nonFinite,
    tangent,
    uvChecker,
    faceOrientation,
    vertexColor,
    objectIdentity,
    materialIdentity,
    albedoRange,
    metalBinary,
    missingTangents,
  ];

  /// The view written down as [name], or null when there is none — what a
  /// tool asks with a name it was given.
  static DebugView? byName(String name) {
    for (final view in values) {
      if (view.name == name) return view;
    }
    return null;
  }

  /// What a tool lists: the name, the kind and the sentence.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'kind': kind.name,
    'description': description,
  };

  @override
  String toString() => 'DebugView.$name';
}

/// Which side of a two-channel wipe something is drawn on — `A5.22`.
///
/// A final class with const instances rather than an enum, for the reason
/// [DebugViewKind] is one.
final class DebugWipeSide {
  const DebugWipeSide._(this.name);

  /// The name it is written down as.
  final String name;

  /// The whole frame, the wipe ignored.
  static const DebugWipeSide both = DebugWipeSide._('both');

  /// Left of `DebugViewSettings.split` only.
  static const DebugWipeSide left = DebugWipeSide._('left');

  /// Right of `DebugViewSettings.split` only.
  static const DebugWipeSide right = DebugWipeSide._('right');

  /// All of them, [both] first.
  static const List<DebugWipeSide> values = <DebugWipeSide>[both, left, right];

  @override
  String toString() => 'DebugWipeSide.$name';
}

/// A channel shown in place of the light, over all or part of the frame —
/// `P6` — and a second one beside it — `A5.22`.
///
/// **Written by the materials, not read back from a buffer**, which is what
/// sets this apart from `ViewportShadingSettings`: the surface buffer keeps a
/// geometric normal, a roughness and a depth, and the channels a look-dev
/// question is about — an albedo too bright, a metalness map read as sRGB, a
/// seam in the UVs — exist only inside the lit stage. Each lit model asks
/// `WriteDebugView` before it writes its light. A stage that is not a lit
/// material — the sky, particles, splats, glass's own pass — draws as it
/// always does, and on a side that shows a channel it reaches the screen
/// without the tone curve, so it reads brighter there than it is.
///
/// **The split is a wipe.** Left of [split] the frame shows [left], right of
/// it [view], in one draw. [left] is [DebugView.off] by default, so the
/// left is lit as ever and a material shows where its map and its light
/// disagree without two captures to line up; set it to a channel and the
/// wipe compares two channels — the normal map against the tangents, the
/// albedo against its range check. Nought is [view] over the whole frame.
///
/// **Overlays follow the wipe.** [overlays] confines the debug lines
/// (`RenderSettings.debug`, the highlight, `Renderer.debugLines`) and every
/// overlay contributor (`PassContributor.isOverlay`, the editor's
/// wireframe) to one side, so the wireframe sits over the channel it
/// explains and the other side stays clean. `RenderSettings.wireframe` is a
/// polygon mode, not an overlay, and stays over the whole frame.
///
/// **A subtree can have its own view** — `SceneNode.debugView`. It shows
/// across the whole frame, without the wipe, and [DebugView.off] there
/// keeps the subtree lit while the rest shows a channel.
///
/// **Passes between the materials and the composite still run.** Reflections,
/// depth of field, motion blur and a temporal resolve work on whatever the
/// scene holds, so turn them off for a clean read of a channel. The
/// composite's exposure, curve, bloom and grade do not touch a side that
/// shows a channel.
final class DebugViewSettings {
  const DebugViewSettings({
    this.view = DebugView.off,
    this.split = 0.0,
    this.left = DebugView.off,
    this.overlays = DebugWipeSide.both,
  });

  /// The channel right of [split]. [DebugView.off] is the default and, with
  /// [left] off too, an exact no-op.
  final DebugView view;

  /// Where the wipe stands, as a share of the width from the left: nought
  /// [view] over the whole frame, a half [left] on the left half and [view]
  /// on the right. Held inside nought and one.
  final double split;

  /// The channel left of [split]: [DebugView.off], the lit picture, unless
  /// a second channel is wanted beside [view].
  final DebugView left;

  /// Which side of the wipe the overlays draw on — [DebugWipeSide.both], the
  /// whole frame, by default.
  final DebugWipeSide overlays;

  /// Whether the right of the wipe shows a channel.
  bool get showsRight => view != DebugView.off && split < 1.0;

  /// Whether the left of the wipe shows a channel.
  bool get showsLeft => left != DebugView.off && split > 0.0;

  /// Whether a frame drawn with these shows a channel anywhere.
  bool get active => showsRight || showsLeft;

  DebugViewSettings copyWith({
    DebugView? view,
    double? split,
    DebugView? left,
    DebugWipeSide? overlays,
  }) => DebugViewSettings(
    view: view ?? this.view,
    split: split ?? this.split,
    left: left ?? this.left,
    overlays: overlays ?? this.overlays,
  );
}
