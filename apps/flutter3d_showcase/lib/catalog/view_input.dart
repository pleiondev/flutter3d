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
  Feature(
    id: 'pixel-picking',
    title: 'Picking by pixel',
    category: Category.viewInput,
    summary:
        'Asking the renderer which mesh is drawn at a point, exact by '
        'construction because the rasteriser already decided.',
    since: '0.4.3',
    evidence: 'Picking by pixel',
    keywords: <String>['pickpixel'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/renderer_pick_pass.dart',
    ],
  ),
  Feature(
    id: 'screen-bounds',
    title: 'Screen-space bounds',
    category: Category.viewInput,
    summary:
        'The rectangle a box in the world covers on the glass, for a focus '
        'ring, a tooltip or a label to use.',
    since: '0.7.0',
    evidence: 'screenBoundsOfBox',
    keywords: <String>['screenboundsofbox'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/scene/screen_bounds.dart',
    ],
  ),
  Feature(
    id: 'gamepad',
    title: 'Gamepad',
    category: Category.viewInput,
    summary:
        'A gamepad read as a snapshot once a frame, with a dead zone '
        'applied before a game ever sees the number.',
    since: '0.2.0',
    evidence:
        'A gamepad read as a snapshot once per frame, with a dead zone '
        'applied and no opinion about what any button means',
    evidenceFile: 'packages/pad_input/CHANGELOG.md',
    packages: <String>['pad_input'],
  ),
  Feature(
    id: 'pointer-lock',
    title: 'Pointer lock',
    category: Category.viewInput,
    summary:
        'A cursor that never runs out of room: relative motion instead of a '
        'position bounded by the edge of the window.',
    since: '0.2.0',
    evidence:
        'Relative mouse deltas, which Flutter offers on no desktop platform',
    evidenceFile: 'packages/pointer_lock/CHANGELOG.md',
    packages: <String>['pointer_lock'],
  ),
  Feature(
    id: 'input-bindings',
    title: 'Bindings and rebinding',
    category: Category.viewInput,
    summary:
        'Mapping an action to a key, and letting a player replace that '
        'mapping while the game keeps running.',
    since: '0.7.0',
    evidence:
        'rebinding, `SaveFile`/`SettingsFile`/`DemoFile`, volumes, credits, '
        '`AutomapView`, `DragLook`',
    evidenceFile: 'packages/flutter3d_game/CHANGELOG.md',
    packages: <String>['flutter3d_game'],
    keywords: <String>['rebinding', 'draglook'],
  ),
  Feature(
    id: 'touch-controls',
    title: 'Touch controls',
    category: Category.viewInput,
    summary:
        'An on-screen stick and button for a touch device, feeding the same '
        'input state a key or a gamepad axis does.',
    since: '0.4.0',
    evidence: 'A touch control lets go when it leaves',
    evidenceFile: 'packages/flutter3d_game/CHANGELOG.md',
    packages: <String>['flutter3d_game'],
    keywords: <String>['touch stick', 'touch button'],
  ),
];
