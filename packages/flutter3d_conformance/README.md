# flutter3d_conformance

What `flutter3d_hardware` requires of a backend, as a suite the backend runs
against itself.

```dart
void main() => runConformance(device);
```

An interface can only say that a call exists. This says that a clear covers the
whole attachment, that uploaded pixels keep their row order, that the HDR format
the backend names is really renderable, and that every stage pair the engine
links does link.

**The last one earns its place regularly.** A varying a fragment stage reads and
no vertex stage writes is a hard error in a browser and invisible on a backend
whose pipelines were linked ahead of time — so the check catches, on one
backend, a mistake that would ship on another.
