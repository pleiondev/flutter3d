/// `edu-06`'s own screen: the same lesson a step panel authors, drawn as a
/// stereo pair and stepped through by button rather than by editing.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart'
    show Flutter3dAppLocalizations;

import 'lesson_player.dart';
import 'stereo_rig.dart';
import 'stereo_surface.dart';
import 'stereo_viewer.dart';

/// Wraps [StereoSurface] around a [LessonPlayer], with a "Previous"/"Next"
/// button pair driving it — the whole of "переключение шагов кнопкой" from
/// `edu-06`'s own acceptance line.
///
/// **No Cardboard is in this room.** [viewer] defaults to
/// [StereoViewer.cardboardV2] because that is the profile the format's own
/// acceptance names, but nothing here has held a real folded holder up to a
/// real phone — the honest claim is that the rig, the lesson and the button
/// are proven; the lens numbers are the published ones, unverified against
/// glass.
final class LessonStereoView extends StatefulWidget {
  /// A stereo lesson view stepping [player] through [scene], seen from
  /// [rig].
  const LessonStereoView({
    super.key,
    required this.renderer,
    required this.scene,
    required this.rig,
    required this.player,
    this.nodes = const <String, SceneNode>{},
    this.restPositions = const <String, Vector3>{},
    this.viewer = StereoViewer.cardboardV2,
    this.onTick,
  });

  /// The renderer the pair is drawn with; borrowed, never disposed here.
  final Renderer renderer;

  /// The scene the lesson's nodes live in.
  final Scene scene;

  /// The rig whose stage each step places and whose eyes draw the pair.
  final StereoRig rig;

  /// The step state the buttons move and each frame applies.
  final LessonPlayer player;

  /// The lesson's nodes by entity id, moved by a step's `offsets`. Empty
  /// for a lesson with no `prop` or `model`.
  final Map<String, SceneNode> nodes;

  /// Where each of [nodes] stood as authored — `edu-00` §6's layered
  /// teardown, `flutter3d_lesson_viewer`'s own `LessonView.restPositions`
  /// counterpart. Empty for a lesson with no `prop`/`model`, the same as
  /// [nodes].
  final Map<String, Vector3> restPositions;

  /// The holder the phone sits in, Cardboard v2 by default; null draws a
  /// centred pair for a phone held in the hands. See
  /// [StereoSurface.viewer].
  final StereoViewer? viewer;

  /// Called once a frame, alongside [LessonPlayer.applyCurrent] — a
  /// `WidgetSurface` on the lesson's own scene needs `tick()` called the
  /// same way, and this widget does not reach for `WidgetSurfaceVisuals` to
  /// do it: the caller, which already resolved the level's `widget_surface`
  /// entities into nodes, hands the one call back in rather than this
  /// widget growing a dependency to make it itself.
  final VoidCallback? onTick;

  @override
  State<LessonStereoView> createState() => _LessonStereoViewState();
}

class _LessonStereoViewState extends State<LessonStereoView> {
  @override
  Widget build(BuildContext context) {
    final words = Flutter3dAppLocalizations.of(context);
    return Stack(
      children: <Widget>[
        StereoSurface(
          renderer: widget.renderer,
          scene: widget.scene,
          rig: widget.rig,
          settings: () => const RenderSettings().forStereo(),
          onBeforeFrame: () {
            widget.player.applyCurrent(
              widget.rig,
              nodes: widget.nodes,
              restPositions: widget.restPositions,
            );
            widget.onTick?.call();
          },
          viewer: widget.viewer,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: words.previousStep,
                onPressed: widget.player.isFirst
                    ? null
                    : () => setState(widget.player.previous),
              ),
              const SizedBox(width: 24.0),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: words.nextStep,
                onPressed: widget.player.isLast
                    ? null
                    : () => setState(widget.player.next),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
