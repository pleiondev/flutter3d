/// The scene, as something a screen reader can walk — `gfx-79n`.
///
/// **A 3D viewport is one opaque rectangle to the platform, and that is the
/// whole problem.** Everything in it is pixels in a texture: a screen reader
/// arriving at the viewport is told there is an image, and a person navigating
/// by touch exploration finds one target the size of the window. Every object
/// the scene holds — the thing being edited, the thing about to be selected —
/// is invisible to the accessibility layer, not because it is hard to describe
/// but because nobody ever described it.
///
/// This overlays one semantics node per object, positioned where the object
/// projects and labelled with what it is. Flutter's own tree does the rest: the
/// platform gets a list it can read out, focus and activate, and the focus ring
/// lands on the object rather than on the window.
///
/// **Why the rectangles come from the camera rather than from a widget.** A
/// semantics node's bounds are ordinarily whatever its widget occupies; here
/// there are no widgets, only a projection that changes whenever the camera or
/// the object moves. `screenBoundsOfBox` in `flutter3d_core` is that projection,
/// and this widget is the part that knows about Flutter.
///
/// What this does *not* claim: it is not a substitute for a keyboard path
/// through the application, and a scene of ten thousand objects should be
/// filtered before it gets here — a screen reader handed ten thousand nodes is
/// a screen reader nobody can use. [SceneSemantics] takes the list it is given.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart' show Aabb3;

/// One object, as the accessibility layer will meet it.
@immutable
final class SemanticObject {
  const SemanticObject({
    required this.id,
    required this.label,
    required this.bounds,
    this.hint,
    this.selected = false,
    this.onTap,
  });

  /// What the application calls this object. Used as the semantics key, so a
  /// node keeps its identity across frames and focus does not jump when the
  /// list is reordered.
  final Object id;

  /// What a screen reader reads out. A name, not a description of the widget:
  /// "left wheel", not "3D object button".
  final String label;

  /// An extra sentence about what activating it does, when that is not obvious
  /// from the label.
  final String? hint;

  /// Where it is on the glass, in logical pixels.
  final Rect bounds;

  /// Whether it is the current selection, which the platform announces
  /// separately from the label.
  final bool selected;

  /// What activating it does. Null makes the node readable but not actionable,
  /// which is the honest state for an object nothing can be done to.
  final VoidCallback? onTap;
}

/// One object as the application knows it, before anything is projected.
///
/// The split from [SemanticObject] is the split between what the scene knows
/// and what the glass knows: an application has a node and a name for it, and
/// only the widget knows how big the viewport turned out to be.
@immutable
final class SceneAnnouncement {
  const SceneAnnouncement({
    required this.id,
    required this.label,
    required this.node,
    this.hint,
    this.selected = false,
    this.onTap,
  });

  final Object id;
  final String label;
  final String? hint;

  /// What to announce. Its `subtreeBounds` is the box that gets projected, so
  /// a group announces as the extent of everything under it, which is what a
  /// person exploring by touch expects of a group.
  final SceneNode node;

  final bool selected;
  final VoidCallback? onTap;
}

/// [announcements] projected through [camera] for a viewport of [size].
///
/// Anything with no bounds, or entirely behind the eye, is dropped: a node a
/// screen reader is told about but cannot be given a position for is a node
/// whose focus ring has nowhere to go.
List<SemanticObject> semanticObjectsFor(
  List<SceneAnnouncement> announcements, {
  required CameraNode camera,
  required Size size,
}) {
  if (size.isEmpty) return const <SemanticObject>[];
  final viewProjection = camera.viewProjection(size.width / size.height);
  return <SemanticObject>[
    for (final it in announcements)
      if (it.node.subtreeBounds case final Aabb3 box)
        if (screenBoundsOfBox(
              viewProjection,
              box,
              width: size.width,
              height: size.height,
            )
            case final ScreenBounds at)
          SemanticObject(
            id: it.id,
            label: it.label,
            hint: it.hint,
            selected: it.selected,
            onTap: it.onTap,
            bounds: Rect.fromLTRB(at.left, at.top, at.right, at.bottom),
          ),
  ];
}

/// Publishes [objects] to the platform's accessibility layer on top of [child].
///
/// [child] is wrapped in `ExcludeSemantics`, because the picture underneath is
/// the one opaque rectangle this widget exists to replace: leaving it in would
/// give a screen reader the window-sized target *and* the objects, and the
/// window-sized one is what touch exploration finds first.
final class SceneSemantics extends StatelessWidget {
  const SceneSemantics({
    required this.objects,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final List<SemanticObject> objects;
  final Widget child;

  /// Switched off, this is `child` and nothing else — not an empty overlay.
  ///
  /// A viewport with no objects to announce should cost no nodes at all, and an
  /// application that has not filled the list yet should not publish an empty
  /// one: a screen reader told "there is nothing here" is told something false.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || objects.isEmpty) return child;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: ExcludeSemantics(child: child)),
        for (final object in objects)
          Positioned.fromRect(
            rect: object.bounds,
            child: Semantics(
              key: ValueKey<Object>(object.id),
              label: object.label,
              hint: object.hint,
              selected: object.selected,
              button: object.onTap != null,
              onTap: object.onTap,
              // The node is the whole of it: there is no painted child, so the
              // rectangle is what the platform draws its focus ring around.
              // `IgnorePointer` so that a semantics overlay cannot eat the
              // gestures the viewport underneath is built out of — the
              // platform activates through `onTap` above, which is not a hit
              // test.
              child: const IgnorePointer(child: SizedBox.expand()),
            ),
          ),
      ],
    );
  }
}
