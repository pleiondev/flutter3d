// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'flutter3d modeller';

  @override
  String get unsavedChangesTitle => 'Несохранённые изменения';

  @override
  String get unsavedChangesBody =>
      'В этой модели есть изменения, которые не были сохранены.';

  @override
  String get keepEditing => 'Продолжить редактирование';

  @override
  String get discard => 'Не сохранять';

  @override
  String get saveAndClose => 'Сохранить и закрыть';

  @override
  String get restoreUnsavedChangesTitle =>
      'Восстановить несохранённые изменения?';

  @override
  String restoreUnsavedChangesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объекта).',
      many:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объектов).',
      few:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объекта).',
      one:
          'Найден автосохранённый файл сессии, которая закрылась некорректно ($count объект).',
    );
    return '$_temp0';
  }

  @override
  String get restore => 'Восстановить';

  @override
  String get exportAnywayTitle => 'Всё равно экспортировать?';

  @override
  String exportAnywayMoreIssues(int count) {
    return 'и ещё $count';
  }

  @override
  String get cancel => 'Отмена';

  @override
  String get exportAnyway => 'Всё равно экспортировать';

  @override
  String get addPrimitiveTooltip => 'Добавить примитив';

  @override
  String get add => 'Добавить';

  @override
  String get open => 'Открыть';

  @override
  String get save => 'Сохранить';

  @override
  String get exportTooltip => 'Экспортировать копию';

  @override
  String get export => 'Экспорт';

  @override
  String get materialStudioSemanticsLabel => 'Материал-студия';

  @override
  String get materialStudioTooltip =>
      'Материал-студия — предпросмотр материала';

  @override
  String get keyboardShortcuts => 'Горячие клавиши';

  @override
  String get keyboardShortcutsTooltip => 'Горячие клавиши (?)';

  @override
  String get startScreenSemanticsLabel => 'Стартовый экран';

  @override
  String get startScreenTooltip =>
      'Стартовый экран — открыть файл или начать новый проект';

  @override
  String get reportProblem => 'Сообщить о проблеме';

  @override
  String get sectionDisplay => 'Отображение';

  @override
  String get sectionView => 'Вид';

  @override
  String get sectionObjects => 'Объекты';

  @override
  String get sectionTransform => 'Трансформация';

  @override
  String get sectionModifiers => 'Модификаторы';

  @override
  String get sectionLastOperation => 'Последняя операция';

  @override
  String get sectionSelection => 'Выделение';

  @override
  String get sectionMesh => 'Меш';

  @override
  String get sectionBudget => 'Бюджет';

  @override
  String get rowWhat => 'Что';

  @override
  String get rowVertices => 'Вершины';

  @override
  String get rowFaces => 'Грани';

  @override
  String get rowTriangles => 'Треугольники';

  @override
  String get rowProfile => 'Профиль';

  @override
  String get shadingMaterial => 'Материал';

  @override
  String get shadingNormals => 'Нормали';

  @override
  String get shadingWire => 'Каркас';

  @override
  String get lensPerspective => 'Перспектива';

  @override
  String get lensOrthographic => 'Ортографическая';

  @override
  String get viewFront => 'Спереди';

  @override
  String get viewBack => 'Сзади';

  @override
  String get viewLeft => 'Слева';

  @override
  String get viewRight => 'Справа';

  @override
  String get viewTop => 'Сверху';

  @override
  String get viewBottom => 'Снизу';

  @override
  String get recoverUnsavedChangesTitle =>
      'Восстановить несохранённые изменения?';

  @override
  String get recoverUnsavedChangesBody =>
      'Найдена автосохранённая версия новее последнего сохранённого файла. Восстановить её или открыть файл в том виде, в каком он был сохранён?';

  @override
  String get openSavedFile => 'Открыть сохранённый файл';

  @override
  String get restoreAutosave => 'Восстановить автосохранение';

  @override
  String get startTitle => 'Начало';

  @override
  String get openFile => 'Открыть файл';

  @override
  String get newProject => 'Новый проект';

  @override
  String get recent => 'Недавние';

  @override
  String get tutorial => 'Обучение';

  @override
  String get close => 'Закрыть';
}
