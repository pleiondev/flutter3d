# flutter3d_impeller

`flutter3d_hardware` over `flutter_gpu`: the backend a desktop or mobile build
draws through.

```dart
final device = await GpuRenderBackend.create();
final renderer = Renderer.create(device: device);
```

Nothing else in the stack names `flutter_gpu`. Swapping this for another backend
is a change to one line of application wiring — which is the property the split
exists for, and the reason there are two more backends to prove it with.

## The shader bundle

`flutter_gpu` wants shaders compiled ahead of time, so this package builds one:

    ./tool/build_shaders.sh

The bundle is gitignored and its format is tied to the SDK version, so a fresh
checkout has none until that runs. A test asserts it was built — deliberately a
failure rather than a skip, because "CI built only one bundle" is exactly the
trap that test exists to catch.
