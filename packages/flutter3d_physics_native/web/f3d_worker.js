// A worker for the physics core's threads module — P9, phase 12.
//
// Started by loadPhysicsCore(threads: n), n − 1 of them: each makes an
// instance of the module on the one shared memory, takes the stack it was
// given, and waits in the core for its share of each pass. It never comes
// back; the page ends it.
self.onmessage = (event) => {
  const { module, memory, index, top } = event.data;
  const instance = new WebAssembly.Instance(module, { env: { memory } });
  instance.exports.__stack_pointer.value = top;
  instance.exports.f3d_worker_main(index);
};
