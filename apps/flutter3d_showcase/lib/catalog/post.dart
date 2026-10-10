/// The pages of the `post` category.
///
/// **One file a category, and only this category's worker writes it**, so the
/// pages of nine categories can be written at once without meeting in a shared
/// list. `lib/src/catalog/catalog.dart` joins them.
library;

import 'package:flutter3d_showcase/src/catalog/feature.dart';

const String _settings =
    'packages/flutter3d_core/lib/src/engine/render/render_settings.dart';
const String _frameNodes =
    'packages/flutter3d_core/lib/src/engine/render/renderer_frame_nodes.dart';
const String _coreChangelog = 'packages/flutter3d_core/CHANGELOG.md';

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
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'Halation warms each level once, and a new scatter setting weighs the wide levels against the core.',
        evidence: 'Bloom\'s halation warms each level once.',
      ),
    ],
  ),
  Feature(
    id: 'tone-mapping',
    title: 'Tone-map curves',
    category: Category.post,
    summary:
        'Every tone curve the engine has, and a display transform table, '
        'squeezing light of any brightness into what a display can show, '
        'side by side on one scene.',
    since: '0.7.0',
    evidence: '`TonemapCurve` with five curves',
    keywords: <String>['tonemapcurve'],
    engineFiles: <String>[_settings],
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'AgX is the whole Minimal AgX and comes out linear; its sigmoid used to be encoded to sRGB twice.',
        evidence: 'AgX is AgX, and it is linear.',
      ),
      Change(
        version: '0.8.0',
        note:
            'A baked display transform can take the curve\'s place, and the new aces2 curve is the ACES 2.0 tonescale the engine ships as one.',
        evidence: 'A display transform in place of the tone curve.',
      ),
    ],
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
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'Contrast pivots on mid grey, lift keeps white white, and a centred dither is on by default.',
        evidence: 'Contrast pivots on linear light\'s mid grey',
      ),
    ],
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
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'The table is indexed and answered in sRGB, the space a .cube file is written in.',
        evidence: 'A LUT is indexed and answered in sRGB',
      ),
    ],
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
    title: 'Switching steps off',
    category: Category.post,
    summary:
        'Leave steps out of a frame with `without`, and read back that the '
        'frame did as it was told.',
    since: '0.7.0',
    evidence: 'against each step\'s own passes',
    keywords: <String>['without', 'renderstep', 'disabledpasses'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'auto-exposure',
    title: 'Auto exposure',
    category: Category.post,
    summary:
        'A meter reads the frame\'s own brightness and moves the exposure '
        'toward a chosen grey, the way a camera\'s own metering does.',
    since: '0.4.3',
    evidence: 'Auto exposure',
    keywords: <String>['autoexposuresettings'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/engine/render/auto_exposure.dart',
    ],
  ),
  Feature(
    id: 'screen-space-reflections',
    title: 'Screen-space reflections',
    category: Category.post,
    summary:
        'A ray marched through the picture already drawn, so a polished '
        'floor shows what stands on it.',
    since: '0.2.0',
    evidence: 'screen-space reflections',
    keywords: <String>['reflectionsettings'],
    engineFiles: <String>[_settings],
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'The march starts at a jittered point and refines its hit, so the smeared ghosts are gone.',
        evidence: 'Screen-space reflections lose their ghosts.',
      ),
    ],
  ),
  Feature(
    id: 'ambient-occlusion',
    title: 'Ambient occlusion',
    category: Category.post,
    summary:
        'The ambient term darkened wherever a surface cannot see much of the '
        'sky, from nothing but the shapes already in the frame.',
    since: '0.2.0',
    evidence: 'ambient occlusion',
    keywords: <String>['ambientocclusionsettings'],
    engineFiles: <String>[_settings],
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'The blur weighs depth relative to the centre, so a distant floor blurs like a near one.',
        evidence: 'is a fraction of depth now',
      ),
    ],
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
    id: 'light-shafts',
    title: 'Light shafts',
    category: Category.post,
    summary:
        'A view ray marched through the sun\'s own shadow map, so a beam '
        'through a doorway keeps the doorway\'s shape.',
    since: '0.7.0',
    evidence: 'LightShaftSettings',
    keywords: <String>['lightshaftsettings'],
    engineFiles: <String>[_settings],
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'Shafts scatter the sun\'s own light through the air, with a density and a forward glow, instead of veiling the frame.',
        evidence:
            'Light shafts scatter the sun\'s light instead of veiling the frame.',
      ),
    ],
  ),
  Feature(
    id: 'anti-aliasing',
    title: 'FXAA, SMAA and sharpen',
    category: Category.post,
    summary:
        'One pass over the finished picture that softens a hard contrast '
        'step, with a sharpen riding the same taps.',
    since: '0.7.0',
    evidence: 'AntiAliasSettings` with FXAA and `sharpen',
    keywords: <String>['antialiassettings'],
    engineFiles: <String>[_settings],
    changes: <Change>[
      Change(
        version: '1.0.0-rc.1',
        note:
            'SMAA 1x joins FXAA as a method: three passes that rebuild the line behind each staircase, truer on long shallow edges.',
        evidence: 'SMAA 1x beside FXAA.',
      ),
    ],
  ),
  Feature(
    id: 'depth-of-field',
    title: 'Depth of field',
    category: Category.post,
    summary:
        'A thin-lens blur from a focus distance, a focal length and an '
        'f-number, the numbers a photographer already knows.',
    since: '0.7.0',
    evidence: 'DepthOfFieldSettings',
    keywords: <String>['depthoffieldsettings'],
    engineFiles: <String>[_settings],
    changes: <Change>[
      Change(
        version: '0.7.4',
        note:
            'A sharp object no longer bleeds into the blur behind it, and the sky blurs as the far field does.',
        evidence: 'Depth of field reads depth nearest.',
      ),
    ],
  ),
  Feature(
    id: 'viewport-shading',
    title: 'Viewport shading',
    category: Category.post,
    summary:
        'Normals, clay, outline and curvature, each read out of the second '
        'buffer the scene pass already writes.',
    since: '0.7.0',
    evidence:
        'ViewportShadingSettings` for normals, clay, outline and curvature',
    keywords: <String>['viewportshadingsettings'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'surface-buffer',
    title: 'The surface buffer',
    category: Category.post,
    summary:
        'The world normal and view-axis depth the scene pass writes once, '
        'for every screen-space effect to share, seen raw.',
    since: '0.4.3',
    evidence: 'Neither extra draw writes the surface buffer',
    keywords: <String>['surface buffer'],
    engineFiles: <String>[_settings],
  ),
  Feature(
    id: 'adaptive-resolution',
    title: 'Adaptive resolution',
    category: Category.post,
    summary:
        'The whole frame drawn smaller when nothing else is left to trade, '
        'at a scale a plain object works out from recent frame costs.',
    since: '0.7.0',
    evidence: 'renderScale` with `AdaptiveScale',
    keywords: <String>['adaptivescale'],
    engineFiles: <String>[_settings],
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
  Feature(
    id: 'temporal-anti-aliasing',
    title: 'Temporal anti-aliasing',
    category: Category.post,
    summary:
        'Each frame is drawn a fraction of a pixel off and blended with the '
        'frames before it, so thin edges stop stair-stepping and flickering.',
    since: '0.8.0',
    evidence: 'Temporal anti-aliasing.',
    evidenceFile: _coreChangelog,
    keywords: <String>['temporalsettings', 'temporalclip'],
    engineFiles: <String>[_settings, _frameNodes],
  ),
  Feature(
    id: 'motion-blur',
    title: 'Motion blur',
    category: Category.post,
    summary:
        'Whatever moved while the shutter was open is smeared along the way '
        'it moved, as a camera would show it.',
    since: '0.8.0',
    evidence: 'Motion blur.',
    evidenceFile: _coreChangelog,
    keywords: <String>['motionblursettings'],
    engineFiles: <String>[_settings, _frameNodes],
  ),
  Feature(
    id: 'spatial-upscale',
    title: 'Spatial upscaling',
    category: Category.post,
    summary:
        'A frame drawn at a smaller size is brought back up with a filter '
        'that follows edges, so outlines stay crisp.',
    since: '0.8.0',
    evidence: 'Spatial upscaling.',
    evidenceFile: _coreChangelog,
    keywords: <String>['spatialupscalesettings'],
    engineFiles: <String>[_settings, _frameNodes],
  ),
  Feature(
    id: 'horizon-occlusion',
    title: 'Horizon occlusion and bounced light',
    category: Category.post,
    summary:
        'Corners darkened by how much sky each point can see between its '
        'horizons, and a coloured wall tinting the floor beside it.',
    since: '0.8.0',
    evidence: 'Horizon-based occlusion and indirect light.',
    evidenceFile: _coreChangelog,
    keywords: <String>['ambientocclusionmethod', 'gtao', 'ssil'],
    engineFiles: <String>[_settings, _frameNodes],
  ),
  Feature(
    id: 'local-exposure',
    title: 'Local exposure',
    category: Category.post,
    summary:
        'Each part of the picture gets its own exposure, so a dark room and '
        'the bright window in it can both be seen.',
    since: '0.8.0',
    evidence: 'Local exposure.',
    evidenceFile: _coreChangelog,
    keywords: <String>['localexposuresettings'],
    engineFiles: <String>[_settings, _frameNodes],
  ),
  Feature(
    id: 'high-contrast',
    title: 'High contrast',
    category: Category.post,
    summary:
        'Texture flattened, colour drained and every edge drawn, with a ring '
        'in its role\'s colour around each thing a player has to find.',
    since: '1.0.0-rc.1',
    evidence: 'A high-contrast look with outlines',
    evidenceFile: _coreChangelog,
    keywords: <String>['HighContrastSettings', 'outlineColor'],
    engineFiles: <String>[
      _settings,
      _frameNodes,
      'packages/flutter3d_core/lib/src/engine/scene/mesh_node.dart',
    ],
  ),
  Feature(
    id: 'lens-effects',
    title: 'Lens flare, distortion and .cube tables',
    category: Category.post,
    summary:
        'A bright lamp throws ghosts and a halo across the frame, the frame bows or pinches, and a grade comes in as a .cube file.',
    since: '1.0.0-rc.1',
    evidence: 'The lens: distortion, flare, and tables from a grading tool.',
    evidenceFile: _coreChangelog,
    keywords: <String>[
      'LensFlareSettings',
      'LookSettings.distortion',
      'CubeLut',
    ],
    engineFiles: <String>[
      _settings,
      _frameNodes,
      'packages/flutter3d_core/lib/src/formats/cube_lut.dart',
    ],
  ),
  Feature(
    id: 'debug-views',
    title: 'Debug views and render stats',
    category: Category.post,
    summary:
        'One material channel in place of the light, wiped across the frame, and what the frame says it cost.',
    since: '1.0.0-rc.1',
    evidence: 'A material channel in place of the light',
    evidenceFile: _coreChangelog,
    keywords: <String>['DebugViewSettings', 'DebugView', 'targetBytes'],
    engineFiles: <String>[
      _settings,
      'packages/flutter3d_core/lib/src/engine/render/frame_result.dart',
    ],
  ),
  Feature(
    id: 'colour-vision',
    title: 'Colour vision',
    category: Category.post,
    summary:
        'The picture as a player missing a cone sees it or corrected for them, colours with meanings a player can move, and a lint for cues told apart by hue alone.',
    since: '1.0.0-rc.1',
    evidence: 'Colour vision, as a colour table.',
    evidenceFile: _coreChangelog,
    keywords: <String>['ColorVision'],
    packages: <String>['flutter3d', 'flutter3d_game'],
    engineFiles: <String>[
      'packages/flutter3d_core/lib/src/formats/color_vision.dart',
      'packages/flutter3d_game/lib/src/config/color_roles.dart',
    ],
  ),
];
