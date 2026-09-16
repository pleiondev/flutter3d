/// `_ModelerScreenState`'s own tool dispatch: what a click, a drag, a rail
/// button or a panel edit turns into on the history.
///
/// **A `part of 'main.dart'`, not a file of its own**, for the reason every
/// file in this directory is: every method here reaches `_cubit`, `_history`,
/// `_editMesh` or `setState` directly, and a `part` is what lets it keep
/// doing that as an `extension` method rather than turning every one of
/// those into a parameter or a public setter. See `device.dart` in this same
/// directory for the fuller version of this rationale.
///
/// `setState` is `@protected` on `State`, and the analyzer's check for that
/// annotation does not recognise an extension method on `_ModelerScreenState`
/// as code written inside the class — even though this file is, syntactically,
/// exactly that. The call itself is correct; only the check misfires.
// ignore_for_file: invalid_use_of_protected_member
part of '../../main.dart';

extension _Interactions on _ModelerScreenState {
  /// A click in the mesh mode: what element is under it, at the level the
  /// sub-mode names.
  void _pickedElement(
    PickingView view,
    Offset at,
    PointerDeviceKind pointer, {
    required ElementPickIntent intent,
  }) {
    final MeshPicker? picker = _elementPicker;
    if (picker == null) return;
    // `ux-28`: a loop and a ring are walks from an edge, so they ask the
    // picker for an edge whatever level the sub-mode is in — aiming at the
    // edge is the gesture, and being in face mode does not make it a
    // different one. `SelectEdgeLoop` answers at edge level and the
    // selection follows it there, which is what `selection_commands.dart`
    // already documents as "the level travels with the elements".
    if (intent.isWalk) {
      final Selection edge = pickElementAt(
        picker,
        view,
        at: at,
        pointer: pointer,
        level: ElementLevel.edge,
      );
      final int? half = edge.ids.isEmpty ? null : edge.ids.first;
      if (half == null) return;
      _runSelection(
        intent == ElementPickIntent.ring
            ? SelectEdgeRing(half)
            : SelectEdgeLoop(half),
      );
      return;
    }
    final picked = pickElementAt(
      picker,
      view,
      at: at,
      pointer: pointer,
      level: levelOf(_submode),
    );
    setState(() {
      final was = _history.selection;
      // Shift takes an element back out rather than only ever adding: dropping
      // one face from a selection of forty is otherwise thirty-nine clicks.
      final Selection next =
          intent == ElementPickIntent.toggle && was.level == picked.level
          ? was.asMeshSelection.toggle(picked)
          : picked;
      _history.selection = was.copyWith(
        mode: SelectionMode.mesh,
        level: next.level,
        elements: next.ids.toList(),
      );
      _cubit.say(null);
    });
  }

  /// What the pointer is resting on inside the mesh — `ux-28`'s own
  /// highlight, which is the half of "click here" that happens before the
  /// click.
  ///
  /// **The same `pickElementAt` a click runs, and that is affordable on
  /// purpose.** Its own doc comment says it: face mode, which is where a
  /// modeller spends most of the session, is one raycast against the tree
  /// and nothing else, and the function was written knowing it would be
  /// called on every hover as well as on every click.
  ///
  /// `setState` only when the answer changed. A hover fires on every pixel
  /// of travel and most of those pixels are over the face the one before
  /// was, so rebuilding for each of them is sixty frames a second spent
  /// redrawing the same highlight.
  void _hoveredElement(
    PickingView view,
    Offset? at,
    PointerDeviceKind pointer,
  ) {
    final MeshPicker? picker = _elementPicker;
    final Selection? found = picker == null || at == null
        ? null
        : pickElementAt(
            picker,
            view,
            at: at,
            pointer: pointer,
            level: levelOf(_submode),
          );
    final Selection? next = found == null || found.ids.isEmpty ? null : found;
    if (_sameHover(next, _hoveredElements)) return;
    setState(() => _hoveredElements = next);
  }

  /// Whether two hovers name the same element.
  static bool _sameHover(Selection? now, Selection? was) {
    if (now == null) return was == null;
    if (was == null || was.level != now.level) return false;
    return now.ids.length == was.ids.length && now.ids.every(was.contains);
  }

  /// Presses a rail button.
  void _ranTool(String id) {
    // `ux-29`: Extrude and Bevel land at the guess and then follow the
    // pointer, so pressing either is the start of a gesture rather than the
    // whole of it. Before the `commandFor` branch below, which is where they
    // used to be answered and where they still are for a caller with no
    // pointer — `startValueDrag` refuses with nothing selected, and the
    // ordinary path then gives the same refusal it always did.
    if (DraggedValue.forTool(id) != null &&
        _transformSession.startValueDrag(id, viewportHeight: _viewportHeight)) {
      _cubit.tool(id);
      setState(() {});
      return;
    }
    // `ux-28`: the lasso arms and waits for a drag, exactly as Select does.
    if (kDragTools.contains(id) ||
        id.endsWith('.select') ||
        id == 'mesh.lasso') {
      // Arming rather than acting: these wait for a pointer.
      _cubit.tool(id);
      // `ux-11`: under the modal preset the key does not arm and wait for a
      // button — it starts the transform there and then, and the pointer
      // drives it with nothing held. Which of the two happens is the
      // person's own setting, because the two schools genuinely disagree
      // about it and neither is wrong.
      if (_settings.transformStart == TransformStart.modalOnPress) {
        _transformSession.startOnPress(id);
      }
      return;
    }
    if (id == 'mesh.linked') {
      // `ux-28`: "what is linked to what is under the cursor". `SelectLinked`
      // follows the selection, so the element under the pointer becomes the
      // selection first — which is also exactly what clicking it would have
      // done, so the two-step is the gesture written out rather than a
      // second meaning for the key.
      //
      // With the pointer somewhere else — the rail, the palette, a tablet
      // where there is no hover at all — it follows whatever is selected.
      // That is the same command answering a slightly smaller question
      // rather than a refusal, and a refusal is what a button pressed from
      // the rail would otherwise always get.
      if (_hoveredElements case final Selection under
          when under.ids.isNotEmpty) {
        setState(() {
          _history.selection = _history.selection.copyWith(
            mode: SelectionMode.mesh,
            level: under.level,
            elements: under.ids.toList(),
          );
        });
      }
      _runSelection(const SelectLinked());
      return;
    }
    if (id == 'object.lathe') {
      // A dialog, not a command run straight from the rail: `AddLathe`
      // needs a profile nobody has drawn yet, so this arms the button and
      // opens `lathe_dialog.dart` rather than going through `commandFor`,
      // which only ever answers with a command ready to run immediately.
      _cubit.tool(id);
      unawaited(_openLatheDialog());
      return;
    }
    // `anim-18`'s own three: none of them is a plain `ModelCommand`
    // `commandFor` could answer with immediately — `import` opens a file
    // picker, `autoMap` only touches the local bone-map field, and `apply`
    // runs a background job — so each arms the button itself, the same
    // "not through `commandFor`" shape `object.lathe` above already uses.
    if (id == 'retarget.import') {
      _cubit.tool(id);
      unawaited(_importRetargetSource());
      return;
    }
    if (id == 'retarget.autoMap') {
      _cubit.tool(id);
      _autoMapRetarget();
      return;
    }
    if (id == 'retarget.apply') {
      _cubit.tool(id);
      unawaited(_applyRetarget());
      return;
    }
    if (id == 'pose.autoRig') {
      // `S8`'s own row: a dialog, not a command run straight from the rail —
      // the same reason `object.lathe` above arms the button and opens its
      // own dialog rather than going through `commandFor`.
      _cubit.tool(id);
      unawaited(_openAutorigDialog());
      return;
    }
    final ModelCommand? command = commandFor(
      id,
      activeObject: _history.selection.activeObject,
      editMesh: _editMesh,
    );
    if (command == null) {
      _cubit.tool(id);
      return;
    }
    _cubit
      ..tool(id)
      ..ran(command);
  }

  /// A rectangle was dragged and let go.
  ///
  /// **The rules are `applyBox`'s and they are the same rules a click
  /// follows** — shift adds, control takes away, neither replaces — because a
  /// modifier that means one thing for a click and another for a box is a
  /// modifier nobody can rely on.
  void _boxed(SelectionBox box, PickingView view) {
    final was = _history.selection;
    if (was.mode == SelectionMode.mesh) {
      final MeshPicker? picker = _elementPicker;
      if (picker == null) return;
      // `ux-28`: the same three modes and the same ids, decided by the loop
      // rather than by the rectangle when the person drew one.
      final Selection caught = box.isLasso
          ? pickElementsInLoop(
              picker,
              view,
              bounds: box.rect,
              encloses: box.encloses,
              level: levelOf(_submode),
            )
          : pickElementsIn(
              picker,
              view,
              rect: box.rect,
              level: levelOf(_submode),
            );
      final Set<int> next = applyBox<int>(
        was.elements.toSet(),
        caught.ids.toSet(),
        mode: box.mode,
      );
      setState(() {
        _history.selection = was.copyWith(
          elements: next.toList()..sort(),
          level: caught.level,
        );
        _cubit.say(null);
      });
      return;
    }

    // Objects, by the middle of what they cover rather than by every vertex in
    // them. **The middle and not an overlap**, which is what every modeller
    // does and is the more useful of the two: a box drawn across a crowded
    // scene to catch the three props in it should not also catch the floor
    // whose bounds run under all of them. Through the same frustum the element
    // picker uses, so the two answer the same question about one rectangle.
    final state = _state;
    if (state is! ModelerReady) return;
    final sync = state.stage.sync;
    if (sync == null) return;
    // A rectangle with no area — a drag that never left one axis — reaches
    // here as an ordinary release, not a mistake to refuse. `frustumOverBox`
    // answers it the same way `pickElementsIn` already does for the
    // mesh-mode branch above: nothing caught, rather than letting
    // `frustumOver`'s own divide-by-zero guard throw into the pointer
    // handler.
    final vm.Frustum? frustum = frustumOverBox(view, box.rect);
    final Set<int> caught = frustum == null
        ? const <int>{}
        : <int>{
            for (final ModelObject object in _history.project.objects)
              if (sync.nodeOf(object.id) case final MeshNode node)
                if (frustum.containsVector3(node.worldBounds.center)) object.id,
          };
    final Set<int> next = applyBox<int>(
      was.objects.toSet(),
      caught,
      mode: box.mode,
    );
    setState(() {
      _history.selection = was.copyWith(
        mode: SelectionMode.object,
        objects: next.toList(),
      );
      _cubit.say(null);
    });
  }

  /// Runs a selection command.
  ///
  /// **Through the history like everything else**, which is the point of
  /// `doc-32n`: a selection made by mistake is one press of ⌘Z away, the
  /// journal records what was selected when a command ran, and an agent
  /// driving the modeller can ask for it by name.
  void _runSelection(ModelCommand command) => _cubit.ran(command);

  /// Nine numbers typed into the panel.
  ///
  /// **What command this becomes is `transform_dispatch.dart`'s own
  /// question, not this file's.** A position or a rotation edit is read as a
  /// difference from what the panel showed a moment before and handed to
  /// `MoveBy`/`RotateBy`, which is what makes [_pivot] and [_space] mean
  /// anything for more than one object selected; a scale edit still sets the
  /// held object alone, for the reason that file's own doc argues. Either way
  /// the same number typed back is the same fields handed in twice, which
  /// `transformCommandFor` reads as nothing changed rather than a move by
  /// zero.
  void _setTransform(int id, TransformFields to) {
    final held = _history.project[id];
    if (held == null) return;
    final decided = transformCommandFor(
      heldId: id,
      from: transformFieldsOf(held.transform),
      to: to,
      pivot: transformPivotOf(_pivot),
      space: _space,
    );
    if (decided.refused case final String said) {
      _cubit.say(said);
      return;
    }
    if (decided.command case final ModelCommand command) {
      _cubit.ran(command);
    }
  }

  /// The material list's own tap: paint the held object with that row.
  /// Null is the "Unassign" button beside the list — `ux-40`.
  void _assignMaterial(int id, int? to) =>
      _cubit.ran(AssignMaterial(id: id, to: to));

  /// `ux-40`: "Add material" paints the selection with what it made.
  ///
  /// **Nobody adds a material to leave it on nothing.** The row added and
  /// then assigned by hand was two steps to undo and a table row left behind
  /// if only one of them was; `AddMaterial.assignTo` makes it one command,
  /// and with nothing selected it is the plain add it always was.
  void _addMaterial() =>
      _cubit.ran(AddMaterial(assignTo: _history.selection.activeObject));

  /// `mat-34d`'s own scene-mode wiring, over `mat-23`'s own commands.
  void _selectLight(int index) => setState(() => _selectedLight = index);

  /// `ux-23`: above the model rather than inside it.
  ///
  /// **A light at the origin is a light inside the cube**, which is where
  /// every new one landed: the viewport showed no change at all, and the
  /// first thing anybody had to do after adding one was work out why. Above
  /// the top of the bounds and back towards the camera is where a key light
  /// goes, and it is where the handle a person drags is visible.
  ///
  /// Half the model's own height above it rather than a fixed distance: a
  /// scanned head two hundred metres tall and a cube of one metre both get a
  /// light that reads as being above the thing.
  void _addLight() {
    final ModelerState state = _state;
    final vm.Aabb3? bounds = state is ModelerReady
        ? state.stage.subjectBounds()
        : null;
    if (bounds == null) {
      _cubit.ran(const AddLight());
      return;
    }
    final vm.Vector3 middle = bounds.center;
    final vm.Vector3 span = bounds.max - bounds.min;
    final double reach = math.max(span.length * 0.5, 1.0);
    _cubit.ran(
      AddLight(
        at: vm.Vector3(middle.x, bounds.max.y + reach, middle.z + reach),
      ),
    );
  }

  void _removeLight(int index) {
    _cubit.ran(RemoveLight(index));
    if (_selectedLight == index) setState(() => _selectedLight = null);
  }

  void _setLightType(int index, ProjectLightType type) =>
      _cubit.ran(SetLightField(index: index, field: 'type', value: type.name));

  void _setLightIntensity(int index, double value) =>
      _cubit.ran(SetLightField(index: index, field: 'intensity', value: value));

  void _setLightRange(int index, double value) =>
      _cubit.ran(SetLightField(index: index, field: 'range', value: value));

  void _setLightShadow(int index, bool value) => _cubit.ran(
    SetLightField(index: index, field: 'castsShadow', value: value),
  );

  void _setLightCone(int index, double value) => _cubit.ran(
    SetLightField(index: index, field: 'outerConeAngle', value: value),
  );

  void _setSceneShadows(bool value) =>
      _cubit.ran(SetSceneLightingField(field: 'shadows', value: value));

  void _setEnvironment(SceneEnvironmentPreset preset) =>
      _cubit.ran(SetEnvironment(preset));

  void _setAmbient(double value) => _cubit.ran(
    SetSceneLightingField(field: 'ambientIntensity', value: value),
  );

  void _setBloom(bool value) =>
      _cubit.ran(SetSceneLightingField(field: 'bloomEnabled', value: value));

  void _setExposure(double value) =>
      _cubit.ran(SetSceneLightingField(field: 'exposure', value: value));

  /// `anim-07`'s own two commands: a diamond finished a drag in
  /// `TimelinePanel`, or "Add" was pressed under `ActionsList`.
  void _moveKeys(MoveKeys command) => _cubit.ran(command);

  void _addClip() => _cubit.ran(const AddClip());

  void _setMaterialField(int index, String field, Object? value) =>
      _cubit.ran(SetMaterialField(index: index, field: field, value: value));

  void _setModifierField(int id, int index, String field, Object? value) =>
      _cubit.ran(
        SetModifierField(id: id, index: index, field: field, value: value),
      );

  void _clearTexture(int index, String slot) =>
      _cubit.ran(SetTexture(materialIndex: index, slot: slot));

  /// `TextureGraphPanel`'s own "Add" menu, for the material at
  /// [materialIndex].
  void _addTextureNode(
    int materialIndex,
    String kind,
    Map<String, Object?> fields,
    (double x, double y) position,
  ) => _cubit.ran(
    AddNode(
      materialIndex: materialIndex,
      kind: kind,
      fields: fields,
      position: position,
    ),
  );

  void _linkTextureNode(
    int materialIndex,
    int nodeId,
    String input,
    int from,
  ) => _cubit.ran(
    Link(
      materialIndex: materialIndex,
      nodeId: nodeId,
      input: input,
      from: from,
    ),
  );

  void _unlinkTextureNode(int materialIndex, int nodeId, String input) => _cubit
      .ran(Unlink(materialIndex: materialIndex, nodeId: nodeId, input: input));

  void _setTextureNodeField(
    int materialIndex,
    int nodeId,
    String field,
    Object? value,
  ) => _cubit.ran(
    SetNodeField(
      materialIndex: materialIndex,
      nodeId: nodeId,
      field: field,
      value: value,
    ),
  );

  void _moveTextureNode(int materialIndex, int nodeId, double x, double y) =>
      _cubit.ran(
        MoveNode(materialIndex: materialIndex, nodeId: nodeId, x: x, y: y),
      );

  void _removeTextureNode(int materialIndex, int nodeId) =>
      _cubit.ran(RemoveNode(materialIndex: materialIndex, nodeId: nodeId));

  /// The texture graph's own bake button — 2048², `TextureGraphPanel`'s own
  /// button label. [BakeTextureGraph.apply] runs to completion inline (see
  /// its own doc comment), so this is a plain command like any other rather
  /// than a background job.
  void _bakeTextureGraph(int materialIndex) =>
      _cubit.ran(BakeTextureGraph(materialIndex: materialIndex, size: 2048));

  /// Opens a picker for an image and points one of a material's five texture
  /// slots at it — `mat-04`'s own row generalises `mat-04a-n`'s base colour
  /// slot alone over every name [SetTexture.slot] takes.
  ///
  /// **Two commands, two steps of history.** [AddImage] interns the bytes —
  /// or reuses the row a duplicate already sits in — and [SetTexture] is the
  /// only command that can then name the slot; there is no single command
  /// that does both, so a texture pick is honestly two edits rather than one
  /// pretending to be one.
  Future<void> _chooseTexture(int materialIndex, String slot) async {
    final PickedFile? file = await openImage();
    if (file == null) return;
    if (!_cubit.ran(AddImage(bytes: file.bytes, imageName: file.name))) {
      return;
    }
    final int? index = indexOfImageBytes(_history.project.images, file.bytes);
    if (index == null) return;
    _cubit.ran(
      SetTexture(materialIndex: materialIndex, slot: slot, imageIndex: index),
    );
  }

  /// The operation card's number was dragged.
  void _amend(ModelCommand to) {
    final said = _history.amend(to);
    if (said != null) {
      _cubit.say(said);
      return;
    }
    _cubit.documentMoved(said: to.says);
  }

  /// ⌘Z and ⇧⌘Z.
  void _undo() => _cubit.undo();

  void _redo() => _cubit.redo();

  /// `tut-16`'s own "Undo agent steps" button, screen 26's own panel.
  void _undoAgentSteps() => _cubit.undoAgentSteps();

  /// What a click in the viewport did to the selection.
  ///
  /// The rules are all in `applyPick`, which is where they can be read and
  /// tested without a window; this is the seam that gives it the two things it
  /// cannot know — what is selected now, and whether shift was down.
  void _picked(PickResult pick, {required bool extend}) {
    final state = _state;
    if (state is! ModelerReady) return;
    final sync = state.stage.sync;
    if (sync == null) return;

    // The renderer answers with the leaf it rasterised; the document speaks in
    // ids. `SceneSync` is the only place that knows which is which, and a
    // second map here would be a second thing to keep in step.
    final int? found = switch (pick) {
      PickedObject(:final node) => sync.objectOf(node),
      // The viewport's own furniture. Not "nothing": clicking a gizmo's arrow
      // is the first half of a drag of the very object that is selected, and
      // clearing there would delete the selection out from under it.
      PickedService() => null,
      PickedNothing() => null,
    };
    // `ux-14`: a locked object does not answer the pointer. Read as "nothing
    // was hit" rather than dropped outright, so a bare click on the floor
    // still clears the selection — which is what a click on the background
    // does, and a locked floor is background as far as a pointer is
    // concerned.
    final int? id = found != null && (state.project[found]?.locked ?? false)
        ? null
        : found;
    final was = _history.selection;
    final List<int>? next = nextSelection(
      id: id,
      isService: pick is PickedService,
      current: was.objects,
      extend: extend,
    );
    if (next == null) return;
    setState(() {
      _history.selection = was.copyWith(
        mode: SelectionMode.object,
        objects: next,
      );
      _cubit.say(null);
    });
  }

  /// A click in the outliner — `ux-14`.
  ///
  /// **The anchor is kept here rather than inside the list.** A shift-click
  /// means "from the last one I picked", and the last one picked survives a
  /// rebuild of the panel, a trip through another mode and an undo; a
  /// `StatefulWidget` inside the list would lose it on any of the three.
  void _pickedInOutliner(int id, OutlinerPick how) {
    final ProjectSelection was = _history.selection;
    final List<int> next = outlinerSelection(
      current: was.objects,
      rows: outlinerRows(_history.project.objects),
      id: id,
      how: how,
      anchor: _outlinerAnchor,
    );
    setState(() {
      // A range keeps whatever it was measured from; anything else sets it,
      // so the next shift-click reaches back to here.
      if (how != OutlinerPick.through) _outlinerAnchor = id;
      _history.selection = was.copyWith(
        mode: SelectionMode.object,
        objects: next,
      );
      _cubit.say(null);
    });
  }

  /// What the selection is, in the words the status line shows.
  String get _selectionSaid => _history.selection.says;
}

/// Reads a model out of the bundle and uploads it.
///
/// Through the isolate loader, which is what an application does: decoding
/// the Khronos helmet costs a third of a frame at best, and a viewport that
/// stutters while opening is the first thing anybody notices.
Future<ModelAsset> _load(String path, GraphicsDevice device) async {
  final document = await decodeModelInIsolate(
    ModelLoadRequest(source: BundleAssetSource(path)),
  );
  return ModelAsset.fromDocument(document, device: device, name: path);
}
