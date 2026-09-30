/// `diffLevel` splits an edit into what can be patched into a running scene
/// and what has to go through a timeline branch.
///
///     dart test test/level_diff_test.dart
///
/// Mutation: drop `'entities'` from the simulation list and the moved crate
/// patches in place; compare lights by count alone and the recoloured lamp
/// is missed.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Map<String, Object?> _document() => <String, Object?>{
  'version': 1,
  'name': 'yard',
  'fogDensity': 0.02,
  'materials': <String, Object?>{
    'stone': <String, Object?>{
      'color': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0, -0.5, 0],
      'size': <double>[20, 1, 20],
      'material': 'stone',
    },
  ],
  'lights': <Object?>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[0, 3, 0],
      'color': <double>[1, 1, 1],
    },
  ],
  'entities': <Object?>[
    <String, Object?>{
      'type': 'crate',
      'at': <double>[2, 0, 2],
    },
  ],
};

/// The level, after [edit] has changed its document.
Level _edited(void Function(Map<String, Object?> json) edit) =>
    Level.fromJson(_document()..let(edit));

extension on Map<String, Object?> {
  void let(void Function(Map<String, Object?>) edit) => edit(this);
}

void main() {
  final before = Level.fromJson(_document());

  test('the same document is no change', () {
    final diff = diffLevel(before, Level.fromJson(_document()));
    expect(diff.isEmpty, isTrue);
    expect(diff.presentationOnly, isTrue);
  });

  test('a recoloured lamp, a material and the fog patch in place', () {
    final after = _edited((json) {
      ((json['lights']! as List<Object?>).single!
          as Map<String, Object?>)['color'] = <double>[
        1,
        0.5,
        0.2,
      ];
      json['materials'] = <String, Object?>{
        'stone': <String, Object?>{
          'color': <double>[0.3, 0.3, 0.3, 1.0],
        },
        'moss': <String, Object?>{
          'color': <double>[0.1, 0.4, 0.1, 1.0],
        },
      };
      json['fogDensity'] = 0.05;
    });

    final diff = diffLevel(before, after);

    expect(diff.lights, <int>[0]);
    expect(diff.lightCountChanged, isFalse);
    expect(diff.materials, unorderedEquals(<String>['stone', 'moss']));
    expect(diff.fog, isTrue);
    expect(diff.music, isFalse);
    expect(diff.presentationOnly, isTrue);
  });

  test('a lamp added is a count change, not a patch of index one', () {
    final after = _edited((json) {
      (json['lights']! as List<Object?>).add(<String, Object?>{
        'type': 'point',
        'at': <double>[5, 3, 0],
      });
    });

    final diff = diffLevel(before, after);

    expect(diff.lightCountChanged, isTrue);
    expect(diff.lights, isEmpty);
    expect(diff.presentationOnly, isTrue);
  });

  test('a moved crate and a wider floor go through the timeline', () {
    final after = _edited((json) {
      ((json['entities']! as List<Object?>).single!
          as Map<String, Object?>)['at'] = <double>[
        3,
        0,
        2,
      ];
      ((json['brushes']! as List<Object?>).single!
          as Map<String, Object?>)['size'] = <double>[
        30,
        1,
        20,
      ];
    });

    final diff = diffLevel(before, after);

    expect(diff.simulation, <String>['brushes', 'entities']);
    expect(diff.presentationOnly, isFalse);
  });

  test('a brush that only changes material is still the simulation\'s', () {
    // Its surface falls back to its material, and footsteps read surfaces.
    final after = _edited((json) {
      ((json['brushes']! as List<Object?>).single!
              as Map<String, Object?>)['material'] =
          'moss';
    });

    expect(diffLevel(before, after).simulation, <String>['brushes']);
  });

  test('the next level is the run\'s, the music the picture\'s', () {
    final after = _edited((json) {
      json['next'] = 'cellar';
      json['music'] = 'rain.ogg';
    });

    final diff = diffLevel(before, after);

    expect(diff.simulation, <String>['next']);
    expect(diff.music, isTrue);
  });
}
