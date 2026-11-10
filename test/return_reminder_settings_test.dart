import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_database.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/screens/return_reminder_settings.dart';
import 'package:my_library/services/return_reminders.dart';

import 'return_reminders_test.dart' show FakeNotifications;

class SettingsReminders extends ReturnReminders {
  SettingsReminders() : super(LibraryDatabase.instance, FakeNotifications());
  bool optedIn = false;
  int requests = 0;
  bool granted = false;
  @override
  Future<bool> enabled(String bookId) async => optedIn;
  @override
  Future<ReminderResult> setEnabled(String bookId, bool value) async {
    requests++;
    if (value && !granted) return ReminderResult.denied;
    optedIn = value;
    return value ? ReminderResult.enabled : ReminderResult.disabled;
  }
}

void main() {
  testWidgets(
      'reminder is off by default and denial preserves opt-out with Polish recovery',
      (tester) async {
    final reminders = SettingsReminders();
    final book = Book(
      id: 'book',
      title: 'Title',
      author: 'Author',
      status: BookStatus.borrowed,
      borrowedBy: 'Anna',
      returnDate: DateTime(2030, 6, 1),
      createdAt: DateTime(2020),
      updatedAt: DateTime(2020),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ReturnReminderSettings(
        book: book,
        repository: LibraryRepository(reminders: reminders),
        onBookChanged: (_) {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(reminders.requests, 0);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.textContaining('Brak zgody na powiadomienia.'), findsOneWidget);
    expect(find.text('Ustawienia powiadomień'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
    reminders.granted = true;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(reminders.optedIn, isFalse);
  });
}
