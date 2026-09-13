// The password rules, ticked off while somebody types.
//
// **Advice, not a gate.** The list under the field is rendered by the server and
// reads the same without this script; this only marks which lines are already
// true. The server checks every rule again, including the ones not shown here —
// common passwords, keyboard runs, the person's own name — so nothing here has
// to be exhaustive, and nothing here can let a weak password through.
(() => {
  const MIN = 10;
  const PASSPHRASE = 16;

  const kinds = (value) =>
    [/\p{Ll}/u, /\p{Lu}/u, /\p{Nd}/u, /[^\p{L}\p{Nd}]/u].filter((kind) => kind.test(value)).length;

  for (const form of document.querySelectorAll('form')) {
    const password = form.querySelector('[data-password]');
    const confirm = form.querySelector('[data-password-confirm]');
    const list = form.querySelector('[data-password-checklist]');
    if (!password || !list) continue;

    const mark = (rule, ok) => {
      const item = list.querySelector(`[data-rule="${rule}"]`);
      if (item) item.dataset.ok = ok ? 'true' : 'false';
    };

    const update = () => {
      const value = password.value;
      const length = [...value].length;
      mark('length', length >= MIN);
      mark('mix', length >= PASSPHRASE || (length >= MIN && kinds(value) >= 3));
      if (confirm) {
        mark('match', value.length > 0 && confirm.value === value);
        // The browser's own message on submit, in the same words as the list.
        confirm.setCustomValidity(
          confirm.value && confirm.value !== value ? 'The two passwords do not match.' : '',
        );
      }
      list.classList.add('live');
    };

    password.addEventListener('input', update);
    if (confirm) confirm.addEventListener('input', update);
  }
})();
