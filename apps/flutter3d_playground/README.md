# flutter3d playground

A level or a prefab document as JSON in an editor, and the scene it
describes beside it, redrawn a quarter of a second after the last key.
What stops a document being drawn (JSON that does not parse, with its line
and column; another format; an instance of a prefab nobody wrote) is said
under the text, and the last document that read stays on screen.

```
flutter run -d chrome
```

The site's [playground page](https://flutter3d.pleion.dev/playground/) is
this application's web build, made by `site/tool/demos.sh playground`.

Entities are drawn as small boxes, one colour per type: what an entity
looks like is a game's vocabulary, and the playground has no game.
`lib/src/reading.dart` reads the text and `lib/src/scene.dart` builds the
scene, both without a window, which is what `test/reading_test.dart` holds.
