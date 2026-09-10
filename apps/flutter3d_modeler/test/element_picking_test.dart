/// What a click means, checked against a cube whose corners are known numbers.
///
/// **The oracle is the projection done by hand.** Asking `PickingView` where a
/// world point lands on screen and then asking it what a click there picks
/// would pass with the y axis flipped, with the aspect ratio applied to the
/// wrong axis, and with any other error that cancels itself on the way back —
/// which is most of them. So [screenOf] below is the perspective divide written
/// out in the test, from the same four numbers the camera is built with, and
/// every click in this file is placed by it.
///
/// The fixture is `EditMesh.cuboid`, two units on a side and centred on the
/// origin, seen from five units away down +Z. At that distance one world unit
/// is 181 logical pixels across the front face, so a few pixels of slack is a
/// few hundredths of a unit, and every distance in these tests is stated in
/// pixels and converted by the code under test.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, PointerDeviceKind, Rect, Size;

import 'package:flutter3d/flutter3d.dart'
    show CameraNode, PerspectiveProjection;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/element_picking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const Size viewport = Size(800.0, 600.0);
const double fovY = math.pi / 4.0;
const double eyeZ = 5.0;

/// Where [world] lands on screen, worked out here rather than asked of the code
/// under test.
Offset screenOf(Vector3 world) {
  final focal = 1.0 / math.tan(fovY / 2.0);
  final depth = eyeZ - world.z;
  final aspect = viewport.width / viewport.height;
  return Offset(
    ((world.x * focal / (aspect * depth)) + 1.0) * viewport.width / 2.0,
    (1.0 - world.y * focal / depth) * viewport.height / 2.0,
  );
}

/// The viewport a click is measured in: the camera on +Z, looking down -Z,
/// which is where a node with no rotation already looks.
PickingView viewLookingAtTheCube({double near = 0.1}) => PickingView(
  camera: CameraNode(
    projection: PerspectiveProjection(
      fovYRadians: fovY,
      near: near,
      far: 100.0,
    ),
  )..setPosition(0.0, 0.0, eyeZ),
  size: viewport,
);

/// A mesh with the tree a viewport keeps beside it.
MeshPicker pickerFor(EditMesh mesh) =>
    MeshPicker(mesh, MeshBvh(mesh, MeshLayoutPlan()..build(mesh)));

/// The live vertex at [point], which is how a test names a corner without
/// depending on the order `EditMesh.cuboid` happens to add them in.
int vertexAt(EditMesh mesh, Vector3 point) {
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    if (mesh.positionOf(vertex, at).distanceTo(point) < 1e-6) return vertex;
  }
  fail('no vertex at $point');
}

/// The face whose corners all sit at [z], which is how a test names the front
/// or the back of the cube without depending on the order `EditMesh.cuboid`
/// happens to add faces in.
int faceAcross(EditMesh mesh, double z) {
  final at = Vector3.zero();
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    var flat = true;
    mesh.forEachHalfEdge(face, (int half) {
      if ((mesh.positionOf(mesh.originOf(half), at).z - z).abs() > 1e-6) {
        flat = false;
      }
    });
    if (flat) return face;
  }
  fail('no face across z = $z');
}

/// The edge running between [from] and [to], as the half-edge the mesh chose to
/// stand for it.
int edgeBetween(EditMesh mesh, Vector3 from, Vector3 to) {
  final a = Vector3.zero();
  final b = Vector3.zero();
  var found = EditMesh.none;
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) {
      mesh.positionOf(mesh.originOf(half), a);
      mesh.positionOf(mesh.originOf(mesh.nextOf(half)), b);
      final matches =
          (a.distanceTo(from) < 1e-6 && b.distanceTo(to) < 1e-6) ||
          (a.distanceTo(to) < 1e-6 && b.distanceTo(from) < 1e-6);
      if (matches) found = mesh.edgeOf(half);
    });
  }
  if (found == EditMesh.none) fail('no edge between $from and $to');
  return found;
}

void main() {
  group('a click', () {
    test('in the middle of a face picks the face', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: screenOf(Vector3(0.0, 0.0, 1.0)),
        pointer: PointerDeviceKind.mouse,
      );

      // Mutation: the `hit?.face` fall-through at the end of `pickElementAt`
      // replaced by an empty selection. Run, and this fails: a click on the
      // middle of a face would do nothing at all, which is the first thing
      // anybody tries.
      //
      // What this test does not catch, and the corners below do: flipping y in
      // `_ndcOf` leaves it passing, because the middle of the front face is the
      // middle of the screen and the mirror image of the middle is itself. Run,
      // and it stayed green while three other tests went red.
      expect(picked.level, ElementLevel.face);
      expect(picked.ids, <int>[0]);
      expect(picked.active, 0);
    });

    test('in face mode answers the face even a pixel from a corner', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: corner.translate(-1.0, 1.0),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.face,
      );

      // One pixel inside the corner, where free mode answers the vertex and
      // both smaller elements are well within the slack: face mode has to
      // answer the face regardless.
      //
      // Mutation: the `level == ElementLevel.face` branch returning
      // `Selection.empty(ElementLevel.face)`. Run, and this fails. Before it,
      // no test in the file passed `level: ElementLevel.face` at all, so the
      // mode a modeller spends most of its time in could have answered nothing
      // and every assertion here would still have been green.
      expect(picked.level, ElementLevel.face);
      expect(picked.ids, <int>[0]);
    });

    test('three pixels inside an edge picks the edge', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final edge = edgeBetween(
        mesh,
        Vector3(1.0, -1.0, 1.0),
        Vector3(1.0, 1.0, 1.0),
      );
      final onTheEdge = screenOf(Vector3(1.0, 0.0, 1.0));

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: onTheEdge.translate(-3.0, 0.0),
        pointer: PointerDeviceKind.mouse,
      );

      // Mutation: answering the face before the two scans in free mode — the
      // early `level == ElementLevel.face` branch widened to take a null level
      // as well — returns the front face here. The cost is that no edge is ever
      // clickable in free mode, because the face behind it is always under the
      // pointer as well.
      expect(picked.level, ElementLevel.edge);
      expect(picked.ids, <int>[edge]);
    });

    test('three pixels outside the same edge still picks it', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final edge = edgeBetween(
        mesh,
        Vector3(1.0, -1.0, 1.0),
        Vector3(1.0, 1.0, 1.0),
      );
      final onTheEdge = screenOf(Vector3(1.0, 0.0, 1.0));

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: onTheEdge.translate(3.0, 0.0),
        pointer: PointerDeviceKind.mouse,
      );

      // Three pixels the other way is off the model, so nothing is hit and the
      // radius has no surface to be measured at.
      //
      // Mutation: making `_depthOfCentre` return null — which is what having no
      // fallback at all amounts to — turns this into an empty selection. Half
      // of every silhouette is outside the shape, so a person aiming at the
      // outline of their model would find that whether the click worked
      // depended on which side of the outline it landed.
      expect(picked.level, ElementLevel.edge);
      expect(picked.ids, <int>[edge]);
    });

    test('on a corner in free mode picks the vertex over the edge', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = Vector3(1.0, 1.0, 1.0);

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: screenOf(corner),
        pointer: PointerDeviceKind.mouse,
      );

      // Three edges and two faces meet at the pointer, all of them at a gap of
      // nothing, so the only thing choosing between them is the order the
      // scans run in.
      //
      // Mutation: the vertex block and the edge block swapped, which is what a
      // tidy-up that groups the two scans together would do. Run, and this
      // comes back with the edge from (1, -1, 1) to (1, 1, 1): every corner
      // click in free mode would select an edge, and a vertex would be
      // unreachable without switching to vertex mode first.
      expect(picked.level, ElementLevel.vertex);
      expect(picked.ids, <int>[vertexAt(mesh, corner)]);
    });

    test('twelve pixels from a vertex picks nothing with a mouse', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));
      // Twelve pixels diagonally, which stays over the front face rather than
      // sliding off the silhouette.
      final inwards = 12.0 / math.sqrt2;

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: corner.translate(-inwards, inwards),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.vertex,
      );

      // Mutation: `cursorPickSlack = 24.0` selects the corner here. The number
      // is what stops a cursor from snapping to a vertex it is visibly not on,
      // and a person who has just moved a vertex expects the next click twelve
      // pixels away to miss it.
      expect(picked.isEmpty, isTrue);
      expect(picked.level, ElementLevel.vertex);
    });

    test('a finger reaches three times as far', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));
      final inwards = 12.0 / math.sqrt2;

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: corner.translate(-inwards, inwards),
        pointer: PointerDeviceKind.touch,
        level: ElementLevel.vertex,
      );

      // Mutation: `fingerPickSlack = 8.0` — the cursor's number for everyone —
      // leaves this empty. Twelve pixels is well inside the contact patch of a
      // finger, so this is a person pressing on a vertex and being told they
      // pressed on nothing.
      expect(picked.ids, <int>[vertexAt(mesh, Vector3(1.0, 1.0, 1.0))]);
    });

    test('from a stylus reaches like a cursor, from nothing like a finger', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));
      final inwards = 12.0 / math.sqrt2;
      Selection pickedWith(PointerDeviceKind pointer) => pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: corner.translate(-inwards, inwards),
        pointer: pointer,
        level: ElementLevel.vertex,
      );

      // The same twelve pixels as the mouse and the finger above, so the only
      // thing deciding these two is which arm of `pickSlackFor` the kind falls
      // into. A stylus puts a visible point where the person aimed and gets the
      // cursor's eight; an unknown kind is a touchscreen the framework failed
      // to name, and being told the press did nothing is worse than being
      // handed the wrong element.
      //
      // Two mutations, both run. `PointerDeviceKind.unknown` dropped from the
      // first arm empties the second expectation. Moving `fingerPickSlack` to
      // the default arm and naming `PointerDeviceKind.mouse` in the first — so
      // that everything unnamed reaches twenty-four — makes the stylus select
      // the corner and fails the first.
      expect(pickedWith(PointerDeviceKind.stylus).isEmpty, isTrue);
      expect(pickedWith(PointerDeviceKind.unknown).ids, <int>[
        vertexAt(mesh, Vector3(1.0, 1.0, 1.0)),
      ]);
    });

    test('a vertex behind the surface is not offered', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final behind = Vector3(1.0, 1.0, -1.0);

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: screenOf(behind),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.vertex,
      );

      // The ray runs exactly through the far corner, so the only thing keeping
      // it out is the front face in the way.
      //
      // Mutation: `visibleOnly: !throughSurface` written as `visibleOnly: false`
      // in the vertex branch selects the far corner. Dragging it would move a
      // corner on the other side of the model, which a person does not see
      // until they orbit.
      expect(picked.isEmpty, isTrue);
    });

    test('unless the pick is told to reach through the surface', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final behind = Vector3(1.0, 1.0, -1.0);

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: screenOf(behind),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.vertex,
        throughSurface: true,
      );

      // The other half of the test above: without this one, a `vertexNear` that
      // never found anything would pass the occlusion test for the wrong
      // reason. Mutation: `throughSurface` ignored — `visibleOnly: true`
      // always — leaves this empty.
      expect(picked.ids, <int>[vertexAt(mesh, behind)]);
    });

    test('lands in the space the object is placed by', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final placed = Matrix4.translation(Vector3(2.0, 0.0, 0.0));

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: screenOf(Vector3(2.0, 0.0, 1.0)),
        pointer: PointerDeviceKind.mouse,
        objectToWorld: placed,
      );

      // Mutation: ignoring `objectToWorld` — using the world ray as it stands —
      // gives an empty selection, because a ray aimed two units to the right of
      // the origin passes the untransformed cube entirely. An object that has
      // been moved would be unclickable everywhere except where it used to be.
      expect(picked.level, ElementLevel.face);
      expect(picked.ids, <int>[0]);
    });

    test("measures its slack in the scaled object's own units", () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      // Half size, two units to the right: the cube now spans x 1.5 to 2.5 and
      // its front face is at z = 0.5.
      final placed = Matrix4.translation(Vector3(2.0, 0.0, 0.0))
        ..scaleByDouble(0.5, 0.5, 0.5, 1.0);
      final picker = pickerFor(mesh);
      final view = viewLookingAtTheCube();

      final onTheEdge = screenOf(Vector3(2.5, 0.0, 0.5));
      final nearTheEdge = pickElementAt(
        picker,
        view,
        at: onTheEdge.translate(-6.0, 0.0),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.edge,
        objectToWorld: placed,
      );

      final corner = screenOf(Vector3(2.5, 0.5, 0.5));
      final inwards = 12.0 / math.sqrt2;
      final nearTheCorner = pickElementAt(
        picker,
        view,
        at: corner.translate(-inwards, inwards),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.vertex,
        objectToWorld: placed,
      );

      // A radius in pixels is a radius in world units, and in a mesh scaled to
      // half size it is twice as many of the mesh's own units. Both mutations
      // run: dropping the `* ray.shrink` on the radius halves the reach to four
      // pixels and the edge comes back empty; dropping the `/ ray.shrink` on
      // the distance doubles it to sixteen and the corner is selected. Either
      // way the slack a person feels depends on the scale of the object they
      // are editing, which is the one thing it must not do.
      expect(nearTheEdge.ids, <int>[
        edgeBetween(mesh, Vector3(1.0, -1.0, 1.0), Vector3(1.0, 1.0, 1.0)),
      ]);
      expect(nearTheCorner.isEmpty, isTrue);
    });

    test('cannot reach what is in front of the near plane', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));

      final picked = pickElementAt(
        pickerFor(mesh),
        // The near plane is 4.5 away and the front face is 4, so the cube is
        // drawn sliced open and the ray starts inside it.
        viewLookingAtTheCube(near: 4.5),
        at: screenOf(Vector3(0.0, 0.0, 1.0)),
        pointer: PointerDeviceKind.mouse,
      );

      // The face the person can see through the slice is the back one, and
      // that is what a click in the middle of the hole selects. Aiming the ray
      // from the camera's own position instead — the obvious way to build it,
      // and the one the doc argues against — would answer the front face,
      // which at that moment is not drawn anywhere.
      //
      // Mutation: the near end unprojected at depth 0.5 rather than 0.0. The
      // ray then starts 8.6 units from the eye, behind the whole cube, and
      // this comes back empty. Run.
      expect(picked.ids, <int>[faceAcross(mesh, -1.0)]);
    });

    test('at nothing at all answers at the level it was asked about', () {
      final mesh = EditMesh.empty();
      final at = screenOf(Vector3(0.0, 0.0, 1.0));
      final inVertexMode = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: at,
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.vertex,
      );
      final inFreeMode = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: at,
        pointer: PointerDeviceKind.mouse,
      );

      // A mesh with no vertices gives the radius nothing to be measured at, so
      // the pick gives up before either scan. What it gives up as still
      // matters: a selection carries its level, and one that came back as a
      // face selection would drop the modeller out of vertex mode every time
      // somebody clicked on the background.
      //
      // Mutation: `Selection.empty(level ?? ElementLevel.face)` written as
      // `Selection.empty(ElementLevel.vertex)`. Run, and the free-mode line
      // fails; writing the constant the other way round fails the first.
      expect(inVertexMode.isEmpty, isTrue);
      expect(inVertexMode.level, ElementLevel.vertex);
      expect(inFreeMode.isEmpty, isTrue);
      expect(inFreeMode.level, ElementLevel.face);
    });

    test('just outside a lopsided model measures to the middle of it', () {
      // A pyramid: four corners of a base square at z = 1, and an apex nine
      // units behind them. The middle of the box it occupies is at z = -4, four
      // units from the crowd of vertices; the average position is at z = -1,
      // dragged forward by the four that sit together.
      final mesh = EditMesh.fromFaces(
        <Vector3>[
          Vector3(-1.0, -1.0, 1.0),
          Vector3(1.0, -1.0, 1.0),
          Vector3(1.0, 1.0, 1.0),
          Vector3(-1.0, 1.0, 1.0),
          Vector3(0.0, 0.0, -9.0),
        ],
        <List<int>>[
          <int>[0, 1, 2, 3],
          <int>[1, 0, 4],
          <int>[2, 1, 4],
          <int>[3, 2, 4],
          <int>[0, 3, 4],
        ],
      );
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));
      final outwards = 15.0 / math.sqrt2;

      final picked = pickElementAt(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        at: corner.translate(outwards, -outwards),
        pointer: PointerDeviceKind.mouse,
        level: ElementLevel.vertex,
      );

      // Fifteen pixels diagonally off the corner, which is outside the
      // silhouette, so the ray hits nothing and the fallback depth sets the
      // reach. Eight pixels of slack measured at the middle of the box is
      // eighteen pixels of reach at the corner, which is four units nearer the
      // eye; measured at the average position it is twelve, and this comes back
      // empty.
      //
      // Mutation: the `Vector3.min` and `Vector3.max` pair in `_depthOfCentre`
      // replaced by a running sum divided by the count. Run, and this fails.
      // The cube every other test uses is symmetric, so the two agree there and
      // nothing else in the file can tell them apart.
      expect(picked.ids, <int>[vertexAt(mesh, Vector3(1.0, 1.0, 1.0))]);
    });
  });

  group('a rectangle drag', () {
    test('takes the vertices whose projection is inside it', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));

      final picked = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        // A box round one corner of the front face and nothing else. The
        // corners are handed to `Rect.fromPoints`, which sorts them, so this
        // says nothing about a backwards drag — that is the test below.
        rect: Rect.fromPoints(
          corner.translate(30.0, -20.0),
          corner.translate(-20.0, 20.0),
        ),
        level: ElementLevel.vertex,
      );

      // Mutation: `_ndcOf` without the y flip — `2 * dy / height - 1` — comes
      // back with vertex 5, the corner at (1, -1, 1), so a box selection marks
      // the mirror image of what was dragged over. Run, and it fails here.
      expect(picked.ids, <int>[vertexAt(mesh, Vector3(1.0, 1.0, 1.0))]);
    });

    test('written the wrong way round means the same region', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));

      final picked = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        // The same box as above with its edges swapped: right of left, bottom
        // of top. A drag that ends up and to the left of where it began
        // arrives like this whenever the caller keeps the two points as they
        // came rather than sorting them.
        rect: Rect.fromLTRB(
          corner.dx + 30.0,
          corner.dy + 20.0,
          corner.dx - 20.0,
          corner.dy - 20.0,
        ),
        level: ElementLevel.vertex,
      );

      // Mutation: `rect` passed on as it stands instead of through
      // `Rect.fromPoints`. `Rect.isEmpty` is true whenever left is not left of
      // right, so the guard swallows the drag and this comes back empty. Run,
      // and it fails — until this test, the normalisation could be deleted
      // outright with the suite staying green.
      expect(picked.ids, <int>[vertexAt(mesh, Vector3(1.0, 1.0, 1.0))]);
    });

    test('takes a face only when the whole of it is inside', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));

      final onOneCorner = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        rect: Rect.fromPoints(
          corner.translate(-20.0, -20.0),
          corner.translate(30.0, 20.0),
        ),
        level: ElementLevel.face,
      );
      final overTheWholeModel = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        rect: Rect.fromLTRB(0.0, 0.0, viewport.width, viewport.height),
        level: ElementLevel.face,
      );

      // The rule belongs to `Selection.convertedTo` rather than to this file,
      // and the pair is here because a frustum that contained nothing would
      // satisfy the first line on its own. Mutation: the side planes built from
      // the whole viewport rather than from the dragged rectangle — the two
      // `_ndcOf` calls in `frustumOver` replaced by the corners of NDC itself.
      // Run, and the first line fails: a drag over one corner then selects the
      // six faces of the entire model.
      expect(onOneCorner.isEmpty, isTrue);
      expect(overTheWholeModel.length, 6);
    });

    test('of no area selects nothing', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final at = screenOf(Vector3(0.0, 0.0, 1.0));

      final picked = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        rect: Rect.fromPoints(at, at),
        level: ElementLevel.vertex,
      );

      // Mutation: the `box.isEmpty` guard removed from `pickElementsIn` and the
      // throw removed from `frustumOver` — the remap then divides by zero, every
      // plane comes out NaN, and `containsVector3` reports every point as inside
      // because NaN is not less than zero. All eight corners come back, so a
      // click that Flutter happened to deliver as a one-pixel drag selects the
      // entire model. Run, and this is the assertion that fails.
      //
      // Removing the guard alone, without touching `frustumOver`, was run too:
      // this test fails there as well, on the `ArgumentError` coming back
      // through it. What that leaves untested is `frustumOver`'s own refusal,
      // which nothing reaches from here — the test in the group below is the
      // one that pins it.
      expect(picked.isEmpty, isTrue);
    });

    test('leaves out what is in front of the near plane', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final corner = screenOf(Vector3(1.0, 1.0, 1.0));

      final picked = pickElementsIn(
        pickerFor(mesh),
        // The near plane is 4.5 away and the corner is 4, so the corner is in
        // front of it: on screen it is drawn sliced open, and nothing that is
        // not drawn should be selectable.
        viewLookingAtTheCube(near: 4.5),
        rect: Rect.fromPoints(
          corner.translate(-20.0, -20.0),
          corner.translate(30.0, 20.0),
        ),
        level: ElementLevel.vertex,
      );

      // Mutation: the two depth entries dropped from the remap in
      // `frustumOver`, so `Frustum.matrix` reads the matrix in its own OpenGL
      // convention. The near plane it then computes sits at 2.3 rather than 4.5
      // and the corner comes back selected. Run, and this fails — which is the
      // only assertion in the file that touches the depth convention at all.
      // The other way of getting the remap wrong was run too: leaving the depth
      // row as the identity, `setEntry(2, 2, 1.0)` with no `setEntry(2, 3)`,
      // fails here as well.
      expect(picked.isEmpty, isTrue);
    });

    test('follows the object into the space it is placed in', () {
      final mesh = EditMesh.cuboid(size: Vector3(2.0, 2.0, 2.0));
      final placed = Matrix4.translation(Vector3(1.0, 0.0, 0.0));
      // The mesh's corner at (1, 1, 1) is drawn a unit further right, and the
      // box is dragged round where it is drawn.
      final corner = screenOf(Vector3(2.0, 1.0, 1.0));

      final picked = pickElementsIn(
        pickerFor(mesh),
        viewLookingAtTheCube(),
        rect: Rect.fromPoints(
          corner.translate(-20.0, -20.0),
          corner.translate(20.0, 20.0),
        ),
        level: ElementLevel.vertex,
        objectToWorld: placed,
      );

      // Mutation: `objectToWorld` dropped in `frustumOver`, leaving the frustum
      // in world space while the vertices it is tested against are in the
      // mesh's. Run, and this comes back empty: box selection on a model that
      // has been placed anywhere but the origin would mark out a region beside
      // the one dragged. The click path argues the same transform twice over
      // and the drag path had nothing.
      expect(picked.ids, <int>[vertexAt(mesh, Vector3(1.0, 1.0, 1.0))]);
    });
  });

  group('a frustum', () {
    test('over a rectangle of no area is refused', () {
      final view = viewLookingAtTheCube();
      final at = screenOf(Vector3(0.0, 0.0, 1.0));

      expect(
        () => view.frustumOver(Rect.fromPoints(at, at.translate(40.0, 0.0))),
        throwsArgumentError,
      );

      // Forty pixels wide and none high, which is a drag along a straight line.
      // `pickElementsIn` answers an empty selection for that before it builds
      // anything, so this refusal is only ever reached by a caller that builds
      // a frustum of its own — a marquee drawn while the drag is still going,
      // say, which asks for the frustum a frame at a time.
      //
      // Mutation: the throw deleted, leaving the guard in `pickElementsIn`
      // standing. Run, and every test above stays green while this one fails:
      // the remap divides by zero in y, all six planes come back NaN, and a
      // frustum of NaN reports every point in the model as inside it.
    });
  });

  group('a viewport', () {
    test('of no area is refused rather than picked in', () {
      expect(
        () => PickingView(camera: CameraNode(), size: Size.zero),
        throwsArgumentError,
      );

      // Mutation: the check deleted. Nothing throws — `Matrix4.invert` hands
      // back zero for the singular matrix an infinite aspect ratio produces and
      // leaves the copy untouched — so the pick answers from a matrix that is
      // not a camera, and a pointer event delivered before layout picks
      // something at random. There is no assertion here that pins what it picks
      // in that state, which is the point: what is worth pinning is the
      // refusal.
    });
  });
}
