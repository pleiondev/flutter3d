// Uploading from the cabinet: pick or drop a file, watch it go, land on its page.
//
// A script rather than a form, for one reason: a multi-megabyte upload with no
// progress looks exactly like a page that has hung. XMLHttpRequest rather than
// fetch because fetch still reports nothing while a body is being sent.
(() => {
  const zone = document.querySelector('[data-upload]');
  if (!zone) return;

  const input = zone.querySelector('input[type=file]');
  const status = zone.querySelector('[data-upload-status]');
  const limit = Number(zone.dataset.limit);
  const csrf = zone.dataset.csrf;

  const say = (text, kind) => {
    status.textContent = text;
    status.dataset.kind = kind || '';
  };

  const megabytes = (bytes) => (bytes / (1024 * 1024)).toFixed(1) + ' MB';

  const send = (file) => {
    if (file.size > limit) {
      say(`${file.name} is ${megabytes(file.size)}; the limit is ${megabytes(limit)}.`, 'error');
      return;
    }
    const request = new XMLHttpRequest();
    request.open('POST', '/api/v1/models');
    request.setRequestHeader('content-type', 'application/octet-stream');
    request.setRequestHeader('x-csrf', csrf);
    request.setRequestHeader('x-filename', encodeURIComponent(file.name));

    request.upload.onprogress = (event) => {
      if (!event.lengthComputable) return;
      const percent = Math.round((event.loaded / event.total) * 100);
      say(percent < 100 ? `Sending ${file.name}: ${percent}%` : `Checking ${file.name}…`);
    };
    request.onload = () => {
      let body = {};
      try { body = JSON.parse(request.responseText); } catch (_) {}
      if (request.status === 201 && body.path) {
        window.location.href = body.path;
      } else {
        say(body.error || `The upload failed (${request.status}).`, 'error');
        zone.classList.remove('busy');
      }
    };
    request.onerror = () => {
      say('The connection dropped before the upload finished.', 'error');
      zone.classList.remove('busy');
    };

    zone.classList.add('busy');
    say(`Sending ${file.name}…`);
    request.send(file);
  };

  input.addEventListener('change', () => {
    if (input.files.length > 0) send(input.files[0]);
  });

  zone.addEventListener('dragover', (event) => {
    event.preventDefault();
    zone.classList.add('over');
  });
  zone.addEventListener('dragleave', () => zone.classList.remove('over'));
  zone.addEventListener('drop', (event) => {
    event.preventDefault();
    zone.classList.remove('over');
    if (event.dataTransfer.files.length > 0) send(event.dataTransfer.files[0]);
  });
})();
