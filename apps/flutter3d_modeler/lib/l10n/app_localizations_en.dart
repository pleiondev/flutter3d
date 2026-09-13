// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'flutter3d modeller';

  @override
  String get unsavedChangesTitle => 'Unsaved changes';

  @override
  String get unsavedChangesBody =>
      'This model has changes that have not been saved.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discard => 'Discard';

  @override
  String get saveAndClose => 'Save and close';

  @override
  String get restoreUnsavedChangesTitle => 'Restore unsaved changes?';

  @override
  String restoreUnsavedChangesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'An autosave from a session that did not close cleanly was found ($count objects).',
      one:
          'An autosave from a session that did not close cleanly was found ($count object).',
    );
    return '$_temp0';
  }

  @override
  String get restore => 'Restore';

  @override
  String get exportAnywayTitle => 'Export anyway?';

  @override
  String exportAnywayMoreIssues(int count) {
    return 'and $count more';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get exportAnyway => 'Export anyway';

  @override
  String get addPrimitiveTooltip => 'Add a primitive';

  @override
  String get add => 'Add';

  @override
  String get open => 'Open';

  @override
  String get save => 'Save';

  @override
  String get exportTooltip => 'Export a copy';

  @override
  String get export => 'Export';

  @override
  String get materialStudioSemanticsLabel => 'Material Studio';

  @override
  String get materialStudioTooltip => 'Material Studio — preview a material';

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get keyboardShortcutsTooltip => 'Keyboard shortcuts (?)';

  @override
  String get startScreenSemanticsLabel => 'Start screen';

  @override
  String get startScreenTooltip =>
      'Start screen — open a file or start a new project';

  @override
  String get reportProblem => 'Report a problem';

  @override
  String get sectionDisplay => 'Display';

  @override
  String get sectionView => 'View';

  @override
  String get sectionObjects => 'Objects';

  @override
  String get sectionTransform => 'Transform';

  @override
  String get sectionModifiers => 'Modifiers';

  @override
  String get sectionLastOperation => 'Last operation';

  @override
  String get sectionSelection => 'Selection';

  @override
  String get sectionMesh => 'Mesh';

  @override
  String get sectionBudget => 'Budget';

  @override
  String get rowWhat => 'What';

  @override
  String get rowVertices => 'Vertices';

  @override
  String get rowFaces => 'Faces';

  @override
  String get rowTriangles => 'Triangles';

  @override
  String get rowProfile => 'Profile';

  @override
  String get shadingMaterial => 'Material';

  @override
  String get shadingNormals => 'Normals';

  @override
  String get shadingWire => 'Wire';

  @override
  String get lensPerspective => 'Perspective';

  @override
  String get lensOrthographic => 'Orthographic';

  @override
  String get viewFront => 'Front';

  @override
  String get viewBack => 'Back';

  @override
  String get viewLeft => 'Left';

  @override
  String get viewRight => 'Right';

  @override
  String get viewTop => 'Top';

  @override
  String get viewBottom => 'Bottom';

  @override
  String get recoverUnsavedChangesTitle => 'Recover unsaved changes?';

  @override
  String get recoverUnsavedChangesBody =>
      'A more recent autosave was found than the last saved file. Restore it, or open the file as it was last saved?';

  @override
  String get openSavedFile => 'Open saved file';

  @override
  String get restoreAutosave => 'Restore autosave';

  @override
  String get startTitle => 'Start';

  @override
  String get openFile => 'Open file';

  @override
  String get newProject => 'New project';

  @override
  String get recent => 'Recent';

  @override
  String get tutorial => 'Tutorial';

  @override
  String get close => 'Close';
}
