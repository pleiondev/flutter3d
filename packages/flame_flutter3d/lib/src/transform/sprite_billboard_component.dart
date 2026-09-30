import 'dart:async' show scheduleMicrotask;

import 'package:flame/components.dart';
import 'package:flame/sprite.dart' show SpriteAnimationTicker;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Portable;

import '../host/has_flutter3d.dart';
import 'billboard_atlas.dart';
import 'object3d_component.dart';

/// A Flame [Sprite], or a [SpriteAnimation], drawn in the scene on a card
/// that turns to face the camera: a racing car seen from behind, a tree by
/// the road, an explosion, the flat sprites a cartridge-era game is made of
/// standing in a 3D world.
///
/// **Flame's sprites, not a second kind.** The picture is the sprite's own
/// image, cut where the sprite says; an animation is Flame's, played by
/// its `SpriteAnimationTicker` on Flame's clock, so its frames, its timing,
/// its looping and its `onComplete` are what a flat Flame game has, and
/// [removeOnFinish] takes a one-shot away when it has played, as it does a
/// `SpriteAnimationComponent`. The image goes to the device once; each part
/// of it a frame shows is a card of its own corners.
///
/// **Share an [atlas].** Many billboards of one sprite sheet, a bank of
/// reeds, should be handed the game's [BillboardAtlas], and draw with one
/// texture and one material; one without makes its own, and lets it go
/// when it goes.
///
/// **Standing on the plane.** The card is [cardHeight] metres tall and as
/// wide as the sprite's shape makes it, its foot at the component's place:
/// a car on the road, not sunk into it. [upright] turns it about the plane's
/// normal only, as a tree should; otherwise it faces the camera squarely,
/// as a spark may. The camera is the game's `camera3d` unless [faces] is
/// given.
///
/// Drawn unlit, cut out where the sprite is clear, and sampled nearest, as
/// pixel art wants, or [smooth] for lettering; `tint` and `opacity` colour
/// and fade it.
class SpriteBillboardComponent extends Object3dComponent {
  SpriteBillboardComponent({
    Sprite? sprite,
    SpriteAnimation? animation,
    required this.device,
    required super.scene,
    required super.plane,
    BillboardAtlas? atlas,
    this.cardHeight = 1.0,
    this.upright = true,
    this.faces,
    this.removeOnFinish = false,
    this.smooth = false,
    super.position,
    super.elevation,
    super.priority,
  }) : assert(
         (sprite == null) != (animation == null),
         'a sprite or an animation, and one of them',
       ),
       _sprite = sprite,
       _atlas = atlas ?? BillboardAtlas(device),
       _ownsAtlas = atlas == null,
       ticker = animation?.createTicker(),
       super(
         node: SceneNode(name: 'sprite billboard'),
         direction: SyncDirection.flameToScene,
       );

  final GraphicsDevice device;

  /// How tall the card stands, in metres.
  final double cardHeight;

  /// Whether the card turns about the plane's normal only.
  final bool upright;

  /// The camera it faces; the game's `camera3d` when null.
  final CameraNode? faces;

  /// Whether a one-shot animation takes the component away once played.
  final bool removeOnFinish;

  /// Whether the picture is sampled linearly rather than nearest: for
  /// lettering, from `BillboardAtlas.spriteOfText`, and anything not pixel
  /// art.
  final bool smooth;

  Sprite? _sprite;

  /// The sprite whose picture the card is drawn with now.
  Sprite? _showing;

  /// Shows [next] instead of the sprite it had: a sign that says something
  /// else, a score that went up. One of another image is uploaded first and
  /// shown when it is; an animation's billboard keeps playing its frames.
  set sprite(Sprite next) {
    if (ticker != null) return;
    _sprite = next;
    final card = _card;
    if (card == null) return;
    _atlas.materialOf(next.image, smooth: smooth).then((material) {
      if (material == null || !identical(_sprite, next)) return;
      card.material = material;
      _showing = next;
      _showFrame();
    });
  }

  final BillboardAtlas _atlas;
  final bool _ownsAtlas;

  /// The animation's ticker, when it is an animation: Flame's own, to pause,
  /// reset or listen to.
  final SpriteAnimationTicker? ticker;

  /// The sprite drawn now.
  Sprite get currentSprite => _sprite ?? ticker!.getSprite();

  MeshNode? _card;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final material = await _atlas.materialOf(
      currentSprite.image,
      smooth: smooth,
    );
    if (material == null) return;
    _showing = currentSprite;
    final card = _card = MeshNode(_atlas.cardOf(currentSprite), material);
    visual.add(card);
    _showFrame();
  }

  @override
  void update(double dt) {
    final playing = ticker;
    if (playing != null) {
      playing.update(dt);
      if (removeOnFinish && playing.done()) removeFromParent();
    }
    super.update(dt);
  }

  @override
  void updateTree(double dt) {
    super.updateTree(dt);
    _showFrame();
    _face();
  }

  /// Shows the sprite now on the card, and sizes the card to its shape.
  void _showFrame() {
    final card = _card;
    if (card == null) return;
    // A sprite of a picture still going up keeps the last one's card until
    // its material is there to draw it.
    final sprite = ticker?.getSprite() ?? _showing ?? currentSprite;
    final showing = _atlas.cardOf(sprite);
    if (!identical(card.mesh, showing)) card.mesh = showing;
    final wide = cardHeight * sprite.srcSize.x / sprite.srcSize.y;
    final scale = card.readScale();
    if (scale.x != wide || scale.y != cardHeight) {
      card.setScale(wide, cardHeight, 1.0);
    }
  }

  final Quaternion _toward = Quaternion.identity();

  /// Turns [visual] so the card faces the camera, whatever [node] is turned
  /// by.
  void _face() {
    final eye = faces ?? _gameCamera();
    if (eye == null) return;
    final from = node.readWorldPosition();
    final to = eye.readWorldPosition()..sub(from);
    if (upright) {
      final up = plane.normal;
      to.sub(up * to.dot(up));
      if (to.length2 == 0.0) return;
      // About the normal, from the card's +Z to the camera.
      final yaw = Portable.atan2(to.x, to.z);
      _toward.setAxisAngle(Vector3(0.0, 1.0, 0.0), yaw);
    } else {
      if (to.length2 == 0.0) return;
      _toward.setFromTwoVectors(Vector3(0.0, 0.0, 1.0), to.normalized());
    }
    final undo = node.readRotation()..inverse();
    visual.setRotation(undo * _toward);
  }

  CameraNode? _gameCamera() => switch (findGame()) {
    final HasFlutter3d game => game.camera3d,
    _ => null,
  };

  /// Its own atlas goes with it, after the frames in flight, and not when
  /// Flame only moves it; a shared one is the game's.
  @override
  void onRemove() {
    if (_ownsAtlas) {
      final game = findGame();
      final drawing = game is HasFlutter3d ? game.renderer : null;
      scheduleMicrotask(() {
        if (isMounted || parent != null) return;
        _atlas.dispose(drawing: drawing);
      });
    }
    super.onRemove();
  }
}
