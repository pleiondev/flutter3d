## 0.6.0

**The first release. It takes the set's number rather than a first number of its
own**, because the whole workspace goes out together and a decoder resolved
against a different `flutter3d_geometry` than the renderer above it would fill
in a `MeshData` the engine does not draw. What follows is what this package is,
not what changed in it: the files came out of `flutter3d` with their behaviour
intact.

* **Every format the engine reads, with no Flutter SDK behind it.**
  `ModelDocument` and the nodes, surfaces, skins, animations and images it
  holds; `SurfaceMaterial`, `MaterialDocument`, `MaterialHint` and
  `LightingModel`; the glTF/GLB reader with its accessors and GLB container;
  the OBJ reader with its `.mtl`; the engine's own `.f3d` reader and writer and
  its `.fmat`; `AnimationClip` and `AnimationTrack`; and the synchronous half of
  loading — `ModelFormat`, `ModelDecoder`, `decodeModel`, `decodeModelBytes`
  and `sniffModelFormat`.

* **The split is at the bytes.** What fetches them stayed in `flutter3d`:
  `decodeModelInIsolate` with its `kIsWeb`, `BundleAssetSource` on Flutter's
  asset bundle, `FileAssetSource` on `dart:io`, and the bundle resolvers.
  `AssetSource` itself is here, as the abstraction both of those extend, so a
  decoder can be handed a source without either of them coming with it.

* **`flutter3d` exports this package whole,** so an application that imports the
  engine keeps every name it had.
