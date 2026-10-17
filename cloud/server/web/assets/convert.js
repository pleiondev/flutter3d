// Converting from /convert: send the file, wait for the converter, land on
// the result.
//
// A script for the same reason upload.js is one: a large file with no
// progress looks like a page that has hung, and a conversion can take a
// minute after the last byte arrives. The file goes as the request body with
// its name and the chosen target in headers — the shape /api/v1/models takes.
(() => {
  const form = document.querySelector('[data-convert]');
  if (!form) return;

  const input = form.querySelector('input[type=file]');
  const target = form.querySelector('select');
  const button = form.querySelector('button[type=submit]');
  const status = form.querySelector('[data-convert-status]');
  const limit = Number(form.dataset.limit);
  const csrf = form.dataset.csrf;

  const say = (text, kind) => {
    status.textContent = text;
    status.dataset.kind = kind || '';
  };
  const megabytes = (bytes) => (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  const idle = () => {
    form.classList.remove('busy');
    button.disabled = false;
  };

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const file = input.files[0];
    if (!file) {
      say('Choose a file first.', 'error');
      return;
    }
    if (file.size > limit) {
      say(`${file.name} is ${megabytes(file.size)}; the limit is ${megabytes(limit)}.`, 'error');
      return;
    }

    const request = new XMLHttpRequest();
    request.open('POST', '/api/v1/conversions');
    request.setRequestHeader('content-type', 'application/octet-stream');
    request.setRequestHeader('x-csrf', csrf);
    request.setRequestHeader('x-filename', encodeURIComponent(file.name));
    request.setRequestHeader('x-target', target.value);

    request.upload.onprogress = (progress) => {
      if (!progress.lengthComputable) return;
      const percent = Math.round((progress.loaded / progress.total) * 100);
      say(percent < 100
        ? `Sending ${file.name}: ${percent}%`
        : `Converting ${file.name}… this can take up to two minutes.`);
    };
    request.onload = () => {
      let body = {};
      try { body = JSON.parse(request.responseText); } catch (_) {}
      if (request.status === 201 && body.path) {
        window.location.href = body.path;
      } else {
        say(body.error || `The conversion failed (${request.status}).`, 'error');
        idle();
      }
    };
    request.onerror = () => {
      say('The connection dropped before the conversion finished.', 'error');
      idle();
    };

    form.classList.add('busy');
    button.disabled = true;
    say(`Sending ${file.name}…`);
    request.send(file);
  });
})();
