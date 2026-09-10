/// A mesh as bytes, and back.
///
/// **Byte for byte is the assertion, not "looks the same".** A format that
/// writes a different file for the same document is a format nobody can diff,
/// nobody can cache by hash and nobody can tell apart from a change. So the
/// round trip is compared as bytes, and the mesh that comes out is written
/// again and compared with what went in.
library;

import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

/// A cube carrying something in every layer there is.
EditMesh loaded() {
  final mesh = EditMesh.cuboid();
  edit(mesh, () {
    for (var face = 0; face < mesh.faceSlotCount; face++) {
      mesh
        ..setMaterialSlot(face, face % 3)
        ..setFaceFlag(face, FaceFlags.smooth, on: face.isEven);
      var corner = 0;
      mesh.forEachHalfEdge(face, (int half) {
        final at = corner++;
        mesh
          ..setUv(half, Vector2(at / 4, face / 6))
          ..setColour(half, Vector4(0.1 * at, 0.2, 0.3, 1))
          ..setCrease(half, 0.25 * at)
          ..setEdgeFlag(half, EdgeFlags.sharp, on: at == 0)
          ..setEdgeFlag(half, EdgeFlags.seam, on: at == 1);
      });
    }
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
      mesh.setSkin(
        vertex,
        VertexAttributes(
          joints: Vector4(vertex.toDouble(), 1, 2, 3),
          weights: Vector4(0.4, 0.3, 0.2, 0.1),
        ),
      );
    }
  });
  return mesh;
}

/// [bytes] with a section nothing knows about spliced in after the header.
Uint8List withAStrangeSection(Uint8List bytes) {
  const payload = <int>[9, 9, 9, 9, 9];
  final padded = (payload.length + 3) & ~3;
  final out = Uint8List(bytes.length + 8 + padded);
  out.setRange(0, 8, bytes);
  out.setRange(8, 12, 'ZZZZ'.codeUnits);
  ByteData.sublistView(out).setUint32(12, payload.length, Endian.little);
  out.setRange(16, 16 + payload.length, payload);
  out.setRange(16 + padded, out.length, bytes, 8);
  return out;
}

void main() {
  group('a round trip', () {
    test('a bare cube comes back the same, byte for byte', () {
      final mesh = EditMesh.cuboid();
      final bytes = mesh.toBytes();

      final back = EditMesh.fromBytes(bytes);

      expect(back.vertexCount, 8);
      expect(back.faceCount, 6);
      expect(back.eulerCharacteristic, 2);
      expect(back.signedVolume, closeTo(1, 1e-6));
      back.validate();
      // Mutation: write the arrays at their allocated length rather than at the
      // slot count, and a mesh that has grown once writes the tail of a
      // doubled array into the file — different bytes for the same document.
      expect(back.toBytes(), bytes);
    });

    test('every layer survives, and the second writing matches the first', () {
      final mesh = loaded();
      final bytes = mesh.toBytes();

      final back = EditMesh.fromBytes(bytes);

      expect(back.toBytes(), bytes);
      expect(back.materialSlotOf(2), 2);
      expect(back.faceHas(4, FaceFlags.smooth), isTrue);
      expect(back.faceHas(3, FaceFlags.smooth), isFalse);

      final half = back.halfEdgeOf(1);
      expect(back.uvOf(half).y, closeTo(1 / 6, 1e-6));
      expect(back.colourOf(half).y, closeTo(0.2, 1e-6));
      expect(back.creaseOf(half), closeTo(0, 1e-6));
      expect(back.edgeHas(half, EdgeFlags.sharp), isTrue);
      expect(back.skinOf(5).joints.x, closeTo(5, 1e-6));
      // Mutation: leave a layer out of the writing, and a document loses every
      // material assignment it had the first time somebody saves it.
      expect(back.hasLayer(MeshDomain.edge, MeshAttribute.crease), isTrue);
    });

    test('a mesh that has been edited comes back edited', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () {
        extrudeFaces(
          mesh,
          Selection.of(ElementLevel.face, <int>[0]),
          distance: 0.5,
        );
      });
      edit(mesh, () => mesh.deleteFace(3));

      final back = EditMesh.fromBytes(mesh.toBytes());

      // The tombstones travel too: a face somebody deleted stays deleted, and
      // the numbers on either side of it stay where they were.
      expect(back.faceSlotCount, mesh.faceSlotCount);
      expect(back.faceCount, mesh.faceCount);
      expect(back.vertexCount, mesh.vertexCount);
      expect(back.isFaceAlive(3), isFalse);
      back.validate();
    });

    test('what comes back has no history to undo into', () {
      final mesh = EditMesh.cuboid();
      edit(mesh, () => mesh.moveVertex(0, Vector3(9, 9, 9)));
      expect(mesh.undoDepth, 1);

      final back = EditMesh.fromBytes(mesh.toBytes());

      // Saving is a boundary the undo stack does not cross, which is the plan's
      // answer and the same one `compact` gives.
      expect(back.undoDepth, 0);
      expect(back.undo(), isFalse);
      expect(back.positionOf(0).x, closeTo(9, 1e-6));
    });
  });

  group('sections', () {
    test('one nothing knows about is stepped over', () {
      final mesh = loaded();
      final bytes = mesh.toBytes();

      final back = EditMesh.fromBytes(withAStrangeSection(bytes));

      // Mutation: step over a section by the length it declares without
      // rounding up to the boundary, and the reader lands three bytes inside
      // the next tag — every section after it is nonsense, and the failure is
      // a `RangeError` from a length read out of the middle of a float.
      expect(back.toBytes(), bytes);
      expect(back.faceCount, 6);
      back.validate();
    });

    test('bytes that are not a mesh are refused with a sentence', () {
      // The sentence matters as much as the refusal: a `RangeError` from
      // somewhere inside is also an `ArgumentError` in Dart, so a test that
      // only asks for the type cannot tell "this is not a mesh" apart from
      // "this is a mesh and I read off the end of it". Mutation: drop the
      // check on the first four bytes, and eight bytes of nonsense are read as
      // a version from the future instead.
      expect(
        () => EditMesh.fromBytes(Uint8List.fromList('NOPE????'.codeUnits)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError it) => it.message.toString(),
            'message',
            contains('first four bytes'),
          ),
        ),
      );
      expect(
        () => EditMesh.fromBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a version from the future is refused rather than guessed at', () {
      final bytes = EditMesh.cuboid().toBytes();
      ByteData.sublistView(bytes).setUint32(4, 99, Endian.little);

      // Mutation: read it anyway, and a file whose topology section changed
      // shape loads as a mesh whose links point anywhere.
      expect(
        () => EditMesh.fromBytes(bytes),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError it) => it.message,
            'message',
            contains('version 99'),
          ),
        ),
      );
    });

    test('a section that runs off the end is refused', () {
      final bytes = EditMesh.cuboid().toBytes();
      ByteData.sublistView(bytes).setUint32(12, 0xFFFF, Endian.little);

      // Mutation: read it anyway, and what comes out is a `RangeError` from
      // the middle of a decode — which is an `ArgumentError` too, so the type
      // says nothing and only the sentence does.
      expect(
        () => EditMesh.fromBytes(bytes),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError it) => it.message.toString(),
            'message',
            contains('ends before'),
          ),
        ),
      );
    });

    test('a topology section that is missing is refused', () {
      final bytes = EditMesh.cuboid().toBytes();
      // Rename the origins section, so it is read as one nothing knows about.
      final data = ByteData.sublistView(bytes);
      var at = 8;
      while (String.fromCharCodes(bytes, at, at + 4) != 'ORIG') {
        at += 8 + ((data.getUint32(at + 4, Endian.little) + 3) & ~3);
      }
      bytes.setRange(at, at + 4, 'XXXX'.codeUnits);

      expect(
        () => EditMesh.fromBytes(bytes),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError it) => it.message,
            'message',
            contains('ORIG'),
          ),
        ),
      );
    });
  });

  group('what the bytes are', () {
    test('every section starts on a boundary of four', () {
      final bytes = loaded().toBytes();

      var at = 8;
      var sections = 0;
      while (at + 8 <= bytes.length) {
        expect(at % 4, 0, reason: 'section $sections starts at $at');
        final length = ByteData.sublistView(
          bytes,
        ).getUint32(at + 4, Endian.little);
        at += 8 + ((length + 3) & ~3);
        sections++;
      }
      expect(
        at,
        bytes.length,
        reason: 'the last section ends where the file does',
      );
      // Ten for the topology and the sizes, eight layers on top.
      expect(sections, 18);
    });

    test('it starts with four characters somebody can recognise', () {
      expect(String.fromCharCodes(EditMesh.cuboid().toBytes(), 0, 4), 'F3DM');
    });
  });
}
