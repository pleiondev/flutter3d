// Opening a model in 3D, on request.
//
// **The engine is not loaded until somebody asks for it.** A model page is a
// few kilobytes of HTML; the renderer is megabytes of script. Somebody who came
// to read the licence or download the file should not wait for either, so the
// page shows a still frame and a button, and the button is what starts the load.
(() => {
  for (const frame of document.querySelectorAll('[data-viewer]')) {
    const button = frame.querySelector('button');
    if (!button) continue;

    button.addEventListener('click', () => {
      const source = frame.dataset.src;
      const name = frame.dataset.name;
      const id = frame.dataset.id;
      const iframe = document.createElement('iframe');
      iframe.src = `/app/?model=${encodeURIComponent(source)}&name=${encodeURIComponent(name)}&id=${encodeURIComponent(id)}&mode=view`;
      iframe.title = `${name}, in 3D`;
      iframe.allow = 'fullscreen';
      iframe.loading = 'eager';
      frame.replaceChildren(iframe);
      frame.classList.add('live');
      iframe.focus();
    });
  }
})();
