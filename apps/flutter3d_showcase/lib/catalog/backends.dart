/// The pages of the `backends` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> backendsFeatures = <Feature>[
  Feature(
    id: 'backend-impeller',
    title: 'Impeller',
    category: Category.backends,
    summary:
        'The desktop and mobile path: flutter_gpu through Impeller, read by '
        'its capabilities rather than by its name.',
    since: '0.1.0',
    evidence:
        '`flutter3d_hardware` over `flutter_gpu`: the backend a desktop '
        'build draws through',
    evidenceFile: 'packages/flutter3d_impeller/CHANGELOG.md',
    packages: <String>['flutter3d_impeller'],
    engineFiles: <String>['packages/flutter3d_app/lib/src/backend_native.dart'],
  ),
  Feature(
    id: 'backend-webgl',
    title: 'WebGL2',
    category: Category.backends,
    summary:
        'The browser path this engine draws through by default, read by its '
        'capabilities rather than by its name.',
    since: '0.1.0',
    evidence:
        'A WebGL2 backend: the second implementation of `flutter3d_hardware`',
    evidenceFile: 'packages/flutter3d_webgl/CHANGELOG.md',
    packages: <String>['flutter3d_webgl'],
    engineFiles: <String>['packages/flutter3d_app/lib/src/backend_web.dart'],
  ),
  Feature(
    id: 'backend-webgpu',
    title: 'WebGPU',
    category: Category.backends,
    summary:
        'The fourth backend, tried before WebGL2 only when a web build asks '
        'for it by name at compile time.',
    since: '0.6.0',
    evidence:
        'It opens a real WebGPU device, records passes through it, and '
        'hands Flutter a frame',
    evidenceFile: 'packages/flutter3d_webgpu/CHANGELOG.md',
    packages: <String>['flutter3d_webgpu'],
    engineFiles: <String>['packages/flutter3d_app/lib/src/backend_web.dart'],
  ),
  Feature(
    id: 'backend-cpu',
    title: 'The software rasteriser',
    category: Category.backends,
    summary:
        'A device with no GPU behind it: what the golden pictures are drawn '
        'with, and every page in this showcase besides.',
    since: '0.2.0',
    evidence: '`flutter3d_hardware` rasterised in Dart with no GPU under it',
    evidenceFile: 'packages/flutter3d_cpu/CHANGELOG.md',
    packages: <String>['flutter3d_cpu'],
    engineFiles: <String>['packages/flutter3d_cpu/lib/src/cpu_device.dart'],
  ),
  Feature(
    id: 'backend-matrix',
    title: 'What differs between them',
    category: Category.backends,
    summary:
        'A live table of what the device open right now can do, read from '
        'GraphicsDevice.supports* rather than from a name.',
    since: '0.2.0',
    evidence: 'capability questions a backend answers rather than guesses at',
    evidenceFile: 'packages/flutter3d_hardware/CHANGELOG.md',
    packages: <String>['flutter3d_hardware'],
    engineFiles: <String>[
      'packages/flutter3d_hardware/lib/src/graphics_device.dart',
    ],
  ),
];
