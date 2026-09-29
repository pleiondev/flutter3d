import 'dart:async' show scheduleMicrotask;
import 'dart:typed_data' show Float32List;
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flame/components.dart';
import 'package:flame/sprite.dart' show SpriteAnimationTicker;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Portable;

import '../host/has_flutter3d.dart';
import 'object3d_component.dart';

/// A Flame [Sprite], or a [SpriteAnimation], drawn in the scene on a card
/// that turns to face the camera: a racing car seen from behind, a tree by
/// the road, an explosion, the flat sprites a cartridge-era game is made of
/// standing in a 3D world.
///
/// **Flame's sprites, not a second kind.** The picture is the sprite's own
/// image, cut where the sprite says; an animation is Flame's, played by
/// its `SpriteAnimationTicker` on Flame's clock, so its frames, its timing,
/// its looping and its `onComplete` are what a flat Flame game has. The
/// image goes to the device once; each part of it a frame shows is a card
/// of its own corners, made the first time it is shown.
///
/// **Standing on the plane.** The card is [cardHeight] metres tall and as wide
/// as the sprite's shape makes it, its foot at the component's place: a car
/// on the road, not sunk into it. [upright] turns it about the plane's
/// normal only, as a tree should; otherwise it faces the camera squarely,
/// as a spark may. The camera is the game's `camera3d` unless [faces] is
/// given.
///
/// Drawn unlit, cut out where the sprite is transparent, and sampled
/// nearest, as pixel art wants.
class SpriteBillboardComponent extends Object3dComponent {
  SpriteBillboardComponent({
    Sprite? sprite,
    SpriteAnimation? animation,
    required this.device,
    required super.scene,
    required super.plane,
    this.cardHeight = 1.0,
    this.upright = true,
    this.faces,
    super.position,
    super.elevation,
    super.priority,
  }) : assert(
         (sprite == null) != (animation == null),
         'a sprite or an animation, and one of them',
       ),
       _sprite = sprite,
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

  final Sprite? _sprite;

  /// The animation's ticker, when it is an animation: Flame's own, to pause,
  /// reset or listen to.
  final SpriteAnimationTicker? ticker;

  /// The sprite drawn now.
  Sprite get currentSprite => _sprite ?? ticker!.getSprite();

  TextureHandle? _texture;
  MeshNode? _cardNode;
  final Vector2 _imageSize = Vector2.zero();
  MeshData? _quad;

  /// A card per part of the image a frame shows, made the first time it
  /// is shown. Its own corners rather than a texture transform: every
  /// lighting model reads a mesh's corners, and not every one reads a
  /// material's transform.
  final Map<(double, double, double, double), DeviceMesh> _cards =
      <(double, double, double, double), DeviceMesh>{};

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final image = currentSprite.image;
    final pixels = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (pixels == null) return;
    _imageSize.setValues(image.width.toDouble(), image.height.toDouble());
    final texture = _texture = device.createTextureFromPixels(
      width: image.width,
      height: image.height,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: pixels,
    );
    // A quad in the XY plane facing +Z, its foot at the origin: the plane
    // shape stood up, image top upwards.
    _quad = const PlaneShape().build().transformed(
      Matrix4.translationValues(0.0, 0.5, 0.0)
        ..multiply(Matrix4.rotationX(1.5707963267948966)),
    );
    final node = _cardNode = MeshNode(
      _cardOf(currentSprite),
      engine.Material(
        name: 'sprite',
        lighting: LightingModel.unlit,
        albedo: texture,
        albedoSampler: SamplerOptions.nearestClamp,
        alphaMode: MaterialAlphaMode.mask,
        doubleSided: true,
      ),
    );
    visual.add(node);
    _showFrame();
  }

  /// The card showing the part of the image [sprite] is cut from.
  DeviceMesh _cardOf(Sprite sprite) {
    final at = sprite.srcPosition;
    final size = sprite.srcSize;
    return _cards.putIfAbsent((at.x, at.y, size.x, size.y), () {
      final quad = _quad!;
      final uv = quad.layout.floatOffsetOf(VertexLayout.texcoord.name);
      final stride = quad.layout.floatsPerVertex;
      final vertices = Float32List.fromList(quad.vertices);
      for (var i = uv; i >= 0 && i < vertices.length; i += stride) {
        vertices[i] = (at.x + vertices[i] * size.x) / _imageSize.x;
        vertices[i + 1] = (at.y + vertices[i + 1] * size.y) / _imageSize.y;
      }
      return DeviceMesh.upload(
        device,
        MeshData(
          layout: quad.layout,
          vertices: vertices,
          indices: quad.indices,
        ),
      );
    });
  }

  @override
  void update(double dt) {
    ticker?.update(dt);
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
    final card = _cardNode;
    if (card == null) return;
    final sprite = currentSprite;
    final showing = _cardOf(sprite);
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

  /// The picture and the cards go with the component, after the frames in
  /// flight, and not when Flame only moves it.
  @override
  void onRemove() {
    final texture = _texture;
    final cards = List<DeviceMesh>.of(_cards.values);
    final game = findGame();
    final drawing = game is HasFlutter3d ? game.renderer : null;
    scheduleMicrotask(() {
      if (isMounted || parent != null) return;
      for (final card in cards) {
        if (drawing != null) {
          drawing.releaseMeshAfterFrame(card);
        } else {
          device
            ..releaseGeometry(card.vertices)
            ..releaseGeometry(card.indices);
        }
      }
      _cards.clear();
      if (texture != null) device.releaseTexture(texture);
      _texture = null;
    });
    super.onRemove();
  }
}
