/// The pieces every form on the service is built from.
///
/// A label that is really attached to its input, an error the screen reader
/// announces with the field it belongs to, and the CSRF token in every POST —
/// three things that are easy to get right once and easy to forget the fifth
/// time a form is written by hand.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../auth/password_policy.dart';

/// A POST form carrying the CSRF token.
class PostForm extends StatelessComponent {
  const PostForm({
    required this.action,
    required this.csrf,
    required this.children,
    this.classes = 'stack',
    super.key,
  });

  final String action;
  final String csrf;
  final String classes;
  final List<Component> children;

  @override
  Component build(BuildContext context) => form(
    [input(type: InputType.hidden, name: 'csrf', value: csrf), ...children],
    action: action,
    method: FormMethod.post,
    classes: classes,
  );
}

/// A labelled input, with a hint under it or an error in the hint's place.
class Field extends StatelessComponent {
  // `label` outside, `caption` inside: a field named `label` would shadow the
  // `<label>` element this component has to build.
  const Field({
    required String label,
    required this.name,
    this.type = InputType.text,
    this.value,
    this.error,
    this.hint,
    this.autocomplete,
    this.required = true,
    this.minLength,
    this.maxLength,
    this.inputAttributes = const {},
    super.key,
  }) : caption = label;

  /// More attributes for the input itself — the markers a script looks for.
  final Map<String, String> inputAttributes;

  final String caption;
  final String name;
  final InputType type;
  final String? value;
  final String? error;
  final String? hint;
  final String? autocomplete;
  final bool required;
  final int? minLength;
  final int? maxLength;

  @override
  Component build(BuildContext context) {
    final id = 'f-$name';
    final note = error ?? hint;
    return div(
      [
        label([Component.text(caption)], htmlFor: id),
        input(
          type: type,
          name: name,
          value: value,
          id: id,
          attributes: {
            'autocomplete': ?autocomplete,
            if (required) 'required': '',
            if (minLength != null) 'minlength': '$minLength',
            if (maxLength != null) 'maxlength': '$maxLength',
            if (error != null) 'aria-invalid': 'true',
            if (note != null) 'aria-describedby': '$id-note',
            ...inputAttributes,
          },
        ),
        if (note != null)
          p([Component.text(note)], id: '$id-note', classes: error != null ? 'error' : 'hint'),
      ],
      classes: error != null ? 'field invalid' : 'field',
    );
  }
}

/// A new password, typed twice, with the rules listed between the two fields.
///
/// The list is the server's own rules as text, so it reads the same with the
/// script blocked; `password.js` only ticks the lines that are already met.
class PasswordFields extends StatelessComponent {
  const PasswordFields({
    required this.name,
    required this.confirmName,
    this.label = 'Password',
    this.confirmLabel = 'Password again',
    this.error,
    this.confirmError,
    super.key,
  });

  final String name;
  final String confirmName;
  final String label;
  final String confirmLabel;
  final String? error;
  final String? confirmError;

  @override
  Component build(BuildContext context) => Component.fragment([
    Field(
      label: label,
      name: name,
      type: InputType.password,
      error: error,
      autocomplete: 'new-password',
      minLength: minPasswordLength,
      inputAttributes: const {'data-password': ''},
    ),
    ul(
      [
        li([Component.text('At least $minPasswordLength characters')], attributes: const {'data-rule': 'length'}),
        li(
          [
            Component.text('Three of lowercase, uppercase, digits, symbols — or '
                '$passphraseLength characters and more'),
          ],
          attributes: const {'data-rule': 'mix'},
        ),
        li([Component.text('Both entries match')], attributes: const {'data-rule': 'match'}),
        li(
          [
            Component.text('Common passwords, keyboard runs and your own name or '
                'address are refused too.'),
          ],
          classes: 'extra',
        ),
      ],
      classes: 'checklist',
      attributes: const {'data-password-checklist': ''},
    ),
    Field(
      label: confirmLabel,
      name: confirmName,
      type: InputType.password,
      error: confirmError,
      autocomplete: 'new-password',
      inputAttributes: const {'data-password-confirm': ''},
    ),
  ]);
}

/// A sentence in a box: the result of what was just done, or why it was not.
class Notice extends StatelessComponent {
  const Notice(this.text, {this.kind = 'info', this.children = const [], super.key});

  final String text;

  /// `ok`, `error` or `info`.
  final String kind;

  /// Anything that goes after the sentence, such as a button to try again.
  final List<Component> children;

  @override
  Component build(BuildContext context) => div(
    [Component.text(text), ...children],
    classes: 'notice',
    attributes: {'data-kind': kind, 'role': kind == 'error' ? 'alert' : 'status'},
  );
}

Component submit(String label, {String? classes}) =>
    button([Component.text(label)], type: ButtonType.submit, classes: classes);
