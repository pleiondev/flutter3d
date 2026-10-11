import 'dart:typed_data';

import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

const FieldDeclaration _heat = FieldDeclaration(
  id: 'acme.heat',
  quantity: 'f3d.temperature',
  unit: Unit.kelvin,
  grid: FieldGrid(4, 3, 2),
  transform: FieldTransform(origin: WorldPosition(10, 0, -5), cellSize: 0.5),
  writer: FieldAccess.simulation('acme.diffuse'),
  readers: <FieldAccess>[FieldAccess.frame('acme.shimmer')],
);

final class _Missing extends Capability {
  const _Missing();

  @override
  String get name => '3d-textures';
}

void main() {
  group('FieldDeclaration', () {
    test('a whole description has no problem', () {
      expect(_heat.problem, isNull);
      expect(_heat.grid.cellCount, 24);
      expect(_heat.touchedBy(const FieldAccess.frame('acme.shimmer')), isTrue);
      expect(_heat.touchedBy(const FieldAccess.audio('acme.hiss')), isFalse);
    });

    test('names what is wrong with one that is not', () {
      FieldDeclaration with_({
        String id = 'acme.heat',
        String quantity = 'f3d.temperature',
        FieldGrid grid = const FieldGrid(2, 2, 2),
        FieldResidence residence = FieldResidence.host,
        double cellSize = 1,
        List<FieldAccess> readers = const <FieldAccess>[],
      }) => FieldDeclaration(
        id: id,
        quantity: quantity,
        unit: Unit.kelvin,
        grid: grid,
        transform: FieldTransform(cellSize: cellSize),
        residence: residence,
        writer: const FieldAccess.simulation('acme.diffuse'),
        readers: readers,
      );

      // Mutation: drop a clause of `problem`; the case it guarded reads as
      // a whole field.
      expect(with_(id: 'heat').problem, contains('"<namespace>.<name>"'));
      expect(with_(quantity: 'warmth').problem, contains('"warmth"'));
      expect(with_(grid: const FieldGrid(0, 2, 2)).problem, contains('0x2x2'));
      expect(
        with_(grid: const FieldGrid(2, 2, 2, components: 0)).problem,
        contains('at least one value'),
      );
      expect(with_(cellSize: 0).problem, contains('0.0 m across'));
      expect(
        with_(residence: FieldResidence.texture3D).problem,
        allOf(contains('texture3D'), contains('acme.diffuse')),
      );
      expect(
        with_(
          readers: const <FieldAccess>[FieldAccess.simulation('acme.diffuse')],
        ).problem,
        contains('as its writer and as a reader'),
      );
    });

    test('writes itself with wire names', () {
      expect(_heat.toJson(), <String, Object?>{
        'id': 'acme.heat',
        'quantity': 'f3d.temperature',
        'unit': 'K',
        'grid': <int>[4, 3, 2],
        'transform': <String, Object?>{
          'origin': <double>[10, 0, -5],
          'cellSize': 0.5,
        },
        'residence': 'host',
        'writer': <String, Object?>{
          'side': 'simulation',
          'step': 'acme.diffuse',
        },
        'readers': <Object?>[
          <String, Object?>{'side': 'frame', 'step': 'acme.shimmer'},
        ],
      });
    });
  });

  group('the open sets', () {
    test('read back by name, and answer null for a later one', () {
      for (final residence in FieldResidence.values) {
        expect(FieldResidence.byName(residence.name), same(residence));
      }
      for (final side in FieldSide.values) {
        expect(FieldSide.byName(side.name), same(side));
      }
      for (final reason in FieldRefusal.values) {
        expect(FieldRefusal.byName(reason.name), same(reason));
      }
      expect(FieldResidence.byName('sparse'), isNull);
      expect(FieldResidence.host.onDevice, isFalse);
      expect(FieldResidence.texture3D.onDevice, isTrue);
    });
  });

  group('FieldTransform', () {
    test('puts a cell in the world and a world position in the grid', () {
      final world = _heat.transform.worldOf(const FieldCoordinate(2, 1, 1));
      expect(world, const WorldPosition(11, 0.5, -4.5));
      expect(_heat.transform.gridOf(world), const FieldCoordinate(2, 1, 1));
    });
  });

  group('HostField', () {
    test('keeps its cells in x, then y, then z order', () {
      final field = HostField(_heat)..setValueAt(1, 2, 1, 300);
      // Mutation: lay the grid out z first. Cell (1, 2, 1) would land at
      // another index, and a device reading the bytes another cell.
      expect(field.indexOf(1, 2, 1), (1 * 3 + 2) * 4 + 1);
      expect(field.values[21], 300);
      expect(field.valueAt(1, 2, 1), 300);
      expect(() => field.valueAt(4, 0, 0), throwsRangeError);
    });

    test('samples between cells and holds the edge beyond them', () {
      final field = HostField(_heat);
      for (var x = 0; x < 4; x++) {
        for (var y = 0; y < 3; y++) {
          for (var z = 0; z < 2; z++) {
            field.setValueAt(x, y, z, 100.0 * x + 10.0 * y + z);
          }
        }
      }
      final t = _heat.transform;
      // Halfway between x = 1 and x = 2, a quarter of the way to y = 1.
      expect(
        field.sample(t.worldOf(const FieldCoordinate(1.5, 0.25, 0))),
        closeTo(152.5, 1e-9),
      );
      // Mutation: drop the clamp. Beyond the grid it would read past the
      // last cell, or throw.
      expect(
        field.sample(t.worldOf(const FieldCoordinate(9, -3, 7))),
        300 + 0 + 1,
      );
      expect(
        field.quantityAt(t.worldOf(const FieldCoordinate(1, 1, 1))),
        const Quantity(111, Unit.kelvin),
      );
    });

    test('a read-only view refuses a write and a copy shares nothing', () {
      final field = HostField(_heat)..fill(5);
      final view = field.readOnly;
      expect(view.isWritable, isFalse);
      expect(() => view.setValueAt(0, 0, 0, 1), throwsUnsupportedError);
      final copy = field.copy()..setValueAt(0, 0, 0, 9);
      expect(field.valueAt(0, 0, 0), 5);
      expect(view.valueAt(0, 0, 0), 5);
      field.copyFrom(copy);
      expect(view.valueAt(0, 0, 0), 9);
    });

    test('refuses values of the wrong length', () {
      expect(
        () => HostField.of(_heat, Float32List(5)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('24 values'),
          ),
        ),
      );
    });

    test('is a snapshot part: captured, restored in place, digested', () {
      final field = HostField(_heat)..setValueAt(3, 2, 1, 0.1);
      final part = field.snapshotPart;
      expect(part.id, 'field:acme.heat');
      final saved = part.capture();
      final digest = part.digest();
      field.fill(7);
      // Mutation: digest by the values' sum. A field moved from one cell
      // to another would digest alike.
      expect(part.digest(), isNot(digest));
      part.restore(saved, part.version);
      expect(field.valueAt(3, 2, 1), closeTo(0.1, 1e-7));
      expect(part.digest(), digest);
      expect(
        () => part.restore(<double>[1, 2], part.version),
        throwsStateError,
      );
    });
  });

  group('FieldResidenceException', () {
    test('names the field, the residence and the missing feature', () {
      const refusal = FieldResidenceException(
        field: 'acme.heat',
        residence: FieldResidence.texture3D,
        reason: FieldRefusal.missingFeature,
        capability: _Missing(),
        backend: 'Impeller',
      );
      expect(refusal, isA<CapabilityException>());
      expect(
        refusal.message,
        'field "acme.heat" cannot be held in texture3D on Impeller: the '
        'device has no 3d-textures',
      );
    });
  });
}
