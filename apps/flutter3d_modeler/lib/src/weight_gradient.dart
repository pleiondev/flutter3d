/// Turns a bone weight into a displayed vertex colour — `anim-11`'s own row,
/// the mechanism `view-18`'s app half asks for: "a bone weight → a `color`
/// attribute across five stops, unlit, `tonemap: false`; updated via
/// overwrite."
///
/// **What is not here.** Which joint a person has selected, redrawing after a
/// brush stroke, and the legend's own place in the viewport are `S5`'s own
/// row (`anim-12`/`ui/weight_paint_panel.dart`) — this file is the paint, not
/// the hand holding it. [WeightGradientShading] and [weightGradientSettings]
/// are built and tested here, ready for that row to call; nothing today
/// calls them, which is this pass's own honest gap, the same way `S6`/`S9`
/// write theirs down rather than build past what they were asked for.
///
/// **The colour goes into an already-uploaded [DeviceMesh], not into the
/// [EditMesh] it came from.** `VertexLayout.standard`/`skinned` already carry
/// a `color` attribute — `packages/flutter3d_core/lib/src/geometry/
/// vertex_layout.dart` — and `surface.glsl`'s own `ReadSurface` already multiplies it into
/// the albedo, so no shader or layout work is needed here; what is needed is
/// getting a weight into that channel. [EditMesh] has its own per-corner
/// `colourOf`, and a document command that painted through it would cost a
/// full `toMeshData()` re-triangulation for a channel nothing else about the
/// mesh needs re-cut. [DeviceMesh.overwriteVertices] is the same partial-
/// buffer contract `pro-eng-01`/`view-14` already give a stroke: whole
/// vertices, in place, on the device the mesh already lives on — which is
/// why [paintWeightGradient] copies [DeviceMesh.source]'s own floats forward
/// unchanged and only touches the four it was asked to.
///
/// **One [EditMesh] vertex is not one GPU row.** A flat-shaded corner needs
/// its own normal, so `MeshLayoutPlan` gives two triangles meeting at a hard
/// edge two different rows for what is one vertex in the document — and a
/// weight lives on the document's vertex, not on either row. A plan's own
/// [MeshLayoutPlan.gpuVertexToVertex] is the map back, one entry per row: this
/// is why [paintWeightGradient] takes the plan the mesh was last built with
/// rather than assuming `DeviceMesh.vertexCount == EditMesh.vertexSlotCount`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// One stop of the weight gradient: the sRGB the design named, at [position]
/// along the 0..1 weight axis.
///
/// sRGB, not linear — a legend widget paints a stop's hex directly, the way
/// any other colour on screen is; [weightGradientColor] is what carries the
/// sRGB→linear step, and only for the mesh's own vertex buffer.
final class WeightGradientStop {
  const WeightGradientStop(this.position, this.srgb);

  final double position;
  final Vector3 srgb;
}

/// `#RRGGBB` as sRGB components in 0..1.
Vector3 _srgbFromHex(int hex) => Vector3(
  ((hex >> 16) & 0xFF) / 255.0,
  ((hex >> 8) & 0xFF) / 255.0,
  (hex & 0xFF) / 255.0,
);

/// IEC 61966-2-1, the same curve `SrgbToLinear` in `shaders/lib/color.glsl`
/// applies per fragment — matched here so a weight painted on the CPU reaches
/// the screen at the same value a texture authored in sRGB would.
double _srgbChannelToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

Vector3 _srgbToLinear(Vector3 srgb) => Vector3(
  _srgbChannelToLinear(srgb.x),
  _srgbChannelToLinear(srgb.y),
  _srgbChannelToLinear(srgb.z),
);

/// The five stops the design names, `#2A3A7A` at no influence through
/// `#FF3B5C` at full — the same order `ui/weight_legend.dart`'s own bar reads
/// left to right, and the same hexes `screen 13`'s hand-over spells out.
final List<WeightGradientStop> kWeightGradientStops = <WeightGradientStop>[
  WeightGradientStop(0.00, _srgbFromHex(0x2A3A7A)),
  WeightGradientStop(0.25, _srgbFromHex(0x4AA3FF)),
  WeightGradientStop(0.50, _srgbFromHex(0x7EE081)),
  WeightGradientStop(0.75, _srgbFromHex(0xFFB347)),
  WeightGradientStop(1.00, _srgbFromHex(0xFF3B5C)),
];

double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

/// [weight] (clamped to 0..1) as a linear RGBA colour, opaque — piecewise
/// linear between [kWeightGradientStops] **in sRGB**, so a weight of 0.5
/// reads as the middle of the legend's own bar, and converted to linear only
/// once, at the end, which is what makes the value this writes into a vertex
/// buffer paint on screen as the hex the design named rather than as that hex
/// darkened by a missing decode.
Vector4 weightGradientColor(double weight) {
  final w = _clamp01(weight);
  final stops = kWeightGradientStops;

  Vector3 srgb;
  if (w <= stops.first.position) {
    srgb = stops.first.srgb;
  } else if (w >= stops.last.position) {
    srgb = stops.last.srgb;
  } else {
    var i = 0;
    while (i < stops.length - 2 && w > stops[i + 1].position) {
      i++;
    }
    final a = stops[i];
    final b = stops[i + 1];
    final t = (w - a.position) / (b.position - a.position);
    srgb = Vector3(
      a.srgb.x + (b.srgb.x - a.srgb.x) * t,
      a.srgb.y + (b.srgb.y - a.srgb.y) * t,
      a.srgb.z + (b.srgb.z - a.srgb.z) * t,
    );
  }

  final linear = _srgbToLinear(srgb);
  return Vector4(linear.x, linear.y, linear.z, 1.0);
}

/// Every live vertex of [mesh]'s own weight on [localJoint] — `weightsOf`'s
/// own local, vertex-attribute-slot index, not a `ModelObject` id — summed
/// across whichever of its (at most four) stored slots name it, since nothing
/// stops a vertex from ever holding two.
///
/// The list is sized to [EditMesh.vertexSlotCount], indexed the same way
/// [MeshLayoutPlan.gpuVertexToVertex] answers — a dead slot is never read
/// back by that map and is left at zero here for the same reason.
List<double> vertexWeightsForJoint(EditMesh mesh, int localJoint) {
  final out = List<double>.filled(mesh.vertexSlotCount, 0.0);
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    var weight = 0.0;
    for (final pair in weightsOf(mesh, v)) {
      if (pair.joint == localJoint) weight += pair.weight;
    }
    out[v] = weight;
  }
  return out;
}

/// Overwrites [mesh]'s own `color` attribute with [weightGradientColor] of
/// each entry of [vertexWeights] — one weight per **document** vertex,
/// indexed the way [vertexWeightsForJoint] returns and [plan]'s own
/// [MeshLayoutPlan.gpuVertexToVertex] maps a GPU row back to.
///
/// [plan] must be the plan [mesh] was last uploaded from — [MeshLayoutPlan.
/// build] against the same [EditMesh], or the row count below refuses rather
/// than write past a mesh the plan disagrees with about how many rows there
/// are.
///
/// [DeviceMesh.overwriteVertices]'s own whole-vertex contract means every
/// other attribute has to travel unchanged: this copies [DeviceMesh.source]'s
/// floats forward and only replaces the four at [VertexLayout.color]'s own
/// offset — 12 of 16 (`VertexLayout.standard`) or 24 (`VertexLayout.skinned`),
/// confirmed against the layout actually carried rather than assumed.
void paintWeightGradient({
  required GraphicsDevice device,
  required DeviceMesh mesh,
  required MeshLayoutPlan plan,
  required List<double> vertexWeights,
}) {
  final source = mesh.source;
  if (source == null) {
    throw StateError(
      'paintWeightGradient: mesh has no source data — it was uploaded with '
      'keepSourceData: false, and a colour overwrite needs the other '
      "attributes to copy back unchanged; DeviceMesh.upload's own default "
      'keeps it.',
    );
  }
  final rowToVertex = plan.gpuVertexToVertex;
  if (rowToVertex.length != mesh.vertexCount) {
    throw ArgumentError(
      'paintWeightGradient: plan has ${rowToVertex.length} rows for a '
      '${mesh.vertexCount}-vertex mesh — build the plan against the same '
      'EditMesh this mesh was uploaded from',
    );
  }
  final colorOffset = source.layout.floatOffsetOf(VertexLayout.color.name);
  if (colorOffset < 0) {
    throw StateError(
      "paintWeightGradient: ${source.layout} carries no 'color' attribute",
    );
  }

  final floatsPerVertex = source.layout.floatsPerVertex;
  final out = Float32List.fromList(source.vertices);
  for (var row = 0; row < rowToVertex.length; row++) {
    final vertex = rowToVertex[row];
    final weight = vertex >= 0 && vertex < vertexWeights.length
        ? vertexWeights[vertex]
        : 0.0;
    final color = weightGradientColor(weight);
    final base = row * floatsPerVertex + colorOffset;
    out[base] = color.x;
    out[base + 1] = color.y;
    out[base + 2] = color.z;
    out[base + 3] = color.w;
  }

  mesh.overwriteVertices(
    device,
    0,
    out.buffer.asByteData(out.offsetInBytes, out.lengthInBytes),
  );
}

/// The material the weights view draws with: unlit and white, so a surface's
/// albedo is exactly [paintWeightGradient]'s own vertex colour with nothing
/// else tinting it — the same reasoning `SurfaceShading.normals` gives the
/// normals view in `display_modes.dart`, one lighting model swapped in for a
/// diagnostic that is not a picture of light.
final Material kWeightGradientMaterial = Material(
  name: 'weights',
  lighting: LightingModel.unlit,
);

/// [RenderSettings] the weights view draws with, over whatever a viewport
/// already has.
///
/// Tone mapping and a lit scene's exposure would corrupt a vertex colour the
/// same way they would a normal — `display_modes.dart`'s own `settingsFor`
/// gives `ShadingMode.normals` this exact pair for this exact reason, down to
/// the neutral exposure: a colour named by hex is not scene-referred light,
/// and only reads back as that hex once both are out of the way.
/// `gfx-40n`: `forMeasurement` rather than the pair this used to build by
/// hand. The pair was incomplete — it left bloom and the occlusion running
/// over a buffer whose bytes are meant to be the gradient's own numbers.
RenderSettings weightGradientSettings(RenderSettings over) =>
    over.forMeasurement();

/// Swaps every mesh under a subject for [kWeightGradientMaterial] and back —
/// `SurfaceShading`'s own shape in `display_modes.dart`, repeated here rather
/// than reused because the two remember different things under different
/// keys and a shared base class would cost more than the four lines it saved.
///
/// Idempotent, and meant to be called every frame the weights view might be
/// open rather than only when it changes — a model opened while the view is
/// already on brings nodes this has never seen, and skipping the walk would
/// leave those drawn with their own material in a view that is meant to show
/// weights.
final class WeightGradientShading {
  final Map<MeshNode, Material> _own = <MeshNode, Material>{};

  /// Draws every [MeshNode] under [subject] with [kWeightGradientMaterial]
  /// when [active], and puts back whatever it took away otherwise.
  ///
  /// **The memory lasts exactly as long as the swap does.** What this
  /// recorded the first time it saw a node, it then wrote back on every frame
  /// the weights view was *off* — which is every frame of an ordinary
  /// session, since this is walked whether or not the sub-mode is open. A
  /// material edited afterwards reached the node and was painted over again
  /// before the next frame was drawn, so the model stayed the colour it was
  /// when the window opened however the document changed. `SurfaceShading`
  /// had the same fault and is fixed the same way.
  void apply(SceneNode subject, {required bool active}) {
    if (!active) {
      for (final MapEntry<MeshNode, Material> each in _own.entries) {
        each.key.material = each.value;
      }
      _own.clear();
      return;
    }
    subject.traverse((SceneNode node) {
      if (node is! MeshNode) return;
      // Already swapped — asked of the node rather than of the map, so a
      // material `SceneSync` wrote *during* a weights session is the one put
      // back at the end of it rather than the one from before it began.
      if (identical(node.material, kWeightGradientMaterial)) return;
      _own[node] = node.material;
      node.material = kWeightGradientMaterial;
    });
  }

  /// Forgets everything, for a subject that has been replaced.
  void forget() => _own.clear();
}
