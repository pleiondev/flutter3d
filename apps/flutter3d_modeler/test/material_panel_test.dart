/// `mat-04`'s own full panel: a list of the project's materials, and — for
/// the one an object is painted with — every field `SurfaceMaterial` carries.
///
///     flutter test test/material_panel_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/texture_slot.dart';
import 'package:flutter3d_modeler/src/ui/material_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ProjectMaterial _material({String? name, double metallic = 0.0}) =>
    ProjectMaterial(
      surface: SurfaceMaterial(name: name, metallic: metallic),
    );

/// A slot with no file bound at all — [TextureSlotController]'s own five
/// fields beyond the name, every one of them null or a no-op.
const TextureSlotController _emptySlot = (
  name: null,
  subtitle: null,
  badge: null,
  thumbnail: null,
  onChoose: _noop,
  onClear: null,
);

void _noop() {}

/// A slot map with every one of [SetTexture]'s five names, each empty and
/// each callback a no-op unless a caller overrides one.
Map<String, TextureSlotController> _emptySlots({
  VoidCallback? onChooseAlbedo,
}) => <String, TextureSlotController>{
  'albedo': onChooseAlbedo == null
      ? _emptySlot
      : (
          name: null,
          subtitle: null,
          badge: null,
          thumbnail: null,
          onChoose: onChooseAlbedo,
          onClear: null,
        ),
  'normal': _emptySlot,
  'metallicRoughness': _emptySlot,
  'occlusion': _emptySlot,
  'emissive': _emptySlot,
};

/// A PNG whose `IHDR` names [width]/[height], padded out to [totalBytes] so a
/// weight can be asserted on it too — the same minimal header
/// `texture_slot_test.dart` builds, copied here rather than shared across a
/// test-only import neither file otherwise needs.
Uint8List _pngBytes(int width, int height, {required int totalBytes}) {
  final bytes = Uint8List(totalBytes);
  final view = ByteData.sublistView(bytes);
  bytes.setAll(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  view.setUint32(8, 13, Endian.big);
  bytes.setAll(12, <int>[0x49, 0x48, 0x44, 0x52]);
  view.setUint32(16, width, Endian.big);
  view.setUint32(20, height, Endian.big);
  bytes.setAll(24, <int>[8, 6, 0, 0, 0]);
  return bytes;
}

/// The panel's own full length, with every texture slot and the advanced
/// section open, does not fit the default 800×600 test surface — widened
/// here rather than in each test, the same way `accessibility_test.dart`
/// does for its own tall screens.
Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectMaterial> materials,
  int? activeIndex,
  ValueChanged<int?>? onAssign,
  VoidCallback? onAddMaterial,
  void Function(String field, Object? value)? onSetField,
  bool metallicEnabled = true,
  Map<String, TextureSlotController>? textureSlots,
}) async {
  tester.view
    ..physicalSize = const Size(800, 1400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: modelerTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MaterialPanel(
            materials: materials,
            activeIndex: activeIndex,
            onAssign: onAssign ?? (_) {},
            onAddMaterial: onAddMaterial ?? () {},
            onSetField: onSetField ?? (_, _) {},
            metallicEnabled: metallicEnabled,
            textureSlots: textureSlots ?? _emptySlots(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('the material list', () {
    testWidgets('shows every material, and marks the active one', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          _material(name: 'Steel'),
          _material(name: 'Rust'),
        ],
        activeIndex: 1,
      );

      expect(find.text('Steel'), findsOneWidget);
      expect(find.text('Rust'), findsOneWidget);
      final Semantics rustRow = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .firstWhere((Semantics s) => s.properties.label == 'Rust');
      expect(rustRow.properties.selected, isTrue);
    });

    testWidgets('tapping a different row assigns it', (
      WidgetTester tester,
    ) async {
      final assigned = <int?>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          _material(name: 'Steel'),
          _material(name: 'Rust'),
        ],
        activeIndex: 0,
        onAssign: assigned.add,
      );

      await tester.tap(find.text('Rust'));
      await tester.pump();

      expect(assigned, <int?>[1]);
    });

    testWidgets('tapping the row already active clears the paint', (
      WidgetTester tester,
    ) async {
      final assigned = <int?>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
        onAssign: assigned.add,
      );

      await tester.tap(find.text('Steel'));
      await tester.pump();

      expect(assigned, <int?>[null]);
    });

    testWidgets('the "Add material" link is always there', (
      WidgetTester tester,
    ) async {
      var added = 0;
      await _pump(
        tester,
        materials: const <ProjectMaterial>[],
        onAddMaterial: () => added++,
      );

      expect(find.text('No materials'), findsOneWidget);
      await tester.tap(find.text('Add material'));
      expect(added, 1);
    });
  });

  group('the active material\'s own fields', () {
    testWidgets('the shader dropdown offers the six built-in models and '
        'edits `lightingModel`', (WidgetTester tester) async {
      final said = <Object?>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Cloth')],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'lightingModel') said.add(value);
        },
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('lightingModelDropdown')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lambert'), findsOneWidget);
      expect(find.text('Toon'), findsOneWidget);
      await tester.tap(find.text('Lambert').last);
      await tester.pumpAndSettle();

      expect(said, <String>['Lambert']);
    });

    testWidgets(
      'a material with no shader field of its own shows PBR selected',
      (WidgetTester tester) async {
        await _pump(
          tester,
          materials: <ProjectMaterial>[_material(name: 'Steel')],
          activeIndex: 0,
        );

        // `EnumField` wraps the actual `DropdownButton` now, so its own key
        // finds the wrapper — the dropdown itself is the sole descendant of
        // that type underneath it.
        final DropdownButton<String> dropdown = tester.widget(
          find.descendant(
            of: find.byKey(const ValueKey<String>('lightingModelDropdown')),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dropdown.value, 'Pbr');
      },
    );

    testWidgets('mat-04\'s own acceptance: Lambert disables metallic', (
      WidgetTester tester,
    ) async {
      final metallic = <double>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Cloth', metallic: 0.2)],
        activeIndex: 0,
        metallicEnabled: false,
        onSetField: (String field, Object? value) {
          if (field == 'metallic') metallic.add(value! as double);
        },
      );

      final metallicFinder = find.byKey(
        const ValueKey<String>('slider-Metallic'),
      );
      final Slider slider = tester.widget(metallicFinder);
      expect(slider.onChanged, isNull);
      expect(slider.onChangeEnd, isNull);

      // Dragging a slider with no handler wired does nothing at all.
      await tester.drag(metallicFinder, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(metallic, isEmpty);
    });

    testWidgets('a metal keeps its metallic slider live', (
      WidgetTester tester,
    ) async {
      final metallic = <double>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel', metallic: 0.2)],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'metallic') metallic.add(value! as double);
        },
      );

      final metallicFinder = find.byKey(
        const ValueKey<String>('slider-Metallic'),
      );
      final Slider slider = tester.widget(metallicFinder);
      expect(slider.onChanged, isNotNull);

      await tester.drag(metallicFinder, const Offset(60, 0));
      await tester.pumpAndSettle();

      // Mutation: call `onSetField` from the slider's continuous `onChanged`
      // instead of only from `onChangeEnd`. One drag, one step of undo.
      expect(metallic, hasLength(1));
    });

    testWidgets('the base colour field edits `baseColor`', (
      WidgetTester tester,
    ) async {
      final said = <List<double>>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(baseColor: Vector4(1, 1, 1, 1)),
          ),
        ],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'baseColor') said.add(value! as List<double>);
        },
      );

      await tester.enterText(find.byType(TextField).first, '5FD4E4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(said, hasLength(1));
      expect(said.single[0], closeTo(0.373, 0.001));
    });

    testWidgets('the emissive field edits `emissive`', (
      WidgetTester tester,
    ) async {
      final said = <List<double>>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Lamp')],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'emissive') said.add(value! as List<double>);
        },
      );

      // The second colour swatch on the panel is emissive's, base colour's
      // own coming first.
      await tester.enterText(find.byType(TextField).at(1), '5FD4E4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(said, hasLength(1));
      expect(said.single, hasLength(3));
    });

    testWidgets(
      'alpha mode offers the three glTF modes and edits `alphaMode`',
      (WidgetTester tester) async {
        final said = <String>[];
        await _pump(
          tester,
          materials: <ProjectMaterial>[_material(name: 'Glass')],
          activeIndex: 0,
          onSetField: (String field, Object? value) {
            if (field == 'alphaMode') said.add(value! as String);
          },
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('alphaModeDropdown')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Blended').last);
        await tester.pumpAndSettle();

        expect(said, <String>['blend']);
      },
    );

    testWidgets('a cutoff slider appears only in mask mode', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(alphaMode: SurfaceAlphaMode.opaque),
          ),
        ],
        activeIndex: 0,
      );
      expect(find.byKey(const ValueKey<String>('slider-Cutoff')), findsNothing);

      await _pump(
        tester,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(alphaMode: SurfaceAlphaMode.mask),
          ),
        ],
        activeIndex: 0,
      );
      expect(
        find.byKey(const ValueKey<String>('slider-Cutoff')),
        findsOneWidget,
      );
    });

    testWidgets('every one of the five texture slots draws its own row', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
        textureSlots: <String, TextureSlotController>{
          'albedo': (
            name: 'rust_albedo.png',
            subtitle: null,
            badge: null,
            thumbnail: null,
            onChoose: () {},
            onClear: () {},
          ),
          'normal': _emptySlot,
          'metallicRoughness': _emptySlot,
          'occlusion': _emptySlot,
          'emissive': _emptySlot,
        },
      );

      expect(find.text('Base colour texture'), findsOneWidget);
      expect(find.text('Normal map'), findsOneWidget);
      expect(find.text('Metallic-roughness map'), findsOneWidget);
      expect(find.text('Occlusion map'), findsOneWidget);
      expect(find.text('Emissive map'), findsOneWidget);
      expect(find.text('rust_albedo.png'), findsOneWidget);
      // Four empty slots, "None" each.
      expect(find.text('None'), findsNWidgets(4));
      // Only the bound slot offers "Clear".
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets(
      'a texture row reads dimensions and weight from textureSlotDisplay',
      (WidgetTester tester) async {
        final TextureSlotDisplay display = textureSlotDisplay(
          EncodedImage(
            bytes: _pngBytes(256, 128, totalBytes: 170 * 1024),
            name: 'albedo.png',
          ),
        );

        await _pump(
          tester,
          materials: <ProjectMaterial>[_material(name: 'Steel')],
          activeIndex: 0,
          textureSlots: <String, TextureSlotController>{
            'albedo': (
              name: display.name,
              subtitle: display.dimensionsText == null
                  ? null
                  : '${display.dimensionsText} · ${display.weightText}',
              badge: display.formatBadge,
              thumbnail: display.thumbnail,
              onChoose: () {},
              onClear: () {},
            ),
            'normal': _emptySlot,
            'metallicRoughness': _emptySlot,
            'occlusion': _emptySlot,
            'emissive': _emptySlot,
          },
        );

        expect(find.text('albedo.png'), findsOneWidget);
        expect(find.text('256×128 · 170 KB'), findsOneWidget);
      },
    );

    testWidgets("the dot reflects the material's own base colour", (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(
              name: 'Rust',
              baseColor: Vector4(0.33, 0.66, 0.11, 1),
            ),
          ),
        ],
      );

      final Finder row = find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == 'Rust',
      );
      final Container dot = tester.widget(
        find.descendant(of: row, matching: find.byType(Container)).first,
      );
      final BoxDecoration decoration = dot.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.color,
        Color.fromRGBO(
          (0.33 * 255).round(),
          (0.66 * 255).round(),
          (0.11 * 255).round(),
          1.0,
        ),
      );
    });

    testWidgets('"Choose…" reaches the caller for the slot it was pressed on', (
      WidgetTester tester,
    ) async {
      var chosen = 0;
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: 0,
        textureSlots: _emptySlots(onChooseAlbedo: () => chosen++),
      );

      await tester.tap(find.text('Choose…').first);
      expect(chosen, 1);
    });

    testWidgets(
      'the advanced section holds emissive strength and double-sided always',
      (WidgetTester tester) async {
        await _pump(
          tester,
          materials: <ProjectMaterial>[_material(name: 'Steel')],
          activeIndex: 0,
        );

        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();

        expect(find.text('Emissive strength'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('doubleSidedCheckbox')),
          findsOneWidget,
        );
        // No map bound to either slot, so neither slider that only means
        // something once one is shows up.
        expect(find.text('Normal scale'), findsNothing);
        expect(find.text('Occlusion strength'), findsNothing);
      },
    );

    testWidgets('normal scale appears in Advanced once a normal map is bound', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(
              normalTexture: const TextureBinding(imageIndex: 0),
            ),
          ),
        ],
        activeIndex: 0,
      );

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('Normal scale'), findsOneWidget);
    });

    testWidgets('double-sided reaches `onSetField`', (
      WidgetTester tester,
    ) async {
      final said = <bool>[];
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Leaf')],
        activeIndex: 0,
        onSetField: (String field, Object? value) {
          if (field == 'doubleSided') said.add(value! as bool);
        },
      );

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('doubleSidedCheckbox')),
      );
      await tester.pump();

      expect(said, <bool>[true]);
    });

    testWidgets('no active material shows no field, only the list', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        materials: <ProjectMaterial>[_material(name: 'Steel')],
        activeIndex: null,
      );

      expect(find.text('Steel'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('Base colour texture'), findsNothing);
    });
  });
}
