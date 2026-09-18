/// `ux-50`'s own spike, checked without a window: the body walks, the floor
/// holds it up, and an edit to the document reaches the running game.
///
///     flutter test test/play_session_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/play/play_session.dart';
import 'package:flutter3d_modeler/src/play/play_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector2, Vector3;

import 'support/fake_graphics_backend.dart';

/// A project of one box, which is the document Play is standing in.
ModelProject _one() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'hero',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
  ),
);

/// Walking forward for [seconds], a sixtieth at a time — a body is stepped,
/// not teleported, and one big step would sweep past the floor it stands on.
void _walk(
  PlaySession session, {
  double seconds = 1.0,
  Vector2? move,
  bool sprint = false,
}) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    session.step(1 / 60, (
      move: move ?? Vector2(0.0, 1.0),
      sprint: sprint,
      jump: false,
    ));
  }
}

void main() {
  test('the body stands on the floor rather than falling through it', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final PlaySession session = PlaySession.start(
      device: it.device,
      project: _one(),
    );

    _walk(session, seconds: 2.0, move: Vector2.zero());

    // **Mutation: leave the floor out of the collision world and only draw
    // it.** The body then falls for as long as Play is open, and the
    // template that walks a character delivers a character falling.
    expect(session.position.y, closeTo(0.9, 0.2));
  });

  test('forward is where the look points, and sprint is faster', () {
    final it = fakeTestDevice(width: 8, height: 8);
    PlaySession fresh() =>
        PlaySession.start(device: it.device, project: _one());

    final PlaySession walked = fresh();
    _walk(walked);
    final PlaySession ran = fresh();
    _walk(ran, sprint: true);

    // Yaw nought looks down -Z, so forward is -Z — the same convention
    // `LevelWalk.wishFor` keeps, and the one the camera's own `lookAt`
    // below agrees with.
    expect(walked.position.z, lessThan(-1.0));
    expect(ran.position.z, lessThan(walked.position.z));

    // And turning turns what forward means. **Mutation: build the wish
    // direction from the world axes rather than from `yaw`.** Walking then
    // ignores where the player is looking, which is the first thing anybody
    // tries.
    final PlaySession turned = fresh()..look(-600, 0);
    _walk(turned);
    expect(turned.position.x.abs(), greaterThan(1.0));
  });

  test(
    'the character template carries the document, the prop one does not',
    () {
      final it = fakeTestDevice(width: 8, height: 8);

      final PlaySession character = PlaySession.start(
        device: it.device,
        project: _one(),
        template: PlayTemplate.character,
      );
      _walk(character);
      final Vector3 rode = character.stage.subject.readPosition();
      expect(rode.z, lessThan(-1.0));

      final PlaySession prop = PlaySession.start(
        device: it.device,
        project: _one(),
        template: PlayTemplate.prop,
      );
      _walk(prop);
      // The document stays where the document is: walking around a prop is
      // the whole of that template, and a prop that walked away with the
      // player would be the character template under another name.
      expect(prop.stage.subject.readPosition().length, closeTo(0.0, 1e-6));
      expect(prop.position.z, lessThan(PlayTemplate.prop.startsBack));
    },
  );

  test('an edit to the document reaches the running game', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final ModelHistory history = ModelHistory(_one());
    final PlaySession session = PlaySession.start(
      device: it.device,
      project: history.project,
    );
    final int id = history.project.objects.single.id;
    expect(session.stage.sync!.nodeOf(id), isNotNull);

    expect(
      history.run(
        SetTransform(id: id, to: Matrix4.translation(Vector3(0.0, 3.0, 0.0))),
      ),
      isNull,
    );
    session.stage.sync!.apply(history.project);

    // **This is the row's whole acceptance, and choosing in-process is what
    // made it one line.** The scene is `SceneSync`'s, the same class the
    // viewport keeps its own picture with, so "reload" is the sync the
    // document already runs — not a process to restart, a port to reconnect
    // or a file to re-export. Mutation: build Play a scene of its own from
    // a copy of the project, and an edit made behind it needs Play stopped
    // and started again to be seen.
    expect(
      session.stage.sync!.nodeOf(id)!.readPosition().y,
      closeTo(3.0, 1e-6),
    );
  });

  test('ux-51: Reload keeps the walk the player already made', () {
    final it = fakeTestDevice(width: 8, height: 8);
    final ModelHistory history = ModelHistory(_one());
    final PlaySession session = PlaySession.start(
      device: it.device,
      project: history.project,
      template: PlayTemplate.prop,
    );
    _walk(session);
    final Vector3 stood = session.position.clone();
    final int id = history.project.objects.single.id;

    expect(history.run(const AddMaterial(materialName: 'brass')), isNull);
    session.reload(history.project);

    // **Mutation: respawn on reload.** That is Play stopped and started
    // again under another name, and it throws away the walk somebody made
    // to reach the corner they wanted to look at — which is the whole
    // reason a Reload button exists beside a Stop one.
    expect(session.position.x, closeTo(stood.x, 1e-6));
    expect(session.position.z, closeTo(stood.z, 1e-6));
    expect(session.stage.sync!.nodeOf(id), isNotNull);
  });
}
