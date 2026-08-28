/// What `editor_cubit_test.dart` and `editor_cubit_ready_test.dart` share: a
/// document to open and a template to offer, both built without a window —
/// the same way `editing_test.dart` builds its own.
library;

import 'dart:convert';

import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/looks.dart';
import 'package:flutter3d_editor/src/scaffold.dart';

/// A small document, written the way a generator writes one.
String _document({String? generatedBy}) => jsonEncode(<String, Object?>{
  'version': 1,
  'name': 'test',
  'generatedBy': ?generatedBy,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[2.0, 2.0, 2.0],
      'material': 'stone',
    },
    <String, Object?>{
      'at': <double>[4.0, 0.0, 0.0],
      'size': <double>[2.0, 2.0, 2.0],
      'material': 'stone',
    },
  ],
});

/// A document with two brushes, open and ready to hand to `EditorCubit.opened`.
Editing openTestDocument({String? generatedBy}) => Editing.parse(
  _document(generatedBy: generatedBy),
  path: '/levels/test.json',
);

/// What no game says its own words look like — `EditorCubit.opened` needs one.
const Looks noLooks = Looks.none;

/// A template with nothing in it, for the chooser tests that only care that
/// one was offered.
const Template testTemplate = Template(
  id: 'shooter',
  name: 'Shooter',
  about: 'a shooter',
  files: <String, String>{},
);
