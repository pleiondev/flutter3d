/// The `.f3d` container: constants shared by the writer and the reader.
///
/// ## Why a format at all
///
/// The measurement in `ARCHITECTURE.md` §14 is the whole argument. A GLB of the
/// teapot's complexity loads in 14.8 us; the same geometry as OBJ takes 5.39 ms,
/// a factor of about 360. That gap is not the language — it is the work. OBJ is
/// text, so every number is parsed, every face is split, every vertex triple is
/// hashed and deduplicated. GLB already holds the buffers the GPU wants, and
/// loading it is mostly pointing at them.
///
/// `.f3d` takes that to its conclusion: an offline converter does the decoding
/// once, and the runtime does almost nothing. Vertex and index arrays are stored
/// exactly as `MeshData` holds them, so the loader hands out typed-data **views
/// over the file bytes** rather than copies. Nothing is decoded per load.
///
/// ## Layout
///
/// Everything is little-endian, stated rather than inherited: the host happens
/// to be little-endian today, and a format that silently depends on that breaks
/// the first time an asset is built on one machine and read on another.
///
/// ```
/// Header, 16 bytes
///   u32 magic          'F3D\n'
///   u32 version
///   u32 sectionCount
///   u32 entryBytes     0 in version 1 (read as 16); 20 or more from version 2
///
/// Section directory, sectionCount x entryBytes
///   u32 kind           see [F3dSection]; [f3dVendorKindStart] and up are
///                      anybody's
///   u32 offset         from the start of the file
///   u32 length         in bytes
///   u32 count          in elements, for the fixed-record tables
///   u32 flags          version 2 and up, see [F3dSectionFlags]; version 1
///                      entries read as 0
/// ```
///
/// A directory rather than a fixed set of header fields, because it makes the
/// format extensible in the only way that matters: a reader skips a kind it does
/// not know, so a later version can add a section without breaking an older
/// loader. [f3dVersion] then only has to change when an existing record's
/// meaning changes.
///
/// Tables hold fixed-size records so an index is an offset multiplication rather
/// than a walk. Everything variable-length — strings, vertex and index arrays,
/// image bytes, keyframe data — lives in the blob and is referenced by
/// `(offset, length)`.
///
/// ## How the format grows
///
/// Four ways, and only the last one needs a new version:
///
/// * **A new section.** An older reader skips a kind it does not know. When
///   skipping it would open a *different* model rather than a poorer one, the
///   writer sets [F3dSectionFlags.mustUnderstand] on it, and a reader that
///   does not know the kind refuses the file, naming it.
/// * **A longer record.** From version 2 a table's stride is its section's
///   `length ~/ count`, not the record size this build knows, so a later
///   writer may append fields to the tail of a record and an older reader
///   reads the head it knows and steps over the rest. A version-1 file is read
///   at the record sizes in [F3dRecord], as it always was.
/// * **A section of somebody else's.** Kinds from [f3dVendorKindStart] up are
///   never the engine's: a tool may store its own data there, and
///   `F3dDocument.parse(understands:)` and `F3dDocument.section` read it back.
/// * **A changed meaning.** A record whose existing fields change meaning bumps
///   [f3dVersion]; the reader branches on the version for that record alone,
///   and a fixture minted at the new version goes under `test/fixtures/v<N>/`.
///
/// ## The bundle
///
/// A `.f3d` is one file for a whole asset, not only its geometry. Beside the
/// model's own tables it may carry:
///
/// * **lights and cameras** ([F3dSection.lights], [F3dSection.cameras]) and
///   the nodes that carry them ([F3dSection.nodeAttachments]), read back as
///   `ModelDocument.lights`, `ModelDocument.cameras`, `ModelNode.lightIndex`
///   and `ModelNode.cameraIndex`. Intensities are photometric, as
///   `docs/CONTRACTS.md` says: lux for a directional light, candela for a
///   point or spot one;
/// * **each material's lighting model** ([F3dSection.materialLighting]), in
///   the JSON `.fmat` writes, read back as `RenderMaterial.lightingModel`;
/// * **material language programs** ([F3dSection.programs]): `.f3dmat`
///   sources by name, `F3dDocument.programs`. A material is drawn with one
///   when its lighting model's shader names it; a reader without the section
///   draws the material's base parameters;
/// * **prefabs** ([F3dSection.prefabs]): level documents in the format
///   envelope (`"format": "f3d.level"`), by name, `F3dDocument.prefabs`. This
///   package does not read levels; `flutter3d_sim`'s `Level.fromJson` does.
///   A prefab names this file's nodes by name and places this file by its
///   own path;
/// * **files carried whole** ([F3dSection.files]), by path,
///   `F3dDocument.files`: the models, `.fmat` materials and textures a prefab
///   names when the bundle was made from a scene rather than one model.
///
/// `F3dWriter` writes the first two from the document and the last three
/// from its `programs`, `prefabs` and `files`. Every one is optional and
/// none is must-understand: a reader that skips one opens a poorer asset
/// (no lights, base parameters instead of a program, no prefab), never a
/// different one, so they arrived without a version bump and a file without
/// them is the bytes it always was. They live in the registry as the same
/// format, `f3d.model`.
///
/// **The 0.8 readers.** They open only version 1 and skip kinds they do not
/// know. So the writer stays at version 1 unless a section carries a flag:
/// a bundle with lights, programs, prefabs and files, or an unflagged tool
/// section, is still a version-1 file that a 0.8 game opens and draws as
/// its geometry. The records of the 0.8 sections keep their sizes and
/// meanings, and only new sections are added. `f3d_fixture_test.dart` walks
/// a bundle the way the 0.8.5 loader does.
///
/// **Files past 4 GiB** will be the wide variant, [f3dWideMagic]: the same
/// layout with u64 offsets and lengths in the directory and the blob's
/// records. Reserved now so the magic is never taken for anything else; this
/// build refuses a wide file by name rather than misreading it. It will come
/// in a minor release as a variant both readers open, not as a version bump
/// of this one.
///
/// ## Alignment
///
/// Every blob entry starts at a 4-byte boundary. That is not tidiness: a
/// `Float32List.view` throws unless its byte offset is a multiple of four, and
/// the whole point of the format is to build those views without copying.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException, FormatSpec;

/// `F3D\n`, chosen so a file opened in a text editor announces itself on line
/// one and the trailing newline stops the magic from running into what follows.
const int f3dMagic = 0x0A443346;

/// The newest version this build reads: bumped when an existing record
/// changes meaning. Adding a section does not need it — an old reader skips
/// what it does not recognise.
///
/// **Version 2 is the flags word in the directory** (see [F3dSectionFlags])
/// and the record stride taken from each section. `F3dWriter` writes version
/// 1 unless a section needs flags, so a converted asset that uses nothing new
/// keeps the bytes it had.
const int f3dVersion = 2;

/// `.f3d` in the format registry: its id, suffix, magic, the version this
/// build reads up to, and the fixture minted at each version.
const FormatSpec f3dFormat = FormatSpec(
  id: 'f3d.model',
  version: f3dVersion,
  suffixes: <String>['.f3d'],
  fixture: 'test/fixtures/v<N>/box.f3d',
  enveloped: false,
  magic: <int>[0x46, 0x33, 0x44, 0x0A],
);

/// The magic of the wide variant, `F3DW`: u64 offsets for files past 4 GiB.
/// Reserved; see "How the format grows" in this library's documentation.
const int f3dWideMagic = 0x57443346;

/// The first section kind that is never the engine's. Kinds from here up are
/// free for tools and plugins; the engine skips them unless asked to read one.
const int f3dVendorKindStart = 0x80000000;

const int f3dHeaderBytes = 16;

/// A version-1 directory entry: kind, offset, length, count.
const int f3dSectionEntryBytes = 16;

/// A version-2 directory entry: a version-1 entry and its flags word. The
/// header's fourth word says the size a file uses, so a later version may
/// grow the entry the same way a record grows.
const int f3dSectionEntryBytesV2 = 20;

/// The bits of a directory entry's flags word (version 2 and up).
abstract final class F3dSectionFlags {
  /// A reader that does not know this section's kind must refuse the file:
  /// skipping it would open a different model, not a poorer one.
  static const int mustUnderstand = 1 << 0;
}

/// Section kinds.
///
/// Explicit values, never the enum index: the value is written into a file that
/// outlives the source, and reordering the enum would silently reinterpret every
/// asset already on disk.
abstract final class F3dSection {
  static const int layouts = 1;
  static const int attributes = 2;
  static const int meshes = 3;
  static const int surfaces = 4;
  static const int materials = 5;
  static const int images = 6;
  static const int nodes = 7;
  static const int roots = 8;
  static const int animations = 9;
  static const int tracks = 10;
  static const int warnings = 11;
  static const int strings = 12;
  static const int blob = 13;
  static const int skins = 14;

  /// The shapes a mesh can be blended towards, each naming the mesh it belongs
  /// to. A section of its own rather than fields on the mesh record, so that a
  /// build that predates morph targets skips it and reads the same file as a
  /// model that draws its base shape — which is exactly what the directory is
  /// for, and cheaper than a version bump that invalidates every asset on disk.
  static const int morphTargets = 15;

  /// The rest weights of a surface's targets, for the few surfaces that have
  /// any. Separate from the surface record for the same reason: that record is
  /// a fixed 84 bytes and every existing file is written to it.
  static const int morphWeights = 16;

  /// Which of a surface's vertex attributes the source file actually
  /// declared, one record per surface in [surfaces] order — see
  /// `ModelSurface.authoredAttributes` and [F3dAttributeFlags]. Absent in a
  /// file written before `fmt-03`, which is read as every attribute the
  /// surface's own mesh layout has, the same "unwritten means all of it"
  /// shape [morphTargets] uses for a section added after the format shipped.
  static const int surfaceAttributes = 17;

  /// The mesh asset name behind each surface, one record per surface in
  /// [surfaces] order — see `ModelSurface.meshName`. Absent reads as null for
  /// every surface, the same as a file that predates `fmt-04`.
  static const int meshNames = 18;

  /// What the source file said about itself — `count` 0 or 1, never more.
  /// See `ModelDocument.asset`.
  static const int asset = 19;

  /// Where each image's bytes came from, one record per image in [images]
  /// order — see `EncodedImage.sourceUri`.
  static const int imageUris = 20;

  /// Sparse, one record per `ModelLod` across every node that has any, not
  /// one per node — the same shape [morphTargets] already holds for
  /// surfaces, and for the same reason: nearly every node has none, and a
  /// record naming its own node index costs less than a table of zeros in
  /// every file that never uses the feature. See `ModelNode.lods`.
  static const int lods = 21;

  /// One record per material variant — `ModelDocument.variants` — carrying
  /// its name and, in the blob, the `(surface, material)` pairs that choose
  /// it. Per variant rather than per surface because that is how many there
  /// are: a handful of looks, against a surface table nearly every row of
  /// which takes part in none. See `ModelSurface.variantMaterials`.
  static const int variants = 23;

  /// `KHR_animation_pointer` tracks, one record each, kept out of [tracks]
  /// on purpose: a reader before this section checks a track's path against
  /// the paths it knows and refuses the file on one it does not. Here, an
  /// older build skips the section and plays the same clips without their
  /// material and light tracks, which is the whole of what it cannot do.
  static const int pointerTracks = 24;

  /// The impostor level a node falls to last — `C4`, `ModelLod.impostor`.
  /// Sparse like [lods], one record per node that has one; a reader without
  /// it sees the surface levels alone and draws the coarsest mesh as far as
  /// the eye goes, which is the right thing for a build that cannot draw the
  /// card.
  static const int impostors = 25;

  /// The layers beyond metal-rough a material carries — `M1`, see
  /// `MaterialExtensions`. Sparse, one record per material that has any, each
  /// naming its material, for the reason [lods] is: nearly every material has
  /// none, and the 132-byte material record is what every existing file is
  /// written to.
  static const int materialExtensions = 22;

  /// The cluster runs of a mesh the splitter cut up — `C9`, see
  /// `MeshData.clusters`. Sparse, one record per mesh that has any, and
  /// written only when one does. The triangles are already in cluster order
  /// in the mesh's own index array, so a reader without this section loads
  /// the same mesh and draws all of it every frame.
  static const int clusters = 26;

  /// How far each surface level strays from its node's full mesh —
  /// `ModelLod.error`. One record per record of [lods], in the same order,
  /// and written only when some level was measured. A section of its own
  /// rather than a wider [lods] record, because every file with levels is
  /// written to the 16-byte one: a reader that predates this skips it and
  /// switches by the screen fraction alone, and a file without it reads as
  /// every level unmeasured.
  static const int lodErrors = 27;

  /// Every `extras` block the document carries, each a JSON string with
  /// the kind and the index of what it belongs to — see
  /// [F3dRecord.extras] and [F3dExtrasOwner]. A clip's markers and a
  /// model's animation graphs live there. Written only when there is one,
  /// so a file with none is the bytes it was; a reader that predates it
  /// skips it and loses the blocks, as it always had.
  static const int extras = 28;

  // ------------------------------------------------- the bundle (1.0.0-rc.1)
  //
  // What makes a `.f3d` one file for a whole asset rather than the model
  // alone. None is must-understand: a reader that skips one opens a poorer
  // model (no lights, the base parameters instead of a program, no prefab),
  // never a different one.

  /// `KHR_lights_punctual` lights, one record each — `ModelDocument.lights`.
  /// Intensity as the contract has it (`docs/CONTRACTS.md`): lux for a
  /// directional light, candela for a point or spot one.
  static const int lights = 29;

  /// Cameras, one record each — `ModelDocument.cameras`.
  static const int cameras = 30;

  /// Which node carries which light and camera — `ModelNode.lightIndex` and
  /// `ModelNode.cameraIndex`. Sparse, one record per node that has either.
  static const int nodeAttachments = 31;

  /// A material's lighting model — `RenderMaterial.lightingModel` — as the
  /// JSON `.fmat` writes under `lightingModel`. Sparse, one record per
  /// material that names one. A model naming a program of [programs] is how
  /// a material is drawn with it; a reader without the section draws the
  /// material's base parameters.
  static const int materialLighting = 32;

  /// RenderMaterial language (`.f3dmat`) sources, by name — `F3dDocument.programs`.
  static const int programs = 33;

  /// Level and prefab documents, each a JSON object in the format envelope
  /// (`"format": "f3d.level"`), by name — `F3dDocument.prefabs`.
  static const int prefabs = 34;

  /// Files carried whole, by path — `F3dDocument.files`: the models,
  /// `.fmat` materials and textures a prefab names when the bundle was made
  /// from a scene rather than from one model.
  static const int files = 35;

  /// Every kind above, the ones this build reads. A must-understand section
  /// of any other kind is refused unless the caller understands it.
  static const Set<int> known = <int>{
    layouts,
    attributes,
    meshes,
    surfaces,
    materials,
    images,
    nodes,
    roots,
    animations,
    tracks,
    warnings,
    strings,
    blob,
    skins,
    morphTargets,
    morphWeights,
    surfaceAttributes,
    meshNames,
    asset,
    imageUris,
    lods,
    materialExtensions,
    variants,
    pointerTracks,
    impostors,
    clusters,
    lodErrors,
    extras,
    lights,
    cameras,
    nodeAttachments,
    materialLighting,
    programs,
    prefabs,
    files,
  };
}

/// Whose an [F3dSection.extras] record is.
abstract final class F3dExtrasOwner {
  /// The root document's own, `DocumentAsset.extras`; its index is 0.
  static const int document = 0;
  static const int node = 1;
  static const int material = 2;
  static const int skin = 3;
  static const int animation = 4;
}

/// Fixed record sizes, in bytes. All multiples of four.
abstract final class F3dRecord {
  /// u32 attributeCount, u32 firstAttribute
  static const int layout = 8;

  /// u32 owner (an [F3dExtrasOwner]), u32 index, u32 jsonOffset,
  /// u32 jsonLength — the JSON in the strings section.
  static const int extras = 16;

  /// u32 nameOffset, u32 nameLength, u32 componentCount
  static const int attribute = 12;

  /// u32 layoutIndex, u32 vertexOffset, u32 vertexBytes, u32 indexOffset,
  /// u32 indexBytes, u32 vertexCount
  static const int mesh = 24;

  /// u32 meshIndex, i32 materialIndex, u32 nameOffset, u32 nameLength,
  /// u32 flags, f32`16` transform
  ///
  /// `flags` is bit 0 for flipWinding and the rest for the skin index plus one,
  /// so zero means "no skin".
  static const int surface = 84;

  /// See the writer; 132 bytes of scalars plus five texture bindings.
  static const int material = 132;

  /// u32 dataOffset, u32 dataLength, u32 nameOffset, u32 nameLength,
  /// u32 mimeOffset, u32 mimeLength
  static const int image = 24;

  /// u32 nameOffset, u32 nameLength, f32`3` translation, f32`4` rotation,
  /// f32`3` scale, u32 childOffset, u32 childCount, u32 surfaceOffset,
  /// u32 surfaceCount
  static const int node = 64;

  /// u32 nameOffset, u32 nameLength, u32 firstTrack, u32 trackCount
  static const int animation = 16;

  /// u32 nodeIndex, u32 path, u32 interpolation, u32 componentCount,
  /// u32 timesOffset, u32 timesCount, u32 valuesOffset, u32 valuesCount
  static const int track = 32;

  /// u32 offset, u32 length into the strings section
  static const int warning = 8;

  /// u32 nameOffset, u32 nameLength, u32 pairOffset, u32 pairCount — the
  /// pairs are i32 surfaceIndex, i32 materialIndex in the blob.
  static const int variant = 16;

  /// u32 animationIndex, u32 trackPosition, u32 interpolation,
  /// u32 componentCount, u32 timesOffset, u32 timesCount, u32 valuesOffset,
  /// u32 valuesCount, u32 pointerOffset, u32 pointerLength
  ///
  /// `trackPosition` is the track's index in its clip, so a clip mixing node
  /// and pointer tracks reads back in the order it was written. The pointer
  /// is the JSON pointer string, resolved again at load — the same place a
  /// glTF file's is.
  static const int pointerTrack = 40;

  /// u32 nameOffset, u32 nameLength, u32 jointOffset, u32 jointCount,
  /// u32 matrixOffset, i32 skeletonRoot
  static const int skin = 24;

  /// One texture binding inside a material: i32 imageIndex, u32 texCoordSet,
  /// u32 samplingFlags
  static const int textureBinding = 12;

  /// u32 meshIndex, u32 nameOffset, u32 nameLength, u32 vertexCount,
  /// u32 positionOffset, u32 normalOffset, u32 tangentOffset, u32 flags
  ///
  /// Each stream is `vertexCount * 3` floats, so only the offsets are stored;
  /// `flags` says which of the two optional ones are there, because a blob
  /// offset of zero is a real offset and cannot double as "absent".
  static const int morphTarget = 32;

  /// u32 surfaceIndex, u32 valuesOffset, u32 valuesCount
  static const int morphWeights = 12;

  /// u32 bitmask, see [F3dAttributeFlags]
  static const int surfaceAttributes = 4;

  /// u32 nameOffset, u32 nameLength into the strings section
  static const int meshName = 8;

  /// u32 generatorOffset, u32 generatorLength into the strings section
  static const int asset = 8;

  /// u32 uriOffset, u32 uriLength into the strings section
  static const int imageUri = 8;

  /// u32 nodeIndex, f32 maxScreenFraction, u32 surfaceOffset, u32
  /// surfaceCount
  static const int lod = 16;

  /// f32 error, in the node's own units; negative for a level nobody
  /// measured, since a real distance never is.
  static const int lodError = 4;

  /// u32 nodeIndex, f32 maxScreenFraction, u32 albedoImage, u32
  /// normalDepthImage, u32 grid, f32 centre x, y, z, f32 radius
  static const int impostor = 36;

  /// u32 materialIndex, u32 jsonOffset, u32 jsonLength into the strings
  /// section.
  ///
  /// **The layers as glTF's own extension JSON, not as fixed fields.** They
  /// are a handful of numbers per material that has any, read once at load,
  /// and the list of them grows with every `KHR_materials_*` the renderer
  /// learns; a fixed record would change size with each, where JSON keeps
  /// one record that an older reader reads what it knows of. A texture is
  /// `{"image": i, "texCoord": n, "sampling": flags}`, the flags those of
  /// [F3dSamplingFlags].
  static const int materialExtensions = 12;

  /// u32 meshIndex, u32 clusterCount, u32 firstIndicesOffset, u32
  /// dataOffset — `clusterCount + 1` u32 run starts and `clusterCount * 11`
  /// f32 of boxes and cones in the blob, exactly as `MeshClusters` holds them.
  static const int clusters = 16;

  /// u32 type (0 directional, 1 point, 2 spot), f32`3` colour (linear),
  /// f32 intensity (lux or candela), f32 range, f32 innerConeAngle, f32
  /// outerConeAngle (radians), u32 nameOffset, u32 nameLength, u32 flags (bit
  /// 0: a range is set)
  static const int light = 44;

  /// u32 projection (0 perspective, 1 orthographic), f32`4` (perspective:
  /// yfov, aspectRatio, znear, zfar; orthographic: xmag, ymag, znear, zfar),
  /// u32 flags (bit 0: aspectRatio set, bit 1: zfar set), u32 nameOffset,
  /// u32 nameLength
  static const int camera = 32;

  /// u32 nodeIndex, i32 lightIndex, i32 cameraIndex (-1 for none)
  static const int nodeAttachment = 12;

  /// u32 materialIndex, u32 jsonOffset, u32 jsonLength into the strings
  /// section
  static const int materialLighting = 12;

  /// u32 nameOffset, u32 nameLength, u32 textOffset, u32 textLength, all
  /// into the strings section: a program's name and source, a prefab's name
  /// and JSON.
  static const int namedText = 16;

  /// u32 pathOffset, u32 pathLength into the strings section, u32
  /// dataOffset, u32 dataLength into the blob
  static const int file = 16;
}

/// Bit positions inside a `surfaceAttributes` record — one per name
/// `VertexLayout`'s own attributes use.
abstract final class F3dAttributeFlags {
  static const int position = 1 << 0;
  static const int normal = 1 << 1;
  static const int texcoord = 1 << 2;
  static const int tangent = 1 << 3;
  static const int color = 1 << 4;
  static const int joints = 1 << 5;
  static const int weights = 1 << 6;
}

/// Which optional streams a morph target record carries.
abstract final class F3dMorphFlags {
  static const int hasNormals = 1 << 0;
  static const int hasTangents = 1 << 1;
}

/// Bit positions inside a texture binding's `samplingFlags`.
///
/// Packed rather than one field each because the whole of [TextureSampling] fits
/// in eight bits, and a material carries five of these.
abstract final class F3dSamplingFlags {
  static const int magLinear = 1 << 0;
  static const int minLinear = 1 << 1;
  static const int useMipmaps = 1 << 2;

  /// Two bits each, holding a `TextureWrap` code (`f3d_wire.dart`).
  static const int wrapSShift = 3;
  static const int wrapTShift = 5;
  static const int wrapMask = 0x3;

  /// Set when the mip level is chosen by nearest rather than interpolated
  /// (`TextureSampling.mipLinear == false`). Bit 7 because bits 3-6 are
  /// already spoken for by the two wrap fields.
  ///
  /// Stored inverted — presence means "not linear" — so that a file written
  /// before this flag existed, which leaves the bit unset, decodes to
  /// `mipLinear: true`, matching [TextureSampling]'s own default and what
  /// every reader before this flag assumed a mipmapped sampler meant.
  static const int mipNearest = 1 << 7;
}

/// Raised when a file is not a `.f3d`, is truncated, or claims a version this
/// build does not understand.
///
/// A distinct type rather than [FormatException] so a caller can tell "this is
/// not our format" from "this is our format and it is broken", and rebuild the
/// asset in the second case.
final class F3dFormatException extends Flutter3dFormatException {
  const F3dFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'F3dFormatException: $message';
}
