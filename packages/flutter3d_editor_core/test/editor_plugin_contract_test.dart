/// The editor's plugin contract beyond commands and palette rows: inspectors
/// built from a plugin's hints, gizmos, importers, asset-browser entries,
/// command arguments an agent is offered, and the `editor:` section of a
/// data plugin.
///
///     dart test test/editor_plugin_contract_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart'
    show
        ColorHint,
        EnumHint,
        LightingModel,
        MaterialDocument,
        RangeHint,
        TextureHint,
        readFmat;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

final class _Scope extends PluginScope {
  _Scope(String id, this.rank)
    : manifest = PluginManifest(
        id: id,
        apiVersion: const PluginApiVersion(1, 0),
      );

  @override
  final PluginManifest manifest;

  @override
  int rank;

  final List<Registration> registrations = <Registration>[];

  @override
  void track(Registration registration) => registrations.add(registration);

  void switchOff() {
    for (final registration in registrations.reversed) {
      registration.cancel();
    }
    registrations.clear();
  }
}

Editing _open() => Editing.parse(
  jsonEncode(<String, Object?>{
    'version': 1,
    'name': 'test',
    'brushes': <Object?>[],
    'lights': <Object?>[],
    'entities': <Object?>[
      <String, Object?>{
        'type': 'boat',
        'at': <double>[1.0, 0.0, 0.0],
        'buoyancy': 2.0,
      },
      <String, Object?>{
        'type': 'torch',
        'at': <double>[4.0, 0.0, 0.0],
      },
    ],
  }),
  path: '/levels/test.json',
);

const ComponentHints _buoyancy = ComponentHints(
  id: 'boats.buoyancy',
  title: 'Buoyancy',
  fields: <FieldHint>[
    FieldHint.number('buoyancy', min: 0, max: 4, defaultValue: 1.0),
    FieldHint.number('drag', min: 0, max: 1, defaultValue: 0.4),
  ],
  entityTypes: <String>{'boat'},
);

/// A gizmo that rings a boat with its buoyancy and lets the ring be pulled.
final class _Ring extends EditorGizmo {
  const _Ring();

  @override
  bool appliesTo(GizmoContext context) => context.entity?.type == 'boat';

  @override
  List<GizmoMark> marksFor(GizmoContext context) => <GizmoMark>[
    GizmoMark.ball(
      context.where,
      radius: context.entity!.number('buoyancy') ?? 1.0,
      handle: 'radius',
    ),
    if (context.selected)
      GizmoMark.line(context.where, context.where + Vector3(0, 2, 0)),
  ];

  @override
  DocumentCommand? dragged(GizmoDrag drag) =>
      SetField('buoyancy', drag.to.distanceTo(drag.target.where));
}

/// An importer that turns a `.boat` text file into a placed boat.
final class _BoatImporter extends EditorImporter {
  const _BoatImporter();

  @override
  String get label => 'Boat hull';

  @override
  List<String> get suffixes => const <String>['.boat'];

  @override
  Future<ImportResult> import(ImportRequest request) async => ImportResult(
    files: <String, Uint8List>{'assets/hulls/${request.name}': request.bytes},
    commands: <DocumentCommand>[
      Place(
        Piece.entity,
        'boat',
        request.at ?? Vector3.zero(),
        properties: <String, Object?>{'hull': 'hulls/${request.name}'},
      ),
    ],
    notes: <String>['read ${request.bytes.length} bytes'],
  );
}

void main() {
  group('hints', () {
    test('a plugin component\'s hints become an inspector section', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).hints.addComponent(_buoyancy);

      final components = inspectorComponents(
        Piece.entity,
        type: 'boat',
        pieces: pieces,
      );
      // Mutation: leave hinted components out of `componentsFor`.
      expect(components.map((c) => c.kind), contains('boats.buoyancy'));
      final section = components.firstWhere((c) => c.kind == 'boats.buoyancy');
      expect(section.title, 'Buoyancy');
      expect(section.hintFor('drag')?.max, 1.0);
      // A torch does not float.
      expect(
        inspectorComponents(
          Piece.entity,
          type: 'torch',
          pieces: pieces,
        ).map((c) => c.kind),
        isNot(contains('boats.buoyancy')),
      );
      // What a boat lacks is offered at the hint's default.
      expect(
        pieces.offersFor(Piece.entity, const <String>['buoyancy'], type: 'boat'),
        <String, Object?>{'drag': 0.4},
      );
    });

    test('the host finds the hint registry through the editor pieces', () {
      final pieces = EditorPieces();
      // Mutation: drop `companions` from EditorPieces.
      expect(pieces.companions.whereType<EditorHintRegistry>(), hasLength(1));
      final scoped = pieces.companions
          .whereType<EditorHintRegistry>()
          .single
          .forPlugin(_Scope('boats', 0));
      scoped.addComponent(_buoyancy);
      expect(pieces.hints.components.single.id, 'boats.buoyancy');
    });

    test('a component id and a model are namespaced; a type is not', () {
      final pieces = EditorPieces();
      final boats = pieces.forPlugin(_Scope('boats', 0)).hints;
      boats.addComponent(const ComponentHints(id: 'wake', title: 'Wake'));
      expect(pieces.hints.components.single.id, 'boats.wake');
      // Mutation: accept any dotted id.
      expect(
        () => boats.addComponent(
          const ComponentHints(id: 'sails.cloth', title: 'Cloth'),
        ),
        throwsArgumentError,
      );
      boats.addMaterial(const MaterialHints(model: 'varnish'));
      expect(pieces.hints.materials.single.model, 'boats.varnish');
      boats.addEntityKind(const EntityKindHints(type: 'boat'));
      expect(pieces.hints.entityKinds.single.type, 'boat');
      expect(
        () => pieces
            .forPlugin(_Scope('ships', 1))
            .hints
            .addEntityKind(const EntityKindHints(type: 'boat')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('plugin "boats"'),
          ),
        ),
      );
    });

    test('switching a plugin off withdraws its hints', () {
      final pieces = EditorPieces();
      final scope = _Scope('boats', 0);
      pieces.forPlugin(scope).hints
        ..addComponent(_buoyancy)
        ..addEntityKind(const EntityKindHints(type: 'boat'));
      scope.switchOff();
      // Mutation: do not track the hint registrations.
      expect(pieces.hints.components, isEmpty);
      expect(pieces.hints.entityKinds, isEmpty);
    });

    test('an entity kind\'s fields are a section, its components join', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).hints
        ..addComponent(
          const ComponentHints(
            id: 'boats.wake',
            title: 'Wake',
            fields: <FieldHint>[FieldHint.toggle('foam', defaultValue: true)],
          ),
        )
        ..addEntityKind(
          const EntityKindHints(
            type: 'boat',
            label: 'Boat',
            fields: <FieldHint>[
              FieldHint.choice('rig', <String>['sloop', 'ketch']),
            ],
            components: <String>{'boats.wake'},
          ),
        );
      final kinds = inspectorComponents(
        Piece.entity,
        type: 'boat',
        pieces: pieces,
      ).map((c) => c.kind);
      expect(kinds, containsAll(<String>['type:boat', 'boats.wake']));
      // A component with no types of its own shows only where a kind names
      // it, not on every entity.
      expect(
        inspectorComponents(
          Piece.entity,
          type: 'torch',
          pieces: pieces,
        ).map((c) => c.kind),
        isNot(contains('boats.wake')),
      );
      expect(
        pieces.fieldHint(Piece.entity, 'rig', type: 'boat')?.choices,
        <String>['sloop', 'ketch'],
      );
    });

    test('a hinted entity kind is offered in the palette', () {
      final pieces = EditorPieces();
      pieces
          .forPlugin(_Scope('boats', 0))
          .hints
          .addEntityKind(
            const EntityKindHints(
              type: 'boat',
              label: 'Boat',
              tint: LinearColor(0.2, 0.4, 1.0),
              fields: <FieldHint>[
                FieldHint.number('buoyancy', defaultValue: 1.0),
              ],
            ),
          );
      // Mutation: build palette rows from explicit entries only.
      final entry = pieces.paletteEntries.single;
      expect(entry.type, 'boat');
      expect(entry.label, 'Boat');
      expect(entry.properties, <String, Object?>{'buoyancy': 1.0});
      expect(entry.tint!.b, closeTo(1.0, 1e-9));
    });

    test('a field refuses the wrong shape and takes a value past its ends', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).hints.addComponent(_buoyancy);
      // Mutation: answer null from `refusalOf` for every value.
      expect(
        pieces.refusalOf(Piece.entity, 'buoyancy', 'deep', type: 'boat'),
        contains('number'),
      );
      expect(
        pieces.refusalOf(Piece.entity, 'buoyancy', 9.0, type: 'boat'),
        isNull,
      );
      expect(
        pieces.refusalOf(Piece.entity, 'unhinted', 'x', type: 'boat'),
        isNull,
      );
    });

    test('a plugin lit model\'s parameters have material hints', () {
      final pieces = EditorPieces();
      pieces
          .forPlugin(_Scope('acme', 0))
          .hints
          .addMaterial(
            const MaterialHints(
              model: 'velvet',
              fields: <FieldHint>[
                FieldHint.number('sheen', min: 0, max: 1, step: 0.05),
                FieldHint.color('sheenColor'),
                FieldHint.choice('weave', <String>['plain', 'twill']),
                FieldHint.asset('pile', suffixes: <String>['.png']),
              ],
            ),
          );
      // Mutation: look the model up without its namespace.
      expect(pieces.materialHint('velvet', 'sheen'), isNull);
      final sheen = pieces.materialHint('acme.velvet', 'sheen')!;
      expect(sheen.kind, isA<RangeHint>());
      expect((sheen.kind as RangeHint).step, 0.05);
      expect(
        pieces.materialHint('acme.velvet', 'sheenColor')!.kind,
        isA<ColorHint>(),
      );
      expect(
        (pieces.materialHint('acme.velvet', 'weave')!.kind as EnumHint).values
            .map((v) => v.value),
        <String>['plain', 'twill'],
      );
      expect(
        (pieces.materialHint('acme.velvet', 'pile')!.kind as TextureHint)
            .extensions,
        <String>['.png'],
      );
    });

    test('a material file naming a plugin\'s stage gets its hints', () {
      final pieces = EditorPieces();
      // A stage name cannot hold a dot, so `<namespace>_<name>` is taken.
      pieces
          .forPlugin(_Scope('acme', 0))
          .hints
          .addMaterial(
            const MaterialHints(
              model: 'acme_Velvet',
              fields: <FieldHint>[FieldHint.number('sheen', min: 0, max: 1)],
            ),
          );
      expect(pieces.hints.materials.single.model, 'acme_Velvet');
      final file = readFmat(
        Uint8List.fromList(utf8.encode('{"fmat": 1, "name": "cloth"}')),
      );
      final velvet = MaterialDocument(
        surface: file.surface,
        lighting: const LightingModel('Velvet', 'acme_Velvet'),
      );
      // Mutation: look the plugin up by the model's label.
      expect(
        materialDocumentHint(velvet, 'sheen', pieces: pieces)?.kind,
        isA<RangeHint>(),
      );
      expect(materialDocumentHint(velvet, 'sheen'), isNull);
      expect(
        () => pieces
            .forPlugin(_Scope('acme', 0))
            .hints
            .addMaterial(const MaterialHints(model: 'other_Velvet')),
        returnsNormally,
        reason: 'a bare name is prefixed, not refused',
      );
      expect(pieces.hints.materials.last.model, 'acme.other_Velvet');
    });
  });

  group('field hints', () {
    test('travel through JSON as a data plugin writes them', () {
      const hint = FieldHint.number(
        'sheen',
        label: 'Sheen',
        min: 0,
        max: 1,
        step: 0.05,
        unit: Unit.percent,
        defaultValue: 0.5,
      );
      final back = FieldHint.fromJson(jsonDecode(jsonEncode(hint.toJson())));
      expect(back.toJson(), hint.toJson());
      expect(back.unit, Unit.percent);
      // A kind a later editor wrote opens as text.
      expect(
        FieldHint.fromJson(<String, Object?>{'key': 'x', 'kind': 'curve'}).kind,
        FieldKind.text,
      );
      expect(
        () => FieldHint.fromJson(<String, Object?>{'kind': 'number'}),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('give a JSON schema for a tool argument', () {
      expect(
        const FieldHint.choice('rig', <String>['sloop', 'ketch']).jsonSchema,
        containsPair('enum', <String>['sloop', 'ketch']),
      );
      expect(
        const FieldHint.vector3('at').jsonSchema,
        containsPair('minItems', 3),
      );
      expect(
        const FieldHint.integer('count', min: 1).jsonSchema,
        containsPair('minimum', 1.0),
      );
    });
  });

  group('commands', () {
    test('a command\'s argument hints are its schema; a listener hears it', () {
      final pieces = EditorPieces();
      var heard = 0;
      final listening = pieces.listen(() => heard++);
      final scope = _Scope('boats', 0);
      pieces
          .forPlugin(scope)
          .addCommand(
            'sink',
            (Map<String, Object?> arguments) => null,
            description: 'Sink the selected boat.',
            arguments: const <FieldHint>[
              FieldHint.number('depth', min: 0, defaultValue: 1.0),
            ],
          );
      // Mutation: drop `arguments` on the way into the store.
      expect(pieces.argumentsOf('boats.sink').single.key, 'depth');
      expect(pieces.pluginCommands.single.name, 'boats.sink');
      expect(pieces.pluginCommands.single.plugin, 'boats');
      expect(heard, 1);
      scope.switchOff();
      expect(heard, 2);
      listening.cancel();
    });
  });

  group('gizmos', () {
    test('a gizmo marks the things it applies to and a drag is a command', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addGizmo('ring', const _Ring());
      final editing = _open()
        ..kind = Piece.entity
        ..selected = 0;

      final marks = pieces.marksFor(
        editing.level,
        selected: <Picked>[(kind: Piece.entity, index: 0)],
      );
      // Mutation: ignore `appliesTo`, so the torch is ringed too.
      expect(marks.map((m) => m.index), <int>[0, 0]);
      expect(marks.first.gizmo, 'boats.ring');
      expect(marks.first.mark.shape, GizmoShape.ball);
      expect(marks.first.mark.size.x, closeTo(4.0, 1e-9));
      expect(marks.last.mark.shape, GizmoShape.line);

      final ring = marks.first;
      final command = pieces.dragged(
        ring,
        editing.level,
        from: Vector3(3.0, 0.0, 0.0),
        to: Vector3(4.0, 0.0, 0.0),
      );
      expect(command, isA<SetField>());
      expect(editing.history.run(command!), isTrue);
      expect(editing.level.entities.first.number('buoyancy'), 3.0);

      // A line has no handle and is not dragged.
      expect(
        pieces.dragged(
          marks.last,
          editing.level,
          from: Vector3.zero(),
          to: Vector3(1, 0, 0),
        ),
        isNull,
      );
    });

    test('a ray finds the handle of a mark', () {
      final pieces = EditorPieces();
      pieces.forPlugin(_Scope('boats', 0)).addGizmo('ring', const _Ring());
      final marks = pieces.marksFor(_open().level);
      // Mutation: test the line too, which has no handle.
      final hit = markUnder(marks, Vector3(1.0, 0.0, -10.0), Vector3(0, 0, 1));
      expect(hit?.mark.handle, 'radius');
      expect(markUnder(marks, Vector3(1, 50, -10), Vector3(0, 0, 1)), isNull);
    });
  });

  group('importers and the asset browser', () {
    test(
      'an importer is found by suffix and its result says what to do',
      () async {
        final pieces = EditorPieces();
        pieces
            .forPlugin(_Scope('boats', 0))
            .addImporter('hull', const _BoatImporter());
        // Mutation: compare suffixes case-sensitively.
        final found = pieces.importerFor('/downloads/Skiff.BOAT');
        expect(found?.name, 'boats.hull');
        expect(pieces.importerFor('/downloads/skiff.glb'), isNull);

        final editing = _open();
        final result = await found!.importer.import(
          ImportRequest(
            path: '/downloads/skiff.boat',
            bytes: Uint8List.fromList(utf8.encode('hull')),
            level: editing.level,
            at: Vector3(0.0, 0.0, 5.0),
          ),
        );
        expect(result.files.keys.single, 'assets/hulls/skiff.boat');
        expect(editing.history.run(result.commands.single), isTrue);
        expect(editing.level.entities.last.type, 'boat');
      },
    );

    test('an asset entry names what a file is and what dropping it does', () {
      final pieces = EditorPieces();
      pieces
          .forPlugin(_Scope('boats', 0))
          .addAssetEntry(
            'hulls',
            AssetBrowserEntry(
              label: 'Hull',
              suffixes: const <String>['.boat'],
              place: (AssetPlacement placement) => Place(
                Piece.entity,
                'boat',
                placement.at,
                properties: <String, Object?>{'hull': placement.path},
              ),
            ),
          );
      // Mutation: put plugin entries after the built-in ones, so a plugin
      // cannot claim a suffix the editor lists too.
      final entry = pieces.assetEntryFor('hulls/skiff.boat')!;
      expect(entry.name, 'boats.hulls');
      expect(pieces.assetEntryFor('levels/one.json')?.name, 'level');
      final place = entry.entry.place!(
        AssetPlacement(
          path: 'hulls/skiff.boat',
          at: Vector3(2, 0, 2),
          level: _open().level,
        ),
      );
      expect(place, isA<Place>());
      expect(pieces.assetEntryFor('notes.txt'), isNull);
    });
  });

  group('the editor section of a data plugin', () {
    test(
      'reads hints and palette rows, writes them back and installs them',
      () {
        final written = <String, Object?>{
          'components': <Object?>[_buoyancy.toJson()],
          'entityKinds': <Object?>[
            const EntityKindHints(type: 'boat', label: 'Boat').toJson(),
          ],
          'materials': <Object?>[
            const MaterialHints(
              model: 'boats.varnish',
              fields: <FieldHint>[FieldHint.number('gloss')],
            ).toJson(),
          ],
        };
        const context = DataSectionContext(plugin: 'boats');
        final section = editorSection.read(
          DataSectionRead(written, context: context),
        );
        expect(editorSection.name, 'editor');
        // Mutation: write the entity kinds back under `kinds`.
        expect(
          jsonDecode(jsonEncode(editorSection.write(section))),
          jsonDecode(jsonEncode(written)),
        );
        expect(
          () => editorSection.read(
            DataSectionRead(<String, Object?>{
              'components': 3,
            }, context: context),
          ),
          throwsA(isA<Flutter3dFormatException>()),
        );

        final pieces = EditorPieces();
        final notes = <String>[];
        editorSection.install(
          DataSectionInstall(
            section,
            host: _Host(pieces, _Scope('boats', 0)),
            context: DataSectionContext(plugin: 'boats', note: notes.add),
          ),
        );
        expect(pieces.hints.components.single.id, 'boats.buoyancy');
        expect(pieces.hints.entityKinds.single.type, 'boat');
        expect(pieces.hints.materials.single.model, 'boats.varnish');

        // An engine with no editor leaves the section out and says so.
        editorSection.install(
          DataSectionInstall(
            section,
            host: _Host(null, _Scope('boats', 0)),
            context: DataSectionContext(plugin: 'boats', note: notes.add),
          ),
        );
        expect(notes.single, contains('no editor'));
      },
    );
  });

  group('project plugins', () {
    test('the data plugins a project keeps are found under assets/plugins', () {
      // Mutation: accept a `.f3dplugin` anywhere in the project.
      expect(
        projectPluginPaths(<String>[
          'assets/plugins/boats.f3dplugin',
          'assets/plugins/sails/sails.f3dplugin',
          'assets/levels/one.json',
          'build/assets/plugins/boats.f3dplugin',
          'notes/old.f3dplugin',
        ]),
        <String>[
          'assets/plugins/boats.f3dplugin',
          'assets/plugins/sails/sails.f3dplugin',
        ],
      );
    });
  });
}

/// A plugin host with the editor's pieces, or with none.
final class _Host extends PluginHost {
  _Host(this._pieces, this._scope);

  final EditorPieces? _pieces;
  final _Scope _scope;

  @override
  PluginManifest get manifest => _scope.manifest;

  @override
  PluginApiVersion get apiVersion => const PluginApiVersion(1, 0);

  @override
  String? get backend => null;

  @override
  LoopRegistry get loop => throw UnimplementedError();

  @override
  EventRegistry get events => throw UnimplementedError();

  @override
  R registry<R extends PluginRegistry>() =>
      maybeRegistry<R>() ?? (throw StateError('no $R'));

  @override
  R? maybeRegistry<R extends PluginRegistry>() {
    final pieces = _pieces;
    if (pieces == null) return null;
    for (final registry in <PluginRegistry>[pieces, ...pieces.companions]) {
      if (registry is R) return registry.forPlugin(_scope) as R;
    }
    return null;
  }
}
