import 'package:dart_mcp/server.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

import 'diagnostic_renderer.dart';
import 'sim_session.dart';

/// One tool: what an agent is offered, and what calling it does — see
/// `flutter3d_mcp_kit`'s [OfferedTool].
///
/// Typed on [SimSession] rather than on a session of its own: this used to
/// be `flutter3d_render_mcp`, a second stdio process for the same agent's
/// same conversation — `par-02`'s own tools beside `ai-00`'s, playing a
/// level and diagnosing a frame are still two different questions with two
/// different pieces of state behind them, so [SimSession.diagnostic] holds
/// the second rather than folding the two together.
typedef DiagnosticTool = OfferedTool<SimSession, PictureAnswer>;

double _number(
  Map<String, Object?> args,
  String key, [
  double fallback = 0.0,
]) => (args[key] as num?)?.toDouble() ?? fallback;

DiagnosticView _view(Map<String, Object?> args) {
  final name = args['view'] as String?;
  return DiagnosticView.values.firstWhere(
    (v) => v.name == name,
    orElse: () => DiagnosticView.lit,
  );
}

const String _viewDescription =
    'lit (the ordinary frame), normals (the surface buffer: octahedral '
    'normal, roughness, view depth in metres), shadowMap or staticShadowMap '
    '(the point-shadow cube atlases). Default lit.';

/// The five verbs `par-02` asks for.
///
/// **Named `diag*` rather than bare**, the one thing merging into one tool
/// table could not leave alone: this package's own `open`/`frame` already
/// named two of [simToolsFor]'s six, and an agent given one tool table with
/// two tools called `open` is an agent nothing here can route a call to.
List<DiagnosticTool> get diagnosticTools => <DiagnosticTool>[
  DiagnosticTool(
    Tool(
      name: 'diagOpen',
      description:
          'Open a level document for diagnosis — a second, independent '
          'level from whatever `open` has playing, if anything. No genre '
          'vocabulary is known here, so a level whose entities need one '
          'will fail to validate — this tool only ever looks at the '
          'picture, not at what plays in it.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'path': StringSchema(description: 'a level document on disk'),
        },
        required: <String>['path'],
      ),
    ),
    (session, args) => session.diagnostic.open(args['path']! as String),
  ),
  DiagnosticTool(
    Tool(
      name: 'diagFrame',
      description:
          'Draw a frame with no GPU, from a given eye position looking in a '
          'given direction, in one of the renderer\'s own debug views. Every '
          'later call (diagPixel, diagPasses, diagScanNaN) reads back this '
          'same frame, so draw it again after moving the eye or changing '
          'the view.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'atX': NumberSchema(description: 'eye position, default 0'),
          'atY': NumberSchema(description: 'eye position, default 0'),
          'atZ': NumberSchema(description: 'eye position, default 0'),
          'aimX': NumberSchema(
            description: 'look direction (not a point), default 0,0,-1',
          ),
          'aimY': NumberSchema(description: 'look direction, default 0'),
          'aimZ': NumberSchema(description: 'look direction, default -1'),
          'view': StringSchema(description: _viewDescription),
        },
      ),
    ),
    (session, args) => session.diagnostic.frame(
      atX: _number(args, 'atX'),
      atY: _number(args, 'atY'),
      atZ: _number(args, 'atZ'),
      aimX: _number(args, 'aimX'),
      aimY: _number(args, 'aimY'),
      aimZ: _number(args, 'aimZ', -1.0),
      view: _view(args),
    ),
  ),
  DiagnosticTool(
    Tool(
      name: 'diagPixel',
      description:
          'The raw, unclamped value of one pixel in the last diagnostic '
          'frame drawn — a depth past one metre and a NaN both survive '
          'here, where the picture itself would have rounded either into '
          'an ordinary-looking colour. Says which pass produced the value, '
          'too.',
      inputSchema: ObjectSchema(
        properties: <String, Schema>{
          'x': IntegerSchema(description: '0-based, from the left'),
          'y': IntegerSchema(description: '0-based, from the top'),
        },
        required: <String>['x', 'y'],
      ),
    ),
    (session, args) => session.diagnostic.pixel(
      (args['x']! as num).toInt(),
      (args['y']! as num).toInt(),
    ),
  ),
  DiagnosticTool(
    Tool(
      name: 'diagPasses',
      description:
          'Every pass the frame graph kept for the last diagnostic frame '
          'drawn, in the order it ran, with its own timing — what actually '
          'happened, rather than what the settings asked for.',
      inputSchema: ObjectSchema(),
    ),
    (session, args) => session.diagnostic.passes(),
  ),
  DiagnosticTool(
    Tool(
      name: 'diagScanNaN',
      description:
          'The first pixel in the last diagnostic frame drawn where any '
          'channel is a NaN or an infinity, and which pass is answerable '
          'for it.',
      inputSchema: ObjectSchema(),
    ),
    (session, args) => session.diagnostic.scanNaN(),
  ),
];
