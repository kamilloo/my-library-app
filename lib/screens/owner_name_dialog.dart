import 'package:flutter/material.dart';

import '../models/owner_name.dart';

Future<String?> showOwnerNameDialog(
  BuildContext context, {
  required bool requiredName,
  String initialName = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        final form = GlobalKey<FormState>();
        var name = initialName;
        return AlertDialog(
          title: const Text('Właściciel'),
          scrollable: true,
          content: Form(
            key: form,
            child: TextFormField(
              initialValue: initialName,
              textCapitalization: TextCapitalization.words,
              maxLength: ownerNameMaxLength,
              decoration: InputDecoration(
                labelText: 'Twoje imię i nazwisko',
                helperText: requiredName
                    ? 'Nazwa pojawi się jako „Właściciel” w udostępnianych informacjach.'
                    : 'Zostaw puste pole, aby usunąć zapisaną nazwę.',
                helperMaxLines: 3,
              ),
              validator: (input) {
                try {
                  final value = validateOwnerName(input ?? '');
                  if (requiredName && value == null) {
                    return 'Podaj imię i nazwisko.';
                  }
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
              onSaved: (input) => name = input ?? '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () {
                final state = form.currentState!;
                if (!state.validate()) return;
                state.save();
                Navigator.pop(context, name);
              },
              child: Text(requiredName ? 'Zapisz' : 'Zapisz i odśwież QR'),
            ),
          ],
        );
      },
    );
