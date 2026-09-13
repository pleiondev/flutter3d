/// The half of `mat-08` that owns a file system: turning a linked material's
/// own look back into `.fmat` bytes on disk.
///
/// **Disk here, decoding and encoding in core.** `flutter3d_model_core` has
/// no file system of its own — every command in `material_commands.dart`
/// takes bytes already read (`LinkMaterialFile`) or hands bytes back for
/// somebody else to write (nothing yet does, until this) — so this is the
/// seam where a material an editor built in memory actually reaches a file.
/// It mirrors `LinkMaterialFile`'s own split: that command decodes bytes the
/// app already read; this writes bytes the app then puts on disk.
///
/// **Through `mat-03`'s own gate, without a second one.** Every edit that
/// reached [ProjectMaterial.surface] before this is called went through
/// `SetMaterialField` or one of its neighbours — `ProjectMaterial` has no
/// other way to change it — so nothing here re-validates a field a command
/// already checked; the gate is upstream, in the command that produced the
/// material this reads.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// Writes a material's own `.fmat` back to disk.
final class MaterialFileWriter {
  const MaterialFileWriter._();

  /// The exact bytes [write] puts on disk for [material] — exposed on its
  /// own so a caller that wants to preview them, or write them somewhere
  /// [write] does not know about (an export archive, a "save a copy"
  /// dialogue), does not have to touch a file to get them.
  ///
  /// **Only what `writeFmat` already writes for a bare [SurfaceMaterial].**
  /// [ProjectMaterial] carries no shader, no parameters and no hints of its
  /// own — those are a texture graph's business (`mat-10..13`) or a file's
  /// own, read once by [readFmat] and never round-tripped back onto the
  /// project — so a `.fmat` this writes never names a custom shader and
  /// therefore never trips the "shader not found" warning on its own way
  /// back in. Colour, the scalar factors, alpha and the two flags are the
  /// whole of what a project-owned material has to say, and it round-trips
  /// exactly.
  static Uint8List bytesFor(ProjectMaterial material) => Uint8List.fromList(
    utf8.encode(writeFmat(MaterialDocument(surface: material.surface))),
  );

  /// Writes [material]'s own `.fmat` to disk, resolved against [baseDir] —
  /// the directory [ProjectMaterial.fmat]'s own doc comment says a linked
  /// path is relative to, ordinarily the project's own file.
  ///
  /// Throws a [StateError] for a material [LinkMaterialFile] never linked:
  /// `EmbedMaterial` is how a material stops deferring to a file, and
  /// writing one back for a material that never asked for one would create
  /// a file nothing else in the project knows to read. Creates directories
  /// under [baseDir] as needed, the way a freshly linked path — named before
  /// anything wrote to it — is allowed to.
  static Future<void> write(
    ProjectMaterial material, {
    required String baseDir,
  }) async {
    final path = material.fmat;
    if (path == null) {
      throw StateError(
        'this material is not linked to a .fmat file; link one first',
      );
    }
    final file = File.fromUri(Uri.directory(baseDir).resolve(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytesFor(material), flush: true);
  }
}
