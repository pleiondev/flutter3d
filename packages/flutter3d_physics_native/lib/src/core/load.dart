/// Loading the core: natively nothing, in the browser its module — P9.
library;

export 'load_native.dart'
    if (dart.library.js_interop) 'module_web.dart'
    show
        defaultPhysicsCoreThreadsUrl,
        defaultPhysicsCoreUrl,
        defaultPhysicsWorkerUrl,
        loadPhysicsCore,
        physicsCoreLoaded,
        physicsCoreThreads;
