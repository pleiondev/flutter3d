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
      // `tut-19`'s own preview capture: whether this viewer could edit the
      // model, and the source file's current hash — both threaded straight
      // through to the build inside, the same way `id` already is. See
      // `model_page.dart`'s own `data-editable`/`data-source-sha` for why
      // each is safe to send to every viewer, editor or not.
      const editable = frame.dataset.editable;
      const sourceSha = frame.dataset.sourceSha;
      const csrf = frame.dataset.csrf;
      const iframe = document.createElement('iframe');
      iframe.src = `/app/?model=${encodeURIComponent(source)}&name=${encodeURIComponent(name)}&id=${encodeURIComponent(id)}&mode=view&editable=${encodeURIComponent(editable)}&sourceSha=${encodeURIComponent(sourceSha)}&csrf=${encodeURIComponent(csrf)}`;
      iframe.title = `${name}, in 3D`;
      iframe.allow = 'fullscreen';
      iframe.loading = 'eager';
      frame.replaceChildren(iframe);
      frame.classList.add('live');
      iframe.focus();
    });
  }
})();
