/// Position, turn and size, three numbers each.
///
/// **Keyed by the object's id at the call site**, for the reason the name field
/// is: a rebuild for a different object must build different boxes rather than
/// rewrite the text under a cursor.
///
/// The turn and the size are shown as `transformFieldsOf` reads them out of the
/// matrix, which is not always the spelling somebody typed — a turn of 30, 90,
/// 30 reads back as 60, 90, 0, because at the pole the X and Z turns are the
/// same turn and only their difference survives. That is a property of Euler
/// angles rather than of this panel, and the file that does the arithmetic
/// argues it at length.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../transform_fields.dart';

/// The 3x3 transform grid: `Position`/`Rotation`/`Scale` down the rows,
/// `X`/`Y`/`Z` across the columns.
class TransformRows extends StatelessWidget {
  const TransformRows({
    super.key,
    required this.fields,
    required this.onChanged,
  });

  final TransformFields fields;
  final ValueChanged<TransformFields> onChanged;

  static const List<String> _axisLabels = <String>['X', 'Y', 'Z'];
  static const List<String> _rowLabels = <String>[
    'Position',
    'Rotation',
    'Scale',
  ];

  /// [fields], with [row]'s own [axis] component replaced by [to] — the one
  /// piece three separate `VectorField` callbacks used to reassemble, now
  /// done in one place since a grid cell only ever changes one number.
  TransformFields _withAxis(int row, int axis, double to) {
    vm.Vector3 replace(vm.Vector3 v) => vm.Vector3(
      axis == 0 ? to : v.x,
      axis == 1 ? to : v.y,
      axis == 2 ? to : v.z,
    );
    return (
      position: row == 0 ? replace(fields.position) : fields.position,
      rotationDegrees: row == 1
          ? replace(fields.rotationDegrees)
          : fields.rotationDegrees,
      scale: row == 2 ? replace(fields.scale) : fields.scale,
    );
  }

  List<double> _rowValues(int row) => switch (row) {
    0 => <double>[fields.position.x, fields.position.y, fields.position.z],
    1 => <double>[
      fields.rotationDegrees.x,
      fields.rotationDegrees.y,
      fields.rotationDegrees.z,
    ],
    _ => <double>[fields.scale.x, fields.scale.y, fields.scale.z],
  };

  /// The hand-over's own "3x3 transform grid": `Position`/`Rotation`/`Scale`
  /// down the rows, `X`/`Y`/`Z` across the columns — a `Table`, not three
  /// stacked full-width fields, so a person can scan one axis across all
  /// three properties in one eyeful rather than hunting through nine rows.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final TextStyle? captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget axisHeader(String said) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(said, textAlign: TextAlign.center, style: captionStyle),
    );
    Widget rowLabel(String said) => Padding(
      padding: const EdgeInsets.only(top: 6, right: 4),
      child: Text(said, style: captionStyle),
    );

    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(56),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            const SizedBox.shrink(),
            for (final String axis in _axisLabels) axisHeader(axis),
          ],
        ),
        for (var row = 0; row < 3; row++)
          TableRow(
            children: <Widget>[
              rowLabel(_rowLabels[row]),
              for (var axis = 0; axis < 3; axis++)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: NumberField(
                    label: _axisLabels[axis],
                    showLabel: false,
                    semanticLabel: '${_rowLabels[row]} ${_axisLabels[axis]}',
                    value: _rowValues(row)[axis],
                    onChanged: (double to) =>
                        onChanged(_withAxis(row, axis, to)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
