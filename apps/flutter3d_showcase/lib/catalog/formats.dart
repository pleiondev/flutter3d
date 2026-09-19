/// The pages of the `formats` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> formatsFeatures = <Feature>[
  Feature(
    id: 'gltf-load',
    title: 'glTF and GLB',
    category: Category.formats,
    summary:
        'The format most tools export to, read down to meshes and '
        'materials this engine can draw.',
    since: '0.1.0',
    evidence:
        'glTF 2.0 / GLB and Wavefront OBJ behind one document abstraction, '
        'plus `.f3d`, the engine\'s own container',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/gltf/gltf_loader.dart',
      'packages/flutter3d_core/lib/src/formats/gltf/gltf_asset.dart',
    ],
  ),
  Feature(
    id: 'gltf-cameras-lights',
    title: 'Cameras and lights from a file',
    category: Category.formats,
    summary:
        'A camera and a punctual light, held on a document the same way a '
        'mesh is, written into a GLB and read back.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        'lights through `KHR_lights_punctual`, cameras, `extras` on five '
        'kinds of object',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/model_camera.dart',
      'packages/flutter3d_core/lib/src/formats/model_light.dart',
    ],
  ),
  Feature(
    id: 'gltf-write',
    title: 'Writing GLB',
    category: Category.formats,
    summary:
        'Any decoded document, written out as a self-contained GLB, '
        'optionally quantized and reordered for a smaller file.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        '`GltfWriter` writes a self-contained GLB: geometry, materials and '
        'samplers, skins, animation channels in all three interpolations, '
        'morph targets with their names, lights through '
        '`KHR_lights_punctual`, cameras, `extras` on five kinds of object',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/gltf/gltf_writer.dart',
    ],
  ),
  Feature(
    id: 'export-validate',
    title: 'Export, read back, compare',
    category: Category.formats,
    summary:
        'Write a document, read the file back, and report what a real '
        'round trip changed or could not carry.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        '`exportToGlb`, `exportToObj`, `exportToStl` and `exportToF3d` '
        'answer an `ExportReport` with the files, the warnings and the '
        'differences `compareModelDocuments` found on reading the file '
        'back, morph targets included. `validateGltfExport` checks each '
        "accessor's declared bounds against its data",
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/export_report.dart',
      'packages/flutter3d_core/lib/src/formats/document_compare.dart',
      'packages/flutter3d_core/lib/src/formats/gltf/gltf_validate.dart',
    ],
  ),
  Feature(
    id: 'obj',
    title: 'OBJ and MTL',
    category: Category.formats,
    summary:
        'Plain-text geometry, older than glTF, with normals filled in '
        'when the file leaves them out.',
    since: '0.1.0',
    evidence:
        'glTF 2.0 / GLB and Wavefront OBJ behind one document abstraction, '
        'plus `.f3d`, the engine\'s own container',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/obj/obj_loader.dart',
      'packages/flutter3d_core/lib/src/formats/obj/obj_writer.dart',
    ],
  ),
  Feature(
    id: 'stl',
    title: 'STL',
    category: Category.formats,
    summary:
        'A flat triangle soup with no shared vertices, told apart from '
        'ASCII by the file\'s own size arithmetic.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        '`StlLoader` reads both dialects and tells them apart by the '
        "file's own size arithmetic, since a binary header often begins "
        'with `solid`',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/stl/stl_loader.dart',
      'packages/flutter3d_core/lib/src/formats/stl/stl_writer.dart',
    ],
  ),
  Feature(
    id: 'usdz',
    title: 'USDZ export',
    category: Category.formats,
    summary:
        'Geometry written into the ZIP archive Quick Look opens, one '
        'Mesh prim a surface, no materials yet.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        '`UsdzWriter` writes geometry only, one `Mesh` prim per surface, '
        'in an archive macOS identifies as USDZ',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/usdz/usdz_writer.dart',
      'packages/flutter3d_core/lib/src/formats/usdz/usdz_zip.dart',
    ],
  ),
  Feature(
    id: 'f3d',
    title: 'The .f3d container',
    category: Category.formats,
    summary:
        "The engine's own container, converted offline so loading it is "
        'almost no work at all.',
    since: '0.1.0',
    evidence:
        'glTF 2.0 / GLB and Wavefront OBJ behind one document abstraction, '
        'plus `.f3d`, the engine\'s own container',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/f3d/f3d_loader.dart',
      'packages/flutter3d_core/lib/src/formats/f3d/f3d_writer.dart',
      'packages/flutter3d_core/lib/src/formats/f3d/f3d_format.dart',
    ],
  ),
  Feature(
    id: 'ktx2',
    title: 'KTX2 and Basis textures',
    category: Category.formats,
    summary:
        'A compressed-texture container, including Basis Universal '
        'files transcoded to plain RGBA8 at load time.',
    since: '0.4.2',
    evidence: 'KTX2 is read.',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/ktx2/ktx2_loader.dart',
      'packages/flutter3d_core/lib/src/formats/ktx2/basis_universal/etc1s_transcoder.dart',
    ],
  ),
  Feature(
    id: 'texture-compression',
    title: 'Compressing a texture',
    category: Category.formats,
    summary:
        'Four block encoders, a mip chain, and a KTX2 container to write '
        'the result into.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        '`encodeBc1`, `encodeBc3`, `encodeEtc2Rgb8` and `encodeAstc4x4` '
        'encode, `buildMipChain` halves with a box filter, and `writeKtx2` '
        'writes the container',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/ktx2/encode/bc1_encoder.dart',
      'packages/flutter3d_core/lib/src/formats/ktx2/encode/mip_chain.dart',
      'packages/flutter3d_core/lib/src/formats/ktx2/encode/ktx2_writer.dart',
    ],
  ),
  Feature(
    id: 'draco',
    title: 'Draco meshes',
    category: Category.formats,
    summary:
        'A compressed mesh format read all the way, both connectivity '
        'methods and every prediction scheme a current encoder writes.',
    since: '0.7.0',
    evidenceFile: 'packages/flutter3d_core/CHANGELOG.md',
    evidence:
        '`decodeDraco` now reads edgebreaker connectivity, which is what '
        'every encoder writes unless told otherwise',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/draco/draco_decoder.dart',
    ],
  ),
];
