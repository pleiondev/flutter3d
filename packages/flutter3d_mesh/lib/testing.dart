/// Meshes to point a test at.
///
/// **Four shapes, each one the smallest thing that would look wrong if an
/// operation broke.** A picture of a cube says nothing — a cube looks like a
/// cube whatever the normals are doing. What these are for is the opposite: an
/// extrusion whose walls are missing, a loop cut that zig-zagged, a lathe whose
/// pole came apart, a rim that stopped being sharp are all things a person sees
/// at a glance and no count catches.
///
/// **In the package rather than in the test, because the test may not build
/// its own world.** `no test builds its own world` in `tool/structure.dart`
/// refuses a harness that stands up its own scene; the same argument applies to
/// the geometry under it. A fixture here is used by the application's frame
/// tests and by anything else that wants a mesh with something to look at.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'src/attributes.dart';
import 'src/bevel.dart';
import 'src/bsp.dart';
import 'src/cut.dart';
import 'src/edit_mesh.dart';
import 'src/extrude.dart';
import 'src/mirror.dart';
import 'src/operations.dart';
import 'src/parametric.dart';
import 'src/parts.dart';
import 'src/selection.dart';
import 'src/subdivide.dart';

/// Every live face of [mesh].
Selection _allFaces(EditMesh mesh) => Selection.of(ElementLevel.face, <int>[
  for (var face = 0; face < mesh.faceSlotCount; face++)
    if (mesh.isFaceAlive(face)) face,
]);

/// A box with one face pushed out and the top of the tower narrowed.
///
/// Two extrusions rather than one, because a single one is symmetric enough to
/// look right with a wall missing; the second gives the shape a silhouette that
/// only closes if every wall of both is there.
EditMesh extrudedBox() {
  final mesh = ParametricCuboid().toEditMesh();
  // Face 2 is the +Y one in the table the cuboid shares with the engine, so
  // the tower goes up — which is the direction a viewport frames best.
  final top = Selection.of(ElementLevel.face, <int>[2]);
  mesh.beginStep();
  extrudeFaces(mesh, top, distance: 0.7);
  extrudeFaces(mesh, top, distance: 0.5);
  scaleSelection(mesh, top, by: Vector3(0.45, 0.45, 0.45));
  mesh
    ..endStep()
    ..clearJournal();
  return mesh;
}

/// A cylinder with three loops cut across it and the middle one pulled out.
///
/// A cut that went in straight is invisible; a cut that zig-zagged shows the
/// moment the ring it made is moved, because the ring stops being a circle.
EditMesh cutCylinder() {
  final mesh = const ParametricCylinder(
    radiusTop: 0.45,
    radiusBottom: 0.45,
    height: 1.4,
    segments: 20,
  ).toEditMesh();

  var upright = EditMesh.none;
  for (
    var face = 0;
    face < mesh.faceSlotCount && upright == EditMesh.none;
    face++
  ) {
    if (mesh.valencyOf(face) != 4) continue;
    mesh.forEachHalfEdge(face, (int half) {
      final from = mesh.positionOf(mesh.originOf(half));
      final to = mesh.positionOf(mesh.originOf(mesh.nextOf(half)));
      if ((from.y - to.y).abs() > 0.5) upright = half;
    });
  }

  mesh.beginStep();
  final cut = loopCut(
    mesh,
    Selection.of(ElementLevel.edge, <int>[mesh.edgeOf(upright)]),
    cuts: 3,
  );
  // The middle ring of the three, pushed out so the cuts have a shape.
  final middle = <int>[
    for (final vertex in cut.selection.ids)
      if (mesh.positionOf(vertex).y.abs() < 0.05) vertex,
  ];
  scaleSelection(
    mesh,
    Selection.of(ElementLevel.vertex, middle),
    by: Vector3(1.7, 1, 1.7),
    pivot: Vector3.zero(),
  );
  mesh
    ..endStep()
    ..clearJournal();
  return mesh;
}

/// A profile turned on the lathe: a vase with a foot, a belly and a lip.
///
/// The pole at the bottom is the part worth a picture — a fan that came apart
/// leaves a hole nothing else reports.
EditMesh turnedProfile() => ParametricLathe(
  profile: <Vector2>[
    Vector2(0, -0.75),
    Vector2(0.34, -0.75),
    Vector2(0.20, -0.55),
    Vector2(0.42, -0.15),
    Vector2(0.46, 0.25),
    Vector2(0.26, 0.55),
    Vector2(0.34, 0.75),
  ],
  segments: 24,
  name: 'vase',
).toEditMesh();

/// Two cylinders side by side, the left one with its wall marked sharp and the
/// right one left smooth.
///
/// **The one fixture whose whole point is a flag.** Both halves have the same
/// vertices, the same faces and the same volume; what differs is where the
/// shading breaks. Sixteen sides puts each facet 22.5° from the next — inside
/// the thirty degrees a smoothing threshold allows — so the angle alone would
/// round both of them off, and only the flag makes one read as sixteen flat
/// panels. Marking the *rims* instead would have shown nothing: a right angle
/// between a cap and a wall breaks at any threshold anybody would set.
EditMesh sharpAgainstSmooth() {
  final mesh = const ParametricCylinder(
    radiusTop: 0.5,
    radiusBottom: 0.5,
    height: 1.1,
    segments: 16,
  ).toEditMesh();

  final original = _allFaces(mesh);
  mesh.beginStep();
  final copy = duplicateSelection(mesh, original);
  translateSelection(mesh, copy.selection, by: Vector3(0.75, 0, 0));
  // The original goes the other way, so the pair straddles the origin and the
  // camera frames both.
  translateSelection(mesh, original, by: Vector3(-0.75, 0, 0));

  for (final face in original.ids) {
    mesh.forEachHalfEdge(face, (int half) {
      final from = mesh.positionOf(mesh.originOf(half));
      final to = mesh.positionOf(mesh.originOf(mesh.nextOf(half)));
      // The uprights of the wall, which is where the two halves part company.
      if ((from.y - to.y).abs() > 0.5) {
        mesh.setEdgeFlag(half, EdgeFlags.sharp, on: true);
      }
    });
  }
  for (final face in copy.selection.ids) {
    mesh.forEachHalfEdge(face, (int half) {
      mesh.setEdgeFlag(half, EdgeFlags.sharp, on: false);
    });
  }
  mesh
    ..endStep()
    ..clearJournal();
  return mesh;
}

/// A cube with every edge given a shallow, flat bevel.
///
/// `mesh-44`'s own acceptance is the vertex and face count on exactly this
/// shape; this is the same construction kept as a picture, since a count
/// cannot say whether a corner cap landed at the right valence or a bridge
/// quad came out inverted.
EditMesh bevelledCube() {
  final mesh = EditMesh.cuboid();
  final edges = <int>[
    for (var half = 0; half < mesh.halfEdgeSlotCount; half++)
      if (mesh.edgeOf(half) == half && mesh.faceOf(half) != EditMesh.none) half,
  ];
  mesh.beginStep();
  bevelEdges(mesh, Selection.of(ElementLevel.edge, edges), width: 0.12);
  mesh
    ..endStep()
    ..clearJournal();
  return mesh;
}

/// A cube, twice Catmull-Clark subdivided.
///
/// `mesh-45`'s own acceptance is one level's vertex and face count; two
/// levels is what a person actually turns on to round a box off, and is
/// dense enough that a missing crease or an inverted quad reads as a visible
/// dent rather than a number one level off.
EditMesh subdividedCube() => catmullClark(EditMesh.cuboid(), levels: 2);

/// A cube with a sphere cut from one corner of it.
///
/// **Off-centre on purpose, unlike `bsp_test.dart`'s own fixture.** A sphere
/// cut from dead centre and fully inside the cube — the case that fixture's
/// own volume tolerance is built to check — leaves the cube's outer surface
/// untouched, so a boolean that silently did nothing would draw the same
/// picture as a correct one. Pushing the sphere half out through a corner
/// carves a real, visible crater into two faces at once, which is what
/// `mesh-47`'s own row asks a picture to show that a volume number cannot.
EditMesh cubeMinusSphere() {
  final cube = EditMesh.cuboid(size: Vector3(1.4, 1.4, 1.4));
  final sphere = const ParametricSphere(
    radius: 0.55,
    segments: 24,
    rings: 12,
  ).toEditMesh();
  final corner = Vector3(0.7, 0.7, 0.7);
  sphere.beginStep();
  for (var v = 0; v < sphere.vertexSlotCount; v++) {
    if (!sphere.isVertexAlive(v)) continue;
    sphere.moveVertex(v, sphere.positionOf(v) + corner);
  }
  sphere.endStep();
  final result = booleanSubtract(cube, sphere);
  if (result == null) {
    throw StateError('cube minus sphere refused to build a fixture');
  }
  return result.mesh;
}

/// Half a vase, lathed with a 180° sweep and mirrored across the plane it
/// already touches.
///
/// **Why a half sweep rather than a whole one mirrored again.** `mirror`'s
/// own doc comment describes its ordinary case as a base that already
/// touches the plane it is reflected across — a lathe swept from `-π/2` to
/// `π/2` puts both its open edges exactly on the plane `x = 0` (`cos(±π/2) ==
/// 0`), which is precisely that case rather than a shape built to sit near
/// the plane by construction. `mesh-41`'s own row is the reason this picture
/// is named for the mirror rather than for the vase: a whole lathed vase
/// would look identical whether or not `mirror` ran at all.
EditMesh mirroredVase() {
  final half = ParametricLathe(
    profile: <Vector2>[
      Vector2(0, -0.75),
      Vector2(0.34, -0.75),
      Vector2(0.20, -0.55),
      Vector2(0.42, -0.15),
      Vector2(0.46, 0.25),
      Vector2(0.26, 0.55),
      Vector2(0.34, 0.75),
    ],
    segments: 12,
    startAngle: -math.pi / 2,
    sweepAngle: math.pi,
    name: 'half-vase',
  ).toEditMesh();
  return mirror(half, normal: Vector3(1, 0, 0), mergeDistance: 1e-4);
}
