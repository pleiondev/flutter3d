/// `anim-07`'s own `SkeletonTree`: a real expandable joint-hierarchy tree
/// over [ProjectSkeleton] — the same skeleton [ProjectSkeleton.joints]
/// already lists, given the shape a person can read.
///
/// **The hierarchy is [ModelObject.parent], not a separate tree the skeleton
/// carries of its own.** [ProjectSkeleton.joints] is a flat list, in the
/// order the vertex attribute addresses them — `anim-03`'s own row says so
/// explicitly — so the parent/child lines a tree needs come from the same
/// place every other parent/child line in this project does. A joint whose
/// own parent is not itself one of [ProjectSkeleton.joints] — the object the
/// skin hangs from, ordinarily — draws at the top level rather than being
/// dropped, since it is still a real joint with nowhere higher in the rig to
/// nest it under.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

import 'theme.dart';

/// A joint-hierarchy tree over one [ProjectSkeleton]. Selecting a row reports
/// the joint's own [ModelObject.id] through [onSelectJoint]; the disclosure
/// arrow expands or collapses a branch without selecting it.
class SkeletonTree extends StatefulWidget {
  const SkeletonTree({
    super.key,
    required this.objects,
    required this.skeleton,
    this.selectedJoint,
    required this.onSelectJoint,
  });

  /// Every object in the project — read only to find a joint's own
  /// [ModelObject.name] and [ModelObject.parent], the same lookup
  /// [ModelProject.operator []] does, taken as a plain list rather than a
  /// whole [ModelProject] since nothing else about the project is this
  /// widget's business.
  final List<ModelObject> objects;

  final ProjectSkeleton skeleton;

  final int? selectedJoint;

  final ValueChanged<int> onSelectJoint;

  @override
  State<SkeletonTree> createState() => _SkeletonTreeState();
}

class _SkeletonTreeState extends State<SkeletonTree> {
  /// Joints whose own children are hidden. Empty at first, so a tree opens
  /// fully expanded — the ordinary case for a rig small enough to fit a
  /// panel, and the one `anim-08`'s own overlay already assumes when it
  /// shows every joint at once.
  final Set<int> _collapsed = <int>{};

  late Map<int, ModelObject> _byId = _indexOf(widget.objects);

  static Map<int, ModelObject> _indexOf(List<ModelObject> objects) =>
      <int, ModelObject>{for (final object in objects) object.id: object};

  @override
  void didUpdateWidget(covariant SkeletonTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.objects, widget.objects)) {
      _byId = _indexOf(widget.objects);
    }
  }

  String _labelOf(int jointId) => _byId[jointId]?.name ?? 'joint $jointId';

  /// [parentId]'s own children among [ProjectSkeleton.joints] — null means
  /// the top level: a joint with no parent, or whose parent is not itself a
  /// joint in this skeleton.
  List<int> _childrenOf(int? parentId) {
    final joints = widget.skeleton.joints.toSet();
    return <int>[
      for (final id in widget.skeleton.joints)
        if (_parentJointOf(id, joints) == parentId) id,
    ];
  }

  int? _parentJointOf(int jointId, Set<int> joints) {
    final parent = _byId[jointId]?.parent;
    if (parent == null || !joints.contains(parent)) return null;
    return parent;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.skeleton.joints.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No joints',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        for (final id in _childrenOf(null))
          ..._buildRows(id, depth: 0, ancestors: const <int>{}),
      ],
    );
  }

  List<Widget> _buildRows(
    int id, {
    required int depth,
    required Set<int> ancestors,
  }) {
    // Defensive: a cyclic `parent` chain (never produced by this project's own
    // commands, but not a shape [ProjectSkeleton] itself refuses) stops here
    // rather than recursing forever.
    if (ancestors.contains(id)) return const <Widget>[];

    final children = _childrenOf(id);
    final expanded = !_collapsed.contains(id);
    final selected = id == widget.selectedJoint;
    final theme = Theme.of(context);

    final row = Material(
      color: selected ? kModelerScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelectJoint(id),
        child: SizedBox(
          height: ModelerMetrics.row,
          child: Row(
            children: <Widget>[
              SizedBox(width: depth * 16.0),
              SizedBox(
                width: 24,
                child: children.isEmpty
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                        ),
                        onPressed: () => setState(() {
                          if (expanded) {
                            _collapsed.add(id);
                          } else {
                            _collapsed.remove(id);
                          }
                        }),
                      ),
              ),
              Expanded(
                child: Text(
                  _labelOf(id),
                  overflow: TextOverflow.ellipsis,
                  style: selected
                      ? theme.textTheme.labelMedium
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return <Widget>[
      row,
      if (expanded)
        for (final child in children)
          ..._buildRows(
            child,
            depth: depth + 1,
            ancestors: <int>{...ancestors, id},
          ),
    ];
  }
}
