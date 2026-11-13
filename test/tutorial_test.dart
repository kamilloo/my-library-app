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
  for (var i = 0; i < tutorialSlides.length - 1; i++) {
    expect(find.text('Zakończ'), findsNothing);
    await tester.tap(find.text('Dalej'));
    await tester.pumpAndSettle();
    expect(find.text(tutorialSlides[i + 1].title), findsOneWidget);
  }
  expect(find.text('Zakończ'), findsOneWidget);
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

  test('seven slides in feature order with exact Polish copy and icons', () {
    expect(tutorialSlides.map((s) => s.title), [
      'Witaj w Mojej Bibliotece!',
      'Dodawaj książki',
      'Zarządzaj wypożyczeniami',
      'Udostępniaj kod QR',
      'Proś o przedłużenie',
      'Pilnuj terminów zwrotu',
      'Twoja biblioteka, Twoje zasady',
    ]);
    expect(tutorialSlides.map((s) => s.icon), [
      Icons.menu_book_rounded,
      Icons.document_scanner_outlined,
      Icons.people_alt_outlined,
      Icons.qr_code_2_rounded,
      Icons.sms_outlined,
      Icons.event_available_outlined,
      Icons.phonelink_lock_outlined,
    ]);
    expect(tutorialSlides[4].title, 'Proś o przedłużenie');
    expect(tutorialSlides.map((s) => s.description), [
      'Twoje książki zawsze pod ręką. Zarządzaj swoją kolekcją i wypożyczeniami w jednym miejscu.',
      'Skanuj kod ISBN, wyszukuj po tytule lub autorze albo dodawaj książki ręcznie. Ustaw własną okładkę.',
      'Zapisuj, komu pożyczasz książki, ustalaj terminy zwrotu i przeglądaj historię.',
      'Po wypożyczeniu pokaż kod QR. Druga osoba może go zeskanować i dodać książkę do listy „Pożyczone od innych”.',
      'Wyślij prośbę o przedłużenie wypożyczenia przez SMS. Właściciel zatwierdza nowy termin, a Ty wklejasz potwierdzenie w aplikacji.',
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
    expect(find.text('2 / 7'), findsOneWidget);
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
    expect(find.text('2 / 7'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 / 7'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsOneWidget);
    expect(preferences.completed, isFalse);
  });

  testWidgets('seven pages swipe with SMS fifth and accessible progress',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(app(MemoryPreferences()));
      await tester.pumpAndSettle();
      for (var page = 0; page < tutorialSlides.length; page++) {
        expect(find.text('${page + 1} / ${tutorialSlides.length}'),
            findsOneWidget);
        expect(
            find.bySemanticsLabel(
                'Strona ${page + 1} z ${tutorialSlides.length}'),
            findsOneWidget);
        expect(find.text(tutorialSlides[page].title), findsOneWidget);
        final dots = find.byWidgetPredicate((widget) =>
            widget is Container && widget.constraints?.maxHeight == 8);
        expect(dots, findsNWidgets(tutorialSlides.length));
        expect(find.text('Zakończ'),
            page == tutorialSlides.length - 1 ? findsOneWidget : findsNothing);
        expect(find.byTooltip('Zamknij pomoc'), findsNothing);
        if (page == 4) {
          expect(find.byIcon(Icons.sms_outlined), findsOneWidget);
          expect(find.text(tutorialSlides[4].description), findsOneWidget);
          await tester.tap(find.text('Wstecz'));
          await tester.pumpAndSettle();
          expect(find.text(tutorialSlides[3].title), findsOneWidget);
          await tester.tap(find.text('Dalej'));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text(tutorialSlides[3].title), findsOneWidget);
          await tester.tap(find.text('Dalej'));
          await tester.pumpAndSettle();
        }
        if (page < tutorialSlides.length - 1) {
          await tester.drag(find.byType(PageView), const Offset(-600, 0));
          await tester.pumpAndSettle();
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('existing v1 completion bypasses seven-slide onboarding',
      (tester) async {
    SharedPreferences.setMockInitialValues({'tutorial_completed_v1': true});
    expect(LocalTutorialPreferences.completionKey, 'tutorial_completed_v1');
    await tester.pumpWidget(app(LocalTutorialPreferences()));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteka'), findsOneWidget);
    expect(find.byType(TutorialScreen), findsNothing);
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
      expect(find.text('1 / 7'), findsOneWidget);
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
    for (var i = 0; i < tutorialSlides.length - 1; i++) {
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(const Size(480, 320));
    await tester.pumpAndSettle();
    expect(find.text('7 / 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding makes no platform permission requests',
      (tester) async {
    final calls = <MethodCall>[];
    for (final channel in [
      'flutter.baseflow.com/permissions/methods',
      'dexterous.com/flutter/local_notifications',
      'my_library/reminders',
      'plugins.flutter.io/url_launcher',
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
