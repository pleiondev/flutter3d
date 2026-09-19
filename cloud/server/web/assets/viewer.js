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

      // `allow="fullscreen"` above only permits the document inside to ask;
      // the modeller does not carry a fullscreen button of its own; without
      // one here, permission with nothing to use it is the whole of what a
      // visitor got. `.viewer`, not the iframe alone, is what goes fullscreen,
      // since the iframe already fills it (`.viewer.live iframe` in
      // styles.css) and a class on the fullscreen element is how the CSS
      // below tells a boxed preview from a full window.
      const fullscreen = document.createElement('button');
      fullscreen.type = 'button';
      fullscreen.className = 'viewer-fullscreen';
      fullscreen.title = 'Full screen';
      fullscreen.setAttribute('aria-label', 'Full screen');
      fullscreen.textContent = '⛶';
      fullscreen.addEventListener('click', () => {
        if (document.fullscreenElement) {
          document.exitFullscreen();
        } else {
          frame.requestFullscreen();
        }
      });
      frame.addEventListener('fullscreenchange', () => {
        frame.classList.toggle('fullscreen', document.fullscreenElement === frame);
      });

      frame.replaceChildren(iframe, fullscreen);
      frame.classList.add('live');
      iframe.focus();
    });
  }
})();
