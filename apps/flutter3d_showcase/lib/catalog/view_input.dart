/// The pages of the `view_input` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> viewInputFeatures = <Feature>[
  Feature(
    id: 'projections',
    title: 'Perspective and orthographic',
    category: Category.viewInput,
    summary:
        'The two ways a camera turns the world into a flat picture, and the '
        'one number in the matrix that tells them apart.',
    since: '0.5.1',
    evidence:
        "orthographic camera's rays are parallel and meet nowhere, so the "
        'shorter version was right on a perspective camera',
    keywords: <String>['orthographic', 'perspective'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/projection.dart',
    ],
  ),
  Feature(
    id: 'off-axis-projection',
    title: 'Off-axis frustum',
    category: Category.viewInput,
    summary:
        'A frustum whose axis is not down the middle, for a headset lens or '
        'a portal window.',
    since: '0.7.0',
    evidence: 'OffAxisProjection',
    keywords: <String>['offaxisprojection'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/projection.dart',
    ],
  ),
  Feature(
    id: 'tiled-render',
    title: 'Rendering in tiles',
    category: Category.viewInput,
    summary:
        'Drawing a picture larger than any single render target, one square '
        'of it at a time.',
    since: '0.7.0',
    evidence: 'TiledProjection',
    keywords: <String>['tiledprojection'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/projection.dart',
    ],
  ),
  Feature(
    id: 'orbit-controller',
    title: 'Orbit',
    category: Category.viewInput,
    summary:
        'Framing a model automatically and swinging the view to a new angle '
        'instead of jumping to it.',
    since: '0.7.0',
    evidence: 'OrbitController` with an orthographic height and `animateTo',
    keywords: <String>['animateto'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/orbit_controller.dart',
    ],
  ),
  Feature(
    id: 'free-look',
    title: 'Free-look and walking',
    category: Category.viewInput,
    summary:
        'Turning the head from where the camera stands and walking it '
        'there, instead of orbiting a point somebody else chose.',
    since: '0.7.0',
    evidence: 'FreeLook',
    keywords: <String>['freelook'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/free_look.dart',
    ],
  ),
  Feature(
    id: 'raycast',
    title: 'CPU raycasting',
    category: Category.viewInput,
    summary:
        'Finding which mesh a ray hits, entirely on the CPU, with an answer '
        'the moment it is asked and no frame drawn.',
    since: '0.1.0',
    evidence: 'CPU picking',
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/raycaster.dart',
    ],
  ),
];
