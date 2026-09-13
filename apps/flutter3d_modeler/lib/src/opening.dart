/// What opening a model file leaves behind.
///
/// **One function returning both halves, because the bug this replaced was the
/// two halves disagreeing.** Opening used to instantiate the decoded model into
/// a scene and, separately, start a fresh project holding a cube. Both lines
/// were correct on their own and the application they made was not: the model
/// was on the screen and the document described something else, so the outliner
/// listed a cube, a click selected nothing that was drawn, undo had no edits to
/// take back and the export readiness measured a shape nobody could see.
///
/// The repair is not a comment saying to keep them in step. It is that there is
/// no way to get one without the other: [openDocument] builds the project and
/// builds the stage *from that project*, and hands back the pair. A caller that
/// wants a scene has already got the document it draws.
///
/// **What kind of file it is is decided here rather than in the widget**, and
/// by the bytes rather than by the name. A person picks one file out of a
/// folder and it is either a saved project or a model to import; branching on
/// the extension would open a project renamed `.glb` as a broken model, and
/// would hand a `.f3dproj` that is really a glTF to the wrong reader. Both
/// roads end in the same pair, so nothing above this has to know which was
/// taken.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'staging.dart';

/// What a chosen file turned out to be.
///
/// **A sealed pair rather than an exception, for the reason `ProjectRead`
/// gives**: opening a file somebody picked is not exceptional, it is a normal
/// Tuesday, and half the files in any folder are the wrong file. The sentence
/// belongs on the status line rather than in a stack trace, and the compiler
/// asking about both cases is what stops a caller drawing an empty scene while
/// holding the reason it could not.
sealed class FileOpened {
  const FileOpened();
}

/// A model that has been opened: the document a person now edits, and the
/// scene that draws it.
final class OpenedModel extends FileOpened {
  const OpenedModel(this.project, this.stage);

  /// The objects the file became. What the outliner lists, what a click
  /// selects, what undo takes back and what an export writes.
  final ModelProject project;

  /// The scene built from [project], with a node per object.
  final ModelerStage stage;

  /// What could not be decoded on the way, in sentences. A texture that would
  /// not read is a model that opens in flat colour, which looks exactly like a
  /// model authored in flat colour — so it is said rather than swallowed.
  List<String> get warnings => stage.materials?.warnings ?? const <String>[];
}

/// The file, and one sentence saying what is wrong with it.
final class OpenRefused extends FileOpened {
  const OpenRefused(this.because);

  final String because;

  @override
  String toString() => 'OpenRefused($because)';
}

/// [bytes] as whatever they are: a saved project, or a model to import.
///
/// [name] is only ever used in a sentence — what decides is
/// [isProjectFile], which reads the first four bytes.
///
/// A project that will not read comes back as [OpenRefused] carrying
/// `readProject`'s own sentence, which names the number that did not add up. A
/// model that will not decode comes back the same way, because a decoder throws
/// and a person who picked a JPEG should be told so rather than shown a stack
/// trace.
Future<FileOpened> openBytes(
  Uint8List bytes, {
  required String name,
  required GraphicsDevice device,
}) async {
  if (isProjectFile(bytes)) {
    return switch (readProject(bytes)) {
      ProjectOpened(:final ModelProject project) => await openProject(
        project,
        device: device,
      ),
      ProjectRefused(:final String because) => OpenRefused(because),
    };
  }

  final ModelDocument document;
  try {
    document = await decodeBytes(bytes, name);
  } catch (error) {
    return OpenRefused('$name could not be read: $error');
  }
  final empty = emptyDecodeRefusal(document, name);
  if (empty != null) return OpenRefused(empty);
  return openDocument(document, device: device);
}

/// [bytes] decoded as a model — `ui-16`'s own lower half of [openBytes],
/// pulled out so an import screen can decode a file, ask a person about
/// units/axis/cleanup, and only then call [openDocument] with the
/// [ImportOptions] they chose, instead of always getting the defaults
/// [openBytes] itself commits to.
Future<ModelDocument> decodeBytes(Uint8List bytes, String name) =>
    decodeModel(ModelLoadRequest(source: _Bytes(name, bytes)));

/// **A decode that succeeded and found nothing is a refusal, not an empty
/// document.** The OBJ reader takes any text at all and answers with a
/// document of no surfaces and no nodes, so a photograph or a log file opens
/// without complaint — and opening replaces what the person was working on.
/// Trading the empty scene nobody authors for the wrong file everybody
/// eventually picks is the right way round. Null when [document] is worth
/// showing.
String? emptyDecodeRefusal(ModelDocument document, String name) {
  if (document.surfaces.isNotEmpty || document.nodes.isNotEmpty) return null;
  return 'There is nothing in $name that this build can read: no meshes and '
      'no nodes came out of it.';
}

/// Whether [name] paired with [bytes] is even worth handing to [openBytes] —
/// `ui-31n`'s own guard on a dropped file.
///
/// **A picker never has to ask this.** `openModel`'s own file dialogue only
/// ever offers the extensions it was built with, so `_openFile` hands
/// whatever comes back straight to [openBytes]. A drop can carry anything the
/// desktop or the browser lets somebody drag onto the window, and for a name
/// [recognizedModelFormat] does not know, [openBytes] would fall back to
/// [sniffModelFormat] — which is right for a `.glb` a person renamed and wrong
/// for a `.dae` or a spreadsheet, both of which would otherwise be read as
/// whichever format the first few bytes happen to resemble.
/// [recognizedModelFormat]'s own doc comment names this exact caller.
///
/// Null when the file is worth opening; a sentence for the status line
/// otherwise. [isProjectFile] is asked first, since a saved project's own
/// extension is whatever a person renamed it to, and is never in
/// [recognizedModelFormat]'s list.
String? unopenableDropRefusal(String name, Uint8List bytes) {
  if (isProjectFile(bytes)) return null;
  if (recognizedModelFormat(name) != null) return null;
  return '$name: not a file type this build can open';
}

/// A model whose bytes are already in memory.
///
/// Both halves of `ProjectFiles` hand over bytes rather than a path — a browser
/// has no path at all — and the decoders take an `AssetSource`, so this is the
/// adapter between them. Sibling files are refused rather than guessed: a
/// `.gltf` with an external `.bin` is a case `ui-16` handles by asking for both
/// files, and answering it wrongly here would look like a corrupt model.
final class _Bytes extends AssetSource {
  const _Bytes(this._name, this._bytes);

  final String _name;
  final Uint8List _bytes;

  @override
  String get key => 'memory:$_name';

  @override
  Future<Uint8List> read() async => _bytes;

  @override
  AssetUriResolver get resolveUri => (AssetRequest request) async {
    // A `.gltf` that carries its buffers inline addresses them as data URIs,
    // and those need nothing but this file. A relative path does need a
    // sibling, which is `ui-16`'s question — asked rather than guessed at,
    // because a wrong guess reads as a corrupt model.
    if (request.uri.startsWith('data:')) return decodeDataUri(request.uri);
    throw StateError(
      'this model refers to "${request.uri}", and only the file itself was '
      'opened',
    );
  };
}

/// [document] as a project, and a stage drawing that project.
///
/// The framing is left to the caller: where the camera goes when a file opens
/// is a viewport decision, and the measurement stands open documents without
/// wanting one.
///
/// **The paint arrives a moment after the shape, and on purpose.** Building a
/// material means decoding the images it samples, which a frame cannot wait
/// for. So the stage is made and drawn first — every object in clay — and the
/// pool is filled after; `repaint` then puts the materials on without touching
/// a vertex buffer. Doing it the other way round would hold the first frame of
/// every opened file for as long as its textures take to decode.
Future<OpenedModel> openDocument(
  ModelDocument document, {
  required GraphicsDevice device,
  ImportOptions options = const ImportOptions(),
}) => openProject(fromModelDocument(document, options: options), device: device);

/// [project] and a stage drawing it, with the materials on.
///
/// The door a saved project comes through, and the second half of the one an
/// imported model comes through. Shared rather than written twice, because
/// what "drawn with its materials" means is a thing that has to stay the same
/// for both: a project that opens painted from a file and unpainted from an
/// import would be two answers to one question.
Future<OpenedModel> openProject(
  ModelProject project, {
  required GraphicsDevice device,
}) async {
  final stage = ModelerStage.fromProject(device: device, project: project);

  await stage.materials?.refresh(project);
  stage.sync?.repaint(project);

  return OpenedModel(project, stage);
}
