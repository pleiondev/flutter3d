/// The pages of the `post` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const String _settings =
    'packages/flutter3d_core/lib/src/engine/render/render_settings.dart';

const List<Feature> postFeatures = <Feature>[
  Feature(
    id: 'bloom',
    title: 'Bloom and halation',
    category: Category.post,
    summary:
        'Light brighter than the display can show spills over the edge of '
        'what gives it off, and can turn red at the rim.',
    since: '0.1.0',
    evidence: 'an HDR pipeline with tone mapping and bloom',
    keywords: <String>['bloom'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'tone-mapping',
    title: 'Tone-map curves',
    category: Category.post,
    summary:
        'Five ways to squeeze light of any brightness into what a display '
        'can show, side by side on one scene.',
    since: '0.7.0',
    evidence: '`TonemapCurve` with five curves',
    keywords: <String>['tonemapcurve'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'color-grading',
    title: 'Colour grade',
    category: Category.post,
    summary:
        'Contrast, saturation and warmth for the whole picture, separate '
        'tints for the shadows and the highlights, and the marks a lens '
        'leaves.',
    since: '0.3.0',
    evidence: 'colour grading, vignette, grain and chromatic aberration',
    keywords: <String>['vignette', 'chromatic aberration'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'lut-grading',
    title: 'Grade through a LUT',
    category: Category.post,
    summary:
        'A grade written down as a small texture: every colour that comes '
        'in has one colour it comes out as.',
    since: '0.7.0',
    evidence: 'LookSettings.lut',
    keywords: <String>['looksettings.lut'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'render-post',
    title: 'Post effects on your own image',
    category: Category.post,
    summary:
        'Hand the renderer any picture and get it back bloomed, exposed and '
        'tone mapped, with no scene behind it.',
    since: '0.7.0',
    evidence: 'over a buffer from outside',
    keywords: <String>['renderpost'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/renderer.dart',
    ],
  ),
  Feature(
    id: 'disabled-passes',
    title: 'Switching passes off',
    category: Category.post,
    summary:
        'Leave a pass out of a frame by its name, and read back that the frame '
        'did as it was told.',
    since: '0.7.0',
    evidence: 'against the published `passOrder`',
    keywords: <String>['disabledpasses'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'msaa',
    title: 'Automatic multisampling',
    category: Category.post,
    summary:
        'The scene pass smooths its own edges when the device offers it and '
        'nothing in the frame needs the picture read back first.',
    since: '0.7.0',
    evidence: 'antiAliasing',
    keywords: <String>['antialiasing'],
    needs: <Need>{Need.offscreenMsaa},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/renderer_scene_pass.dart',
    ],
  ),
  Feature(
    id: 'xray',
    title: 'X-ray silhouettes',
    category: Category.post,
    summary:
        'The outline of whatever a wall hides, painted flat over the wall, '
        'while the visible part stays lit.',
    since: '0.4.3',
    evidence: 'X-ray silhouettes',
    keywords: <String>['xray'],
    needs: <Need>{Need.stencil},
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/renderer_xray_pass.dart',
    ],
  ),
];
