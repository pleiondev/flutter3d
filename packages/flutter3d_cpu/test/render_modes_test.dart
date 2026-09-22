/// `mcp-08n`'s own acceptance: `normals` on an inverted shell differs from
/// `material` by more than 20% of pixels — checked against a real
/// `CpuDevice`, since the point is what actually lands on screen.
///
///     dart test test/render_modes_test.dart
///
/// **And the fourth mode, which the row shipped without.** `wireframe`
/// landed 2026-09-17 as geometry — a three-sided prism per polygon edge —
/// rather than as the line topology `view-07` will eventually give the live
/// viewport; `wire_overlay.dart` argues that trade. The checks below are the
/// two things that could be quietly wrong about it: that the edges are the
/// *document's* and not the triangulation's, and that the picture actually
/// changes.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

GraphicsDevice _cpuDevice(int width, int height) => CpuDevice(
  width: width,
  height: height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

void main() {
  test('normals on an inverted shell differs from material by more than 20% '
      'of pixels', () async {
    final shell = EditMesh.cuboid(size: Vector3(2, 2, 2))
      ..beginStep()
      ..flipNormals()
      ..endStep();
    final project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'shell',
        geometry: EditedGeometry(shell),
        transform: Matrix4.identity(),
      ),
    );

    final material = await renderProject(
      RenderRequest(project: project, width: 64, height: 64),
      deviceFactory: _cpuDevice,
    );
    final normals = await renderProject(
      RenderRequest(
        project: project,
        width: 64,
        height: 64,
        shading: RenderShading.normals,
      ),
      deviceFactory: _cpuDevice,
    );

    final decodedMaterial = (await decodeImagePure(material))!;
    final decodedNormals = (await decodeImagePure(normals))!;

    var differingPixels = 0;
    final pixelCount = decodedMaterial.width * decodedMaterial.height;
    for (var i = 0; i < decodedMaterial.pixels.length; i += 4) {
      var differs = false;
      for (var c = 0; c < 3; c++) {
        if ((decodedMaterial.pixels[i + c] - decodedNormals.pixels[i + c])
                .abs() >
            8) {
          differs = true;
          break;
        }
      }
      if (differs) differingPixels++;
    }

    expect(
      differingPixels / pixelCount,
      greaterThan(0.2),
      reason:
          'material and normals shading of an inverted shell should '
          'read as visibly different pictures across most of the frame, '
          'not just at a seam',
    );
  });

  test("the wires are the document's edges, not the triangulation's", () {
    // **The check the whole mode rests on.** A cube is six quads: twelve
    // edges as a model, eighteen as triangles, because fanning each quad adds
    // a diagonal. Mutation: build the wire from `MeshData.indices` — the
    // triangles the renderer draws — and this says 18. That is a picture of
    // the triangulator, and an agent told "this object has n-gons" would be
    // looking at a mesh that appears to have none.
    final cube = EditMesh.cuboid(size: Vector3(2, 2, 2));
    expect(polygonEdgesOf(cube), hasLength(12));

    // Six triangles a wire — three sides, two triangles each — so the mesh
    // is exactly as big as the edge count says and nothing is silently
    // dropped.
    final wire = wireMeshFor(cube)!;
    expect(wire.indexCount ~/ 3, 12 * 6);
  });

  test('a mesh with nothing in it draws no wires', () {
    // Null and not an empty mesh: `DeviceMesh.upload` of an empty mesh is a
    // draw call that renders nothing, and a caller deciding whether to hang a
    // node is better served by being told there is no node to hang.
    expect(wireMeshFor(EditMesh.empty()), isNull);
  });

  test('wireframe changes the picture, and the wires land on it', () async {
    final cube = EditMesh.cuboid(size: Vector3(2, 2, 2));
    final project = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(cube),
        transform: Matrix4.identity(),
      ),
    );

    final material = await _shot(project, RenderShading.material);
    final wires = await _shot(project, RenderShading.wireframe);

    // Most of this difference is the flat pale surface replacing the lit one,
    // which is the mode too and deliberately so: a lit surface shades half
    // the model down to where a near-black wire on it is one
    // indistinguishable dark shape.
    expect(
      _differingFraction(material, wires),
      greaterThan(0.2),
      reason: 'the wireframe has to be a different picture, visibly',
    );
    // And the wires themselves. The darkest pixel in the frame is a wire, and
    // it has to be far darker than anything a pale flat surface produces on
    // its own. Mutation: leave the restyle and drop the wire nodes, and this
    // is the check that goes red while the one above stays green.
    expect(
      _darkest(wires),
      lessThan(60),
      reason: 'a near-black wire has to actually land on the frame',
    );
  });

  test('an imported mesh gets the flat surface and no wires', () async {
    // The honest gap, said as a check: `ImportedGeometry` has no half-edge
    // topology behind it, so there are no polygons to read and no wires to
    // draw. It must still render — a project with one imported object and
    // `wireframe` asked for is not an error, it is a picture without wires.
    //
    // Counted on the scene rather than measured on the frame, and the first
    // attempt at this is why: the darkest pixel in a picture of one small
    // object is the background behind it, so a pixel check answered 16 for
    // both and would have passed whatever was hung on the node.
    final edited = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'cube',
        geometry: EditedGeometry(EditMesh.cuboid(size: Vector3(2, 2, 2))),
        transform: Matrix4.identity(),
      ),
    );
    final imported = const ModelProject().added(
      (int id) => ModelObject(
        id: id,
        name: 'imported',
        geometry: ImportedGeometry(CuboidShape(size: Vector3(2, 2, 2)).build()),
        transform: Matrix4.identity(),
      ),
    );

    expect(_meshCount(edited, wires: false), 1);
    expect(
      _meshCount(edited, wires: true),
      2,
      reason: 'an editable mesh gets its own wires hung under it',
    );
    expect(_meshCount(imported, wires: false), 1);
    expect(
      _meshCount(imported, wires: true),
      1,
      reason: 'no topology, no wires',
    );

    // And it still draws, which is the other half of "not an error".
    final wireframe = await _shot(imported, RenderShading.wireframe);
    expect(wireframe.width, 256);
  });
}

/// How many meshes [project] puts in a scene, with and without wires.
int _meshCount(ModelProject project, {required bool wires}) =>
    sceneFromProject(project, _cpuDevice(8, 8), wires: wires).meshes.length;

Future<Rgba8Image> _shot(ModelProject project, RenderShading shading) async {
  final png = await renderProject(
    RenderRequest(project: project, width: 256, height: 256, shading: shading),
    deviceFactory: _cpuDevice,
  );
  return (await decodeImagePure(png))!;
}

/// The darkest green channel in the frame — green because every colour in
/// these pictures is a grey or a near-black, and one channel ranks them.
int _darkest(Rgba8Image image) {
  var darkest = 255;
  for (var i = 1; i < image.pixels.length; i += 4) {
    if (image.pixels[i] < darkest) darkest = image.pixels[i];
  }
  return darkest;
}

/// The share of pixels where [a] and [b] differ by more than a rounding —
/// the same eight-level tolerance the normals check above uses.
double _differingFraction(Rgba8Image a, Rgba8Image b) {
  var differing = 0;
  for (var i = 0; i < a.pixels.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      if ((a.pixels[i + c] - b.pixels[i + c]).abs() > 8) {
        differing++;
        break;
      }
    }
  }
  return differing / (a.width * a.height);
}
