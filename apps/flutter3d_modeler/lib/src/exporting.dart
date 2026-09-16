/// Taking the document out to a format somebody else reads.
///
/// **An export is allowed to lose what the target cannot hold; a save is not.**
/// That is the whole difference between this file and `writeProject`. A project
/// file keeps the parameters a cylinder still knows itself by, the hierarchy and
/// the history; an OBJ keeps triangles and a colour, and a glTF keeps most of
/// the rest. So this asks `ExportReadiness` first and puts what will be lost in
/// front of the person, rather than deciding for them.
///
/// **Nothing here writes a file.** It builds bytes and hands back what to call
/// them, so a test can ask what an export of a project contains without a disk,
/// a picker or a sandbox — the same bargain `element_picking.dart` struck for
/// clicks. The widget's half is one `saveAs` per file.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// What the model can be taken out as: the writers this application offers
/// out of `flutter3d_formats`' own list.
///
/// **A choice of writers, not a second list of formats.** The shape of the
/// work is `document → writer → files`, and the writer — its suffix, its
/// sentence, how many files it makes — is `flutter3d_formats`' own
/// [ModelWriter]; what is decided here is only which of them this menu shows.
///
/// **And it shows all of them** (`ux-18`). This listed three of the six
/// `builtInModelWriters` carries, so STL and USDZ were written, tested and
/// unreachable from the application that ships them. `exporting_test.dart`
/// holds the two lists against each other both ways round, the same way
/// `flutter3d_model_mcp`'s own tool table is held against its command names:
/// a writer added there without a member here is a failing test rather than
/// a format nobody can pick.
enum ExportFormat {
  /// The engine's own container: every surface, material, image, node and
  /// animation this repository knows how to write.
  f3d(F3dModelWriter()),

  /// Wavefront OBJ with its `.mtl` beside it. The oldest thing every tool
  /// reads, and the least it can carry: triangles, a placement baked into
  /// them, and a Phong approximation of each material.
  obj(ObjModelWriter()),

  /// A self-contained glTF binary — `fmt-06`'s own `GltfWriter`, the format
  /// most of the rest of the world actually opens. Everything OBJ cannot
  /// carry survives this one: the node tree, materials with textures,
  /// skins and animation.
  glb(GlbModelWriter()),

  /// Binary STL: triangles and nothing else — no colour, no hierarchy, no
  /// names. What a printer and most CAD tools want, and `ux-18`'s own
  /// reason for being here: the writer has existed since `fmt-09` and this
  /// menu did not offer it, so the one format a person with a 3D printer
  /// came for was the one they could not choose.
  stl(StlModelWriter()),

  /// The same triangles as text. Larger by several times and readable in an
  /// editor, which is occasionally exactly what somebody needs.
  stlAscii(StlModelWriter(ascii: true)),

  /// USDZ, for Quick Look on an Apple device — geometry only so far, which
  /// is what the writer's own sentence says and what this menu repeats.
  usdz(UsdzModelWriter());

  const ExportFormat(this.writer);

  final ModelWriter writer;

  String get suffix => writer.suffix;

  /// What a picker calls this one — `ux-18`.
  ///
  /// **Two of these share a [suffix].** Binary and ASCII STL both write a
  /// `.stl` file, so a menu built on the suffix alone offers `.stl` twice and
  /// asks a person to choose between two identical buttons. Everything else
  /// is its own extension, which is the name people already use for it.
  String get label => this == stlAscii ? '.stl (text)' : suffix;

  /// One line for a menu, in the words a person recognises.
  String get says => writer.says;
}

/// How a texture's pixels are written — mat-30's own row: "an encoder …, an
/// option de export; в glTF PNG."
///
/// **Only `.f3d` ever reads this.** `GltfWriter` and `ObjWriter` always keep
/// [png]: glTF's own ecosystem compatibility is the reason the plan names for
/// staying PNG there (`KHR_texture_basisu` exists for KTX2 in glTF, but
/// nothing here writes that extension, and OBJ's `map_Kd` cannot name a
/// compressed format at all — see `ktx2_texture_export_test.dart`). `.f3d` is
/// this engine's own container with its own loader, so it is the one place a
/// choice made here does not have to satisfy anybody else's reader.
enum TextureEncoding {
  /// What every writer already did before this option existed.
  png,

  /// BC3 for a texture with any translucent texel, BC1 otherwise — the same
  /// per-image choice `fmt-22`'s own encoders were built and PSNR-verified
  /// against — written into a KTX2 container via `writeKtx2`.
  ///
  /// **sRGB vs. linear is not distinguished.** A base-colour or emissive
  /// texture is gamma-encoded and a normal or metallic-roughness map is not,
  /// and a real pipeline picks `_SRGB` or `_UNORM` `vkFormat` accordingly —
  /// which binding(s) use a given image is a fact this function does not
  /// have (an image is shared by index, not tagged with a colour space), so
  /// every image here writes as the `_UNORM` variant. Named rather than
  /// guessed at: the bytes still decode to the same channel values a real
  /// GPU would sample, only without the sampler's own automatic gamma
  /// decode a `_SRGB` format would have asked for.
  ktx2,
}

/// One file an export produced.
final class ExportFile {
  const ExportFile(this.name, this.bytes);

  /// The name to offer the save panel, suffix and all.
  final String name;

  final Uint8List bytes;

  @override
  String toString() => 'ExportFile($name, ${bytes.length} bytes)';
}

/// What asking to export gave back.
///
/// **Three cases rather than bytes-or-null**, because the third one is the
/// point. A project that will not export cleanly is neither a success nor a
/// failure: it is a question for the person, and the compiler asking about all
/// three is what stops a caller writing a file that quietly lost an object.
sealed class ExportResult {
  const ExportResult();
}

/// The bytes, and what was lost on the way.
final class ExportWritten extends ExportResult {
  const ExportWritten(this.files, this.warnings);

  /// One for `.f3d`, two for OBJ — the `.obj` and its `.mtl`. In the order they
  /// should be written, the file that names the other first.
  final List<ExportFile> files;

  /// What the target could not hold, in sentences. Empty is the ordinary case.
  final List<String> warnings;
}

/// Nothing to write, and why.
final class ExportRefused extends ExportResult {
  const ExportRefused(this.because);

  final String because;

  @override
  String toString() => 'ExportRefused($because)';
}

/// It would write, and something in it will not load.
///
/// The caller shows [issues] and asks; `planExport(force: true)` writes anyway.
/// A refusal that could not be overridden would be this file deciding what
/// somebody's model is for.
final class ExportBlocked extends ExportResult {
  const ExportBlocked(this.issues);

  /// The errors from `ExportReadiness`, worst first. Warnings are not here —
  /// they ride along with [ExportWritten] and stop nothing.
  final List<ExportIssue> issues;

  /// The question, in one line.
  String get says =>
      '${issues.length == 1 ? 'One thing' : '${issues.length} things'} in this '
      'model will not load where it is going. Export anyway?';
}

/// [project] with every object's own node transform baked into its geometry,
/// where that is possible — `ui-17`'s own "bake node transforms" checkbox.
///
/// **Reuses `ApplyTransform` rather than a second transform-baking
/// implementation.** That command already does exactly this for one object
/// at a time — moves the vertices, flips normals on a mirroring determinant,
/// resets the node to identity — and a copy of it here would be a second
/// place that math could drift from the first. Called against a project a
/// caller is about to throw away for something exported instead, never
/// against the live, undoable one.
///
/// **Not every object can be baked, and this does not stop for the ones that
/// cannot.** `ApplyTransform` refuses a parametric shape, an imported mesh
/// and a socket — each for its own reason, all already explained on
/// `ApplyTransform` itself — and an object already at the identity leaves
/// nothing to bake. Every one of those keeps its own node transform exactly
/// as it was; only the objects `ApplyTransform` actually accepts end up with
/// an identity matrix on the other side.
ModelProject bakeAllTransforms(ModelProject project) {
  var next = project;
  for (final ModelObject object in project.objects) {
    final outcome = ApplyTransform(
      object.id,
    ).apply(next, ProjectSelection.none);
    if (outcome.ok) next = outcome.project!;
  }
  return next;
}

/// [project] as files, or the reason it is not.
///
/// [force] carries a person's answer to [ExportBlocked] back in. It skips the
/// error gate and nothing else: the warnings still come back with the bytes,
/// because "I know" is an answer to a question and not a reason to stop asking.
///
/// [bakeTransforms] runs [bakeAllTransforms] first, so the readiness check
/// and the writer both see the baked project — a transform that collapses a
/// shell of positive volume into one of zero should be caught before export,
/// not discovered by whoever opens the file next.
///
/// [textureEncoding] chooses how a texture's bytes are written — see
/// [TextureEncoding]'s own doc comment for why only [ExportFormat.f3d]
/// listens to it.
ExportResult planExport(
  ModelProject project, {
  required ExportFormat format,
  String name = 'model',
  bool force = false,
  bool bakeTransforms = false,
  TextureEncoding textureEncoding = TextureEncoding.png,

  /// Write only these objects and whatever hangs under them — `ux-18`.
  ///
  /// **A prop out of a scene, without deleting the scene.** The review found
  /// people exporting a whole room to get one chair out of it, then undoing
  /// the deletions they had made to do it. Empty (the default) writes
  /// everything, which is what Export has always meant.
  ///
  /// Children come with their parents, because a node whose parent is not in
  /// the file has nowhere to hang: an export of "the chair" that dropped the
  /// chair's own legs would be a worse answer than refusing.
  Set<int> only = const <int>{},

  /// Whether the modifier stacks are folded into the geometry that is
  /// written — `ux-18`.
  ///
  /// **On, because that is what the file has always carried** since `ux-13`
  /// gave `toModelDocument` its own evaluator: a mirror a person can see is a
  /// mirror the export writes. Off writes the base mesh instead, which is
  /// what somebody taking a model into a tool that has its own mirror wants,
  /// and what nothing here could ask for before.
  bool applyModifiers = true,
}) {
  if (only.isNotEmpty) project = _narrowedTo(project, only);
  if (!applyModifiers) project = _withoutModifiers(project);
  if (bakeTransforms) project = bakeAllTransforms(project);
  // An empty project is refused rather than written, and this is the one place
  // that differs from `ObjWriter`, which writes an empty file on purpose and
  // says why. The difference is the caller: a format has to represent nothing,
  // and a person pressing Export on an empty document has made a mistake.
  if (project.objects.isEmpty) {
    return const ExportRefused('There is nothing in this project to export.');
  }

  // Triangles either way, because both writers write triangles: `ObjWriter`
  // bakes each surface's `MeshData`, which `toModelDocument` has already cut.
  // OBJ *the format* holds an n-gon and this writer does not, so warning about
  // quads is honest for both targets rather than a glTF rule leaking.
  final readiness = ExportReadiness.check(project);
  if (!force && !readiness.canExport) {
    return ExportBlocked(<ExportIssue>[
      for (final ExportIssue issue in readiness.issues)
        if (issue.severity == ExportSeverity.error) issue,
    ]);
  }

  final warnings = <String>[
    for (final ExportIssue issue in readiness.issues) issue.message,
  ];

  final ModelDocument document = toModelDocument(project);
  // The converter's own complaints — a parent that is not there, a transform
  // that is not a translate, rotate and scale. They belong beside readiness
  // rather than under it: readiness is about the model, these are about the
  // trip.
  warnings.addAll(document.warnings);

  // Only `.f3d` has a reader of its own that takes a compressed texture; see
  // [TextureEncoding].
  final ModelDocument encoded =
      format == ExportFormat.f3d && textureEncoding == TextureEncoding.ktx2
      ? _withKtx2Textures(document)
      : document;
  final ModelWrite written = format.writer.write(encoded, baseName: name);

  // Said once, here, rather than per object: OBJ has no node tree at all, so a
  // hierarchy does not survive it and every child comes back at the place its
  // parent put it. Somebody exporting a rig to OBJ should hear that before they
  // open it somewhere else and find it flat.
  const flattened =
      'OBJ has no node tree, so the hierarchy is baked into the vertices: '
      'the model looks right and comes back as one level of objects.';
  // `gal-05`: what the document owes, beside what it is. Only when it owes
  // something — a project built from this application's own models and
  // from CC0 owes nobody anything, and an empty credits file beside it
  // would suggest otherwise.
  final String? credits = creditsFile(project, documentName: name);
  return ExportWritten(
    <ExportFile>[
      for (final WrittenFile each in written.files)
        ExportFile(each.name, each.bytes),
      if (credits != null)
        ExportFile('CREDITS.txt', Uint8List.fromList(utf8.encode(credits))),
    ],
    <String>[
      ...warnings,
      if (format == ExportFormat.obj &&
          project.objects.any((ModelObject o) => o.parent != null))
        flattened,
    ],
  );
}

/// [project] with every modifier stack emptied — `ux-18`'s own "apply
/// modifiers", switched off.
///
/// **The stacks are dropped for the trip, not from the document.** This is a
/// copy handed to the writer; the project a person is editing keeps every
/// modifier it had, which is the difference between an export option and an
/// edit.
ModelProject _withoutModifiers(ModelProject project) => ModelProject(
  profile: project.profile,
  objects: <ModelObject>[
    for (final ModelObject each in project.objects)
      each.modifiers.isEmpty
          ? each
          : each.copyWith(modifiers: const <ModifierSlot>[]),
  ],
  materials: project.materials,
  images: project.images,
  nextId: project.nextId,
  skeletons: project.skeletons,
  clips: project.clips,
  lighting: project.lighting,
);

/// [project] with nothing in it but [keep] and everything hanging under
/// them — `ux-18`'s own "selection only".
///
/// **Parents are kept too, not only children.** An object whose own parent is
/// left out would come back at the origin rather than where it sits, because
/// its transform is local to a parent the file no longer has. Keeping the
/// chain up to the root costs a few empty nodes and keeps every placement
/// true.
ModelProject _narrowedTo(ModelProject project, Set<int> keep) {
  final wanted = <int>{};
  void keepUp(int id) {
    var at = project[id];
    var guard = 0;
    while (at != null && wanted.add(at.id) && guard++ < 1000) {
      at = at.parent == null ? null : project[at.parent!];
    }
  }

  void keepDown(int id) {
    wanted.add(id);
    for (final ModelObject each in project.objects) {
      if (each.parent == id) keepDown(each.id);
    }
  }

  for (final int id in keep) {
    keepUp(id);
    keepDown(id);
  }
  // `copyWith` does not take an object list — deliberately, since every
  // ordinary edit goes through a command — so this builds the narrowed
  // project directly. Materials, images, skeletons, clips and the lighting
  // come across whole: an object kept here still indexes into all of them.
  return ModelProject(
    profile: project.profile,
    objects: <ModelObject>[
      for (final ModelObject each in project.objects)
        if (wanted.contains(each.id)) each,
    ],
    materials: project.materials,
    images: project.images,
    nextId: project.nextId,
    skeletons: project.skeletons,
    clips: project.clips,
    lighting: project.lighting,
  );
}

/// [document] with every image [_encodeAsKtx2] can decode replaced by its
/// KTX2 encoding — everything else (surfaces, materials, the node tree,
/// skins, animation) is the exact same instance [document] already had.
///
/// A wrapper rather than a copy through `PlainModelDocument`: that class'
/// own `roots` is `ModelDocument`'s default — every node its own root, the
/// fallback a format with no real hierarchy (OBJ) reads — and this
/// document's actual `roots` came from `toModelDocument`'s real walk of the
/// project. Copying through `PlainModelDocument` would silently flatten
/// every parent/child edge in the file this writes; forwarding every getter
/// but [images] cannot.
ModelDocument _withKtx2Textures(ModelDocument document) =>
    _ImagesOverride(document, <EncodedImage>[
      for (final EncodedImage image in document.images) _encodeAsKtx2(image),
    ]);

final class _ImagesOverride extends ModelDocument {
  const _ImagesOverride(this._inner, this.images);

  final ModelDocument _inner;

  @override
  final List<EncodedImage> images;

  @override
  List<ModelSurface> get surfaces => _inner.surfaces;

  @override
  List<SurfaceMaterial> get materials => _inner.materials;

  @override
  DocumentAsset? get asset => _inner.asset;

  @override
  List<ModelNode> get nodes => _inner.nodes;

  @override
  List<int> get roots => _inner.roots;

  @override
  List<AnimationClip> get animations => _inner.animations;

  @override
  List<ModelSkin> get skins => _inner.skins;

  @override
  List<ModelLight> get lights => _inner.lights;

  @override
  List<ModelCamera> get cameras => _inner.cameras;

  @override
  List<String> get warnings => _inner.warnings;
}

/// [image] re-encoded as KTX2 (BC3 for any translucent texel, BC1
/// otherwise) — or [image] itself, unchanged, when neither of
/// `flutter3d_model_core`'s own [decodePng]/[decodeJpeg] can make sense of
/// its bytes (an already-KTX2 image from a previous export, or a format
/// this pipeline does not decode at all, such as `.webp`).
///
/// **`flutter3d_model_core`'s own decoders, not a new dependency.**
/// `flutter3d_formats` cannot decode a PNG itself — `png_encoder_test.dart`
/// and this same file's own earlier survey found no pure-Dart image decoder
/// in its `lib/`, only a writer — but `mat-09n` already built one one layer
/// up, in `flutter3d_model_core`, for the texture graph's own bake
/// (`mat-11`) to read a painted layer's pixels with. This app already
/// depends on that package, so reusing it here costs nothing a new
/// dependency on `package:image` would have, and keeps one PNG decoder in
/// this repository rather than two.
///
/// **Padded to whole 4×4 blocks, not cropped.** Every encoder in
/// `flutter3d_formats`'s `encode/` refuses a partial block; a crop would
/// lose the texture's own edge pixels, so a source whose size is not a
/// multiple of four is padded by replicating its last row and column, and
/// the KTX2 header still declares the *original* width and height — a
/// texture upload reads exactly that many texels and never looks at the
/// padding, the same way a GPU's own compressed-texture upload path treats
/// a non-block-sized mip.
EncodedImage _encodeAsKtx2(EncodedImage image) {
  final decoded = decodePng(image.bytes) ?? decodeJpeg(image.bytes);
  if (decoded == null) return image;

  final width = decoded.width;
  final height = decoded.height;
  final paddedWidth = (width + 3) & ~3;
  final paddedHeight = (height + 3) & ~3;

  final pixels = Uint8List(paddedWidth * paddedHeight * 4);
  var hasAlpha = false;
  for (var y = 0; y < paddedHeight; y++) {
    final sy = y < height ? y : height - 1;
    for (var x = 0; x < paddedWidth; x++) {
      final sx = x < width ? x : width - 1;
      final srcAt = (sy * width + sx) * 4;
      final dstAt = (y * paddedWidth + x) * 4;
      pixels[dstAt] = decoded.rgba[srcAt];
      pixels[dstAt + 1] = decoded.rgba[srcAt + 1];
      pixels[dstAt + 2] = decoded.rgba[srcAt + 2];
      final a = decoded.rgba[srcAt + 3];
      pixels[dstAt + 3] = a;
      if (a != 255) hasAlpha = true;
    }
  }
  final source = Rgba8Image(
    width: paddedWidth,
    height: paddedHeight,
    pixels: pixels,
  );

  final Uint8List blockBytes;
  final int vkFormat;
  if (hasAlpha) {
    blockBytes = encodeBc3(source);
    vkFormat = VkFormat.bc3UNormBlock;
  } else {
    blockBytes = encodeBc1(source);
    vkFormat = VkFormat.bc1RgbaUNormBlock;
  }

  final ktx2Bytes = writeKtx2(
    vkFormat: vkFormat,
    pixelWidth: width,
    pixelHeight: height,
    levels: <Uint8List>[blockBytes],
  );

  return EncodedImage(
    bytes: ktx2Bytes,
    name: image.name,
    mimeType: 'image/ktx2',
    sourceUri: image.sourceUri,
  );
}
