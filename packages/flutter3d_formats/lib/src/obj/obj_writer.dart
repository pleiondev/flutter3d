import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';

import '../model_document.dart';

/// Encodes any [ModelDocument] as Wavefront OBJ, with its `.mtl` beside it.
///
/// Takes a [ModelDocument] rather than an [ObjDocument], for the reason
/// `F3dWriter` does: the abstraction exists so that one encoder serves every
/// decoder, and a glTF scene exported as OBJ is the case that matters. Nothing
/// here is on a frame path.
///
/// **The dialect is the one `ObjLoader` reads**, not the union of everything
/// the format allows. Every choice below that had more than one defensible
/// answer was settled by asking what the reader beside this file does with it:
/// the V flip, the sticky `usemtl`, the absent `vt`/`vn` records, the inverted
/// Phong approximation in the `.mtl`. That is what makes the round trip the
/// centre of the test file rather than a nice extra.
///
/// **A document with no geometry writes an empty file, and does not refuse.**
/// The refusals in this package are for a *malformed* input — a truncated
/// `.f3d`, a bad magic — and a model with nothing in it is not malformed, it is
/// empty, which OBJ can say exactly: a header and no records. Read back it
/// gives zero surfaces and the loader's own `The file contained no triangles.`,
/// so the observation survives the round trip in the one place that already
/// reports it. Refusing would force every caller through a result type to guard
/// a case the format represents.
final class ObjWriter {
  ObjWriter(
    this.document, {
    this.name = 'model',
    this.decimals = 6,
    this.flipTexcoordV = true,
  });

  final ModelDocument document;

  /// The base name, without a suffix: it names the `.mtl` and appears in the
  /// header comment. It is not written into any record a reader parses, so a
  /// caller that saves under a different filename loses nothing but the
  /// `mtllib` line pointing at the right sibling.
  final String name;

  /// Decimal places for every number written.
  ///
  /// Six. Vertices live in a [Float32List], which carries around seven
  /// significant decimal digits, so sixteen places would spend half the file
  /// spelling out the noise past what the source could represent. Three places
  /// is a millimetre on a metre, which is visible as faceting on anything
  /// hand-modelled at that scale. Six resolves a micrometre on a metre and
  /// still fits inside what the source float actually knew.
  ///
  /// Trailing zeros are trimmed, so an axis-aligned box costs `1` rather than
  /// `1.000000` per coordinate without losing a digit anyone could read back.
  final int decimals;

  /// OBJ puts the texture origin at the bottom left and this engine puts it at
  /// the top left, so `ObjLoader` stores `1 - v` on the way in and this undoes
  /// it on the way out. Both default to true; setting one without the other is
  /// how a model comes back with its textures upside down.
  final bool flipTexcoordV;

  /// The filename the `mtllib` record points at.
  String get materialLibraryName => '$name.mtl';

  /// Encodes the `.obj`. The result is a complete file.
  Uint8List write() {
    final out = StringBuffer()
      ..writeln('# $name.obj')
      ..writeln('# written by flutter3d');
    if (document.materials.isNotEmpty) {
      out.writeln('mtllib $materialLibraryName');
    }

    // **Three counters, not one.** OBJ numbers positions, texture coordinates
    // and normals in three independent 1-based sequences that run for the whole
    // file rather than restarting per object, and a document is free to mix a
    // UV-mapped surface with an unmapped one. Sharing a counter between the
    // three works right up until the first surface that omits an attribute,
    // after which every face in the file addresses the wrong vertex — and a
    // document of one mesh never reaches that point, which is why the test
    // beside this writes three.
    var positionBase = 1;
    var texcoordBase = 1;
    var normalBase = 1;

    String? currentMaterial;
    var wroteAnyMaterial = false;

    for (var i = 0; i < document.surfaces.length; i++) {
      final surface = document.surfaces[i];
      final mesh = _bake(surface);
      // A surface with no triangles would write orphan `v` records that no face
      // addresses, and come back as nothing at all, so the surface count would
      // not survive its own round trip. Skipped whole.
      if (mesh.vertexCount < 0) continue;

      final material = _materialNameOf(surface);
      out
        ..writeln()
        ..writeln('o ${_token(surface.name) ?? 'object_$i'}');

      // `usemtl` is sticky in OBJ, and `ObjLoader` implements that faithfully:
      // an unmaterialled surface following a materialled one would inherit it.
      // So the line is written whenever the material changes, including the
      // change back to none, which a bare `usemtl` says and the reader accepts.
      if (material != currentMaterial) {
        if (material != null) {
          out.writeln('usemtl $material');
          wroteAnyMaterial = true;
        } else if (wroteAnyMaterial) {
          out.writeln('usemtl');
        }
        currentMaterial = material;
      }

      final stride = mesh.layout.floatsPerVertex;
      final texcoordOffset = _usedOffset(mesh, VertexLayout.texcoord);
      final normalOffset = _usedOffset(mesh, VertexLayout.normal);

      /// One face corner, in whichever of the four spellings this mesh
      /// supports: `v`, `v/vt`, `v//vn` or `v/vt/vn`. Never `v//` and never a
      /// trailing empty field — `ObjLoader` resolves an empty component to no
      /// index so those would parse, but plenty of readers reject them and the
      /// record says the same thing without.
      String corner(int vertex) {
        final position = positionBase + vertex;
        if (texcoordOffset < 0 && normalOffset < 0) return '$position';
        if (normalOffset < 0) return '$position/${texcoordBase + vertex}';
        if (texcoordOffset < 0) return '$position//${normalBase + vertex}';
        return '$position/${texcoordBase + vertex}/${normalBase + vertex}';
      }

      for (var v = 0; v < mesh.vertexCount; v++) {
        final o = v * stride;
        out.writeln(
          'v ${_number(mesh.vertices[o])} '
          '${_number(mesh.vertices[o + 1])} '
          '${_number(mesh.vertices[o + 2])}',
        );
      }
      if (texcoordOffset >= 0) {
        for (var v = 0; v < mesh.vertexCount; v++) {
          final o = v * stride + texcoordOffset;
          final t = mesh.vertices[o + 1];
          out.writeln(
            'vt ${_number(mesh.vertices[o])} '
            '${_number(flipTexcoordV ? 1.0 - t : t)}',
          );
        }
      }
      if (normalOffset >= 0) {
        for (var v = 0; v < mesh.vertexCount; v++) {
          final o = v * stride + normalOffset;
          out.writeln(
            'vn ${_number(mesh.vertices[o])} '
            '${_number(mesh.vertices[o + 1])} '
            '${_number(mesh.vertices[o + 2])}',
          );
        }
      }

      // Read off the matrix that was actually baked rather than off
      // `ModelSurface.flipWinding`. The flag tells a *renderer* to invert its
      // front face while the transform stays on the node; here the transform
      // has been folded into the positions, so the stored index order now
      // describes the opposite orientation and the file has to say so.
      final reversed = surface.transform.determinant() < 0.0;

      for (var t = 0; t + 2 < mesh.indices.length; t += 3) {
        final a = mesh.indices[t];
        final b = mesh.indices[t + 1];
        final c = mesh.indices[t + 2];
        out.writeln(
          'f ${corner(reversed ? c : a)} ${corner(b)} '
          '${corner(reversed ? a : c)}',
        );
      }

      positionBase += mesh.vertexCount;
      if (texcoordOffset >= 0) texcoordBase += mesh.vertexCount;
      if (normalOffset >= 0) normalBase += mesh.vertexCount;
    }

    return utf8.encode(out.toString());
  }

  /// Encodes the `.mtl`, or null when the document names no materials.
  ///
  /// Null rather than an empty library because the `.obj` only writes its
  /// `mtllib` line under the same condition: a caller can save whatever this
  /// returns and never write a file the model does not reference.
  ///
  /// **What this writes is the inverse of `ObjLoader`'s approximation.** It
  /// recovers no Phong material that ever existed, and it is not meant to.
  /// `Kd` and `d` come back exactly, because the loader carried them through
  /// untouched, and `Ns` is the exponent that reproduces the roughness the
  /// document holds. `Ks` is the lossy one. Through this reader an OBJ material
  /// can only ever mean two metallic values, so the writer picks the nearer of
  /// them and a metallic of 0.3 comes back as 0.5.
  Uint8List? writeMaterialLibrary() {
    if (document.materials.isEmpty) return null;

    final names = _materialNames;
    final out = StringBuffer()..writeln('# $materialLibraryName');

    for (var i = 0; i < document.materials.length; i++) {
      final material = document.materials[i];
      final specular = material.metallic > 0.25 ? 1.0 : 0.0;
      final exponent = ((1.0 - material.roughness) * 1000.0).clamp(0.0, 1000.0);

      out
        ..writeln()
        ..writeln('newmtl ${names[i]}')
        ..writeln(
          'Kd ${_number(material.baseColor.x)} '
          '${_number(material.baseColor.y)} '
          '${_number(material.baseColor.z)}',
        )
        ..writeln(
          'Ks ${_number(specular)} ${_number(specular)} ${_number(specular)}',
        )
        ..writeln('Ns ${_number(exponent)}')
        ..writeln('d ${_number(material.baseColor.w)}');

      // Only when the image remembers where it came from. A writer that
      // invented `material_0.png` would put a filename in the library that
      // nobody wrote a file for, and the reader would report a missing texture
      // rather than the absent one it actually has.
      final texture = material.baseColorTexture;
      final path = texture == null ? null : _imagePath(texture.imageIndex);
      if (path != null) out.writeln('map_Kd $path');
    }

    return utf8.encode(out.toString());
  }

  // ------------------------------------------------------------------ meshes

  /// The surface's geometry in the model's own space.
  ///
  /// OBJ has no per-object transform and no hierarchy — its `o` records are
  /// siblings, which is exactly what `ModelDocument.nodes` says of them — so a
  /// placement that is not folded into the positions is a placement that is
  /// lost. [MeshData.transformed] carries the normals through the
  /// inverse-transpose, without which non-uniform scale would skew them.
  MeshData _bake(ModelSurface surface) => surface.transform.isIdentity()
      ? surface.mesh
      : surface.mesh.transformed(surface.transform);

  /// The float offset of [attribute], or `-1` when the mesh has it in name only.
  ///
  /// The all-zero test is not tidiness. `ObjLoader` writes a zero normal and a
  /// zero texture coordinate precisely where the file had no `vn` and no `vt`,
  /// so a stream that is zero throughout *is* the absence of one, and writing
  /// it out would turn "this model has no normals" into "every normal on this
  /// model points nowhere" — which the reader would then believe, and skip the
  /// smoothing pass that would have given the model normals.
  int _usedOffset(MeshData mesh, VertexAttribute attribute) {
    final offset = mesh.layout.floatOffsetOf(attribute.name);
    if (offset < 0) return -1;

    final stride = mesh.layout.floatsPerVertex;
    for (var o = offset; o < mesh.vertices.length; o += stride) {
      for (var c = 0; c < attribute.componentCount; c++) {
        if (mesh.vertices[o + c] != 0.0) return offset;
      }
    }
    return -1;
  }

  // --------------------------------------------------------------- materials

  late final List<String> _materialNames = _buildMaterialNames();

  /// Names for `newmtl`, parallel to `document.materials`.
  ///
  /// Made unique, because a `.mtl` library is keyed by name on the way back in:
  /// two materials both called `Material` would collapse to one entry and every
  /// surface using the first would silently draw with the second. Two materials
  /// sharing a name is ordinary in an exported scene, not a corner case.
  List<String> _buildMaterialNames() {
    final taken = <String>{};
    final names = <String>[];

    for (var i = 0; i < document.materials.length; i++) {
      final base = _token(document.materials[i].name) ?? 'material_$i';
      var candidate = base;
      for (var suffix = 2; !taken.add(candidate); suffix++) {
        candidate = '${base}_$suffix';
      }
      names.add(candidate);
    }
    return names;
  }

  String? _materialNameOf(ModelSurface surface) {
    final index = surface.materialIndex;
    if (index == null || index < 0 || index >= document.materials.length) {
      return null;
    }
    return _materialNames[index];
  }

  String? _imagePath(int index) {
    if (index < 0 || index >= document.images.length) return null;
    return _token(document.images[index].name);
  }

  /// A name reduced to something a record can hold.
  ///
  /// A newline in a name would end the record early and turn the rest of the
  /// name into a directive, so runs of whitespace collapse to a single space —
  /// which `usemtl`, `newmtl` and `o` all survive, because the reader joins
  /// their arguments back with one. Null when nothing is left, so the caller
  /// substitutes a generated name rather than writing a bare keyword.
  static String? _token(String? value) {
    if (value == null) return null;
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.isEmpty ? null : collapsed;
  }

  // ----------------------------------------------------------------- numbers

  String _number(double value) {
    if (value == 0.0) return '0'; // and negative zero, which reads as noise.

    final text = value.toStringAsFixed(decimals);
    if (!text.contains('.')) return text;

    var end = text.length;
    while (end > 1 && text.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    if (text.codeUnitAt(end - 1) == 0x2E) end--;
    final trimmed = text.substring(0, end);
    return trimmed == '-0' ? '0' : trimmed;
  }
}
