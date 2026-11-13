import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_library/screens/tutorial_screen.dart';
import 'package:my_library/main.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/services/tutorial_preferences.dart';

class ExistingLibrary extends LibraryRepository {
  final existing = Book(
      id: 'existing',
      title: 'Istniejąca książka',
      author: 'Anna',
      status: BookStatus.available,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));

  @override
  Future<List<Book>> books() async => [existing];
}

class MemoryPreferences implements TutorialPreferences {
  bool completed = false;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  @override
  Future<bool> isCompleted() async {
    if (failRead) throw StateError('read');
    return completed;
  }

  @override
  Future<void> complete() async {
    if (failWrite) throw StateError('write');
    completed = true;
    writes++;
  }
}

Widget app(TutorialPreferences preferences) => MaterialApp(
      home: TutorialGate(
          preferences: preferences,
          libraryBuilder: (_) => const Scaffold(body: Text('Biblioteka'))),
    );

Future<void> lastPage(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.tap(find.text('Dalej'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
      'completion opens real library and Help preserves books and search',
      (tester) async {
    final preferences = MemoryPreferences();
    final repository = ExistingLibrary();
    await tester.pumpWidget(MaterialApp(
        home: TutorialGate(
      preferences: preferences,
      libraryBuilder: (_) =>
          Scaffold(body: LibraryScreen(repository: repository)),
    )));
    await tester.pumpAndSettle();
    await lastPage(tester);
    await tester.tap(find.text('Zakończ'));
    await tester.pumpAndSettle();
    expect(find.byType(BookCard), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.tap(find.text('Pomoc'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Anna');
    expect(find.byType(BookCard), findsOneWidget);
    expect((await repository.books()).single, same(repository.existing));
    expect(preferences.writes, 1);
  });

  test('local completion persists across preference instances', () async {
    SharedPreferences.setMockInitialValues({'unrelated': 'preserved'});
    expect(await LocalTutorialPreferences().isCompleted(), isFalse);
    await LocalTutorialPreferences().complete();
    expect(await LocalTutorialPreferences().isCompleted(), isTrue);
    expect((await SharedPreferences.getInstance()).getString('unrelated'),
        'preserved');
  });

  test('six slides in feature order with exact Polish copy', () {
    expect(tutorialSlides.map((s) => s.title), [
      'Witaj w Mojej Bibliotece!',
      'Dodawaj książki',
      'Zarządzaj wypożyczeniami',
      'Udostępniaj kod QR',
      'Pilnuj terminów zwrotu',
      'Twoja biblioteka, Twoje zasady',
    ]);
    expect(tutorialSlides.map((s) => s.description), [
      'Twoje książki zawsze pod ręką. Zarządzaj swoją kolekcją i wypożyczeniami w jednym miejscu.',
      'Skanuj kod ISBN, wyszukuj po tytule lub autorze albo dodawaj książki ręcznie. Ustaw własną okładkę.',
      'Zapisuj, komu pożyczasz książki, ustalaj terminy zwrotu i przeglądaj historię.',
      'Po wypożyczeniu pokaż kod QR. Druga osoba może go zeskanować i dodać książkę do listy „Pożyczone od innych”.',
      'Włącz przypomnienia o zwrocie książek, zmieniaj terminy i przedłużaj wypożyczenia.',
      'Książki i historia są przechowywane na Twoim urządzeniu. Możesz korzystać z biblioteki także bez internetu.',
    ]);
  });

  testWidgets('first launch, navigation, finish and restart bypass',
      (tester) async {
    final preferences = MemoryPreferences();
    await tester.pumpWidget(app(preferences));
    await tester.pumpAndSettle();
    expect(find.text(tutorialSlides.first.title), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(find.text('Zakończ'), findsNothing);
    await tester.tap(find.text('Dalej'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 6'), findsOneWidget);
    await tester.tap(find.text('Wstecz'));
    await tester.pumpAndSettle();
    await lastPage(tester);
    expect(find.text('Dalej'), findsNothing);
    await tester.tap(find.text('Zakończ'));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
    expect(preferences.writes, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(preferences));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
  });

  testWidgets('swipe and Android Back never dismiss unfinished onboarding',
      (tester) async {
    final preferences = MemoryPreferences();
    await tester.pumpWidget(app(preferences));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 6'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 / 6'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsOneWidget);
    expect(preferences.completed, isFalse);
  });

  testWidgets('read failure opens library without a launch loop',
      (tester) async {
    await tester.pumpWidget(app(MemoryPreferences()..failRead = true));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
  });

  testWidgets('write failure allows retry before entering library',
      (tester) async {
    final preferences = MemoryPreferences()..failWrite = true;
    await tester.pumpWidget(app(preferences));
    await tester.pumpAndSettle();
    await lastPage(tester);
    await tester.tap(find.text('Zakończ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Spróbuj ponownie'), findsOneWidget);
    expect(find.text('Biblioteka'), findsNothing);
    preferences.failWrite = false;
    await tester.tap(find.text('Zakończ'));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
  });

  testWidgets(
      'Help starts at first slide and closes to unchanged previous route',
      (tester) async {
    final preferences = MemoryPreferences()..completed = true;
    await tester.pumpWidget(MaterialApp(
      home: TutorialGate(
          preferences: preferences,
          libraryBuilder: (_) => const Scaffold(
                  body: Column(children: [
                Text('Istniejąca książka'),
                TutorialHelpButton(),
              ]))),
    ));
    await tester.pumpAndSettle();
    for (final close in ['Zamknij pomoc', 'back', 'finish']) {
      await tester.tap(find.text('Pomoc'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 6'), findsOneWidget);
      if (close == 'finish') {
        await lastPage(tester);
        await tester.tap(find.text('Zakończ'));
      } else if (close == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip(close));
      }
      await tester.pumpAndSettle();
      expect(find.text('Pomoc'), findsOneWidget);
      expect(find.text('Istniejąca książka'), findsOneWidget);
    }
    expect(preferences.completed, isTrue);
    expect(preferences.writes, 0);
  });

  testWidgets(
      'small screen, large text and rotation preserve page without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!),
      home: TutorialScreen(onFinish: () async {}),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(480, 320));
    await tester.pumpAndSettle();
    expect(find.text('6 / 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding makes no platform permission requests',
      (tester) async {
    final calls = <MethodCall>[];
    for (final channel in [
      'flutter.baseflow.com/permissions/methods',
      'dexterous.com/flutter/local_notifications',
      'my_library/reminders',
      'dev.steenbakker.mobile_scanner/scanner/method'
    ]) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add(call);
        return null;
      });
    }
    await tester.pumpWidget(app(MemoryPreferences()));
    await tester.pumpAndSettle();
    await lastPage(tester);
    expect(calls, isEmpty);
  });
}
