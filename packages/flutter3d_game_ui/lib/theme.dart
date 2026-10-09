/// What every widget of flutter3d_game_ui reads: the colours it is drawn in
/// and the words it says.
///
/// * [GameUiTheme]: a `ThemeExtension` with the panel, touch, map and HUD
///   colours, so a game restyles every widget here in one place.
/// * [Flutter3dGameLocalizations]: every default string a widget here would
///   otherwise have typed in English, with English and Russian shipped and
///   a delegate an app lists beside Flutter's own.
///
/// Both were `flutter3d_game`'s until 1.0.0-rc.1, when the widgets that read
/// them moved here.
library;

export 'src/l10n/game_localizations.dart';
export 'src/theme/game_ui_theme.dart';
