import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/data/library_repository.dart';
import 'package:my_library/main.dart';
import 'package:my_library/models/book.dart';
import 'package:my_library/models/genre.dart';
import 'package:my_library/screens/genres.dart';

class GenreWidgetRepository extends LibraryRepository {
  List<Genre> registry = [
    const Genre('', defaultGenre, 0),
    ...starterGenres.map((n) => Genre(n, n, 0))
  ];
  List<Book> collection = [];
  String? savedGenre;
  @override
  Future<List<Genre>> genres() async => registry
      .map((g) => Genre(
          g.id, g.name, collection.where((b) => b.genre == g.name).length))
      .toList();
  @override
  Future<List<Book>> books() async => collection;
  @override
  Future<List<HistoryEntry>> history({String? bookId}) async => [];
  @override
  Future<Genre> saveGenre(String input, {String? id}) async {
    final name = validateGenreName(input);
    if (registry.any((g) =>
        normalizedGenre(g.name) == normalizedGenre(name) && g.id != id)) {
      throw const GenreException('Ten gatunek już istnieje.');
    }
    final g = Genre(id ?? name, name, 0);
    String? previous;
    if (id != null) {
      final old = registry.singleWhere((g) => g.id == id);
      previous = old.name;
      registry.remove(old);
      collection = collection
          .map((b) => b.genre == old.name ? b.copyWith(genre: name) : b)
          .toList();
    }
    registry.add(g);
    genreChanges.value = GenreChange(previous, name);
    return g;
  }

  @override
  Future<void> deleteGenre(String id) async {
    final g = registry.singleWhere((g) => g.id == id);
    registry.remove(g);
    collection = collection
        .map((b) => b.genre == g.name ? b.copyWith(genre: defaultGenre) : b)
        .toList();
    genreChanges.value = GenreChange(g.name, null);
  }

  @override
  Future<Book> addBook(
      {required String title,
      required String author,
      String description = '',
      String? coverUrl,
      String? barcode,
      String condition = 'Dobry',
      String genre = defaultGenre}) async {
    savedGenre = genre;
    final b = makeBook('new', genre: genre);
    collection.add(b);
    return b;
  }

  @override
  Future<Book> updateBook(
      {required String id,
      required String title,
      required String author,
      String? barcode,
      required String condition,
      String? coverUrl,
      bool updateCover = false,
      String? genre}) async {
    savedGenre = genre;
    final b = collection.singleWhere((b) => b.id == id).copyWith(genre: genre);
    collection = [b];
    return b;
  }
}

Book makeBook(String id,
        {String genre = defaultGenre,
        BookStatus status = BookStatus.available,
        String? title}) =>
    Book(
        id: id,
        title: title ?? id,
        author: 'Anna',
        genre: genre,
        status: status,
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025));

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('Polish genre counts handle singular, few and teen exceptions', () {
    const expected = {
      0: '0 książek',
      1: '1 książka',
      2: '2 książki',
      4: '4 książki',
      5: '5 książek',
      11: '11 książek',
      12: '12 książek',
      14: '14 książek',
      21: '21 książek',
      22: '22 książki',
      25: '25 książek',
      101: '101 książek',
      112: '112 książek',
    };
    for (final entry in expected.entries) {
      expect(genreBookCount(entry.key), entry.value);
    }
  });

  testWidgets('management list and delete preview use Polish book counts',
      (tester) async {
    for (final count in [1, 2, 5]) {
      final repo = GenreWidgetRepository()
        ..registry = [const Genre('p', 'Poezja', 0)]
        ..collection =
            List.generate(count, (i) => makeBook('book-$i', genre: 'Poezja'));
      await tester.pumpWidget(MaterialApp(
          key: ValueKey(count), home: ManageGenresScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text(genreBookCount(count)), findsOneWidget);
      await tapVisible(tester, find.text('Usuń gatunek'));
      expect(
          find.textContaining('Przypisane książki: ${genreBookCount(count)}.'),
          findsOneWidget);
      await tapVisible(tester, find.text('Anuluj'));
      expect(repo.collection, hasLength(count));
    }
  });

  testWidgets(
      'Add defaults to Bez gatunku; inline custom creation selects without resetting form',
      (tester) async {
    final repo = GenreWidgetRepository();
    await tester.pumpWidget(MaterialApp(home: AddBookScreen(repository: repo)));
    expect(find.text(defaultGenre), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Draft title');
    await tester.enterText(find.byType(TextFormField).at(1), 'Draft author');
    await tapVisible(tester, find.byType(GenreSelector));
    for (final name in starterGenres) {
      expect(find.text(name), findsOneWidget);
    }
    await tapVisible(tester, find.text('Dodaj gatunek'));
    await tester.enterText(find.byType(TextFormField).last, 'Poezja');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    expect(find.text('Poezja'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        'Draft title');
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Zapisz książkę'));
    expect(repo.savedGenre, 'Poezja');
  });

  testWidgets('Edit initializes saved genre and saves only changed selection',
      (tester) async {
    final repo = GenreWidgetRepository()
      ..collection = [
        makeBook('Existing', genre: 'Horror', status: BookStatus.borrowed)
      ];
    await tester.pumpWidget(MaterialApp(
        home: AddBookScreen(repository: repo, book: repo.collection.single)));
    expect(find.text('Horror'), findsOneWidget);
    await tapVisible(tester, find.byType(GenreSelector));
    await tapVisible(tester, find.text('Fantastyka'));
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Zapisz zmiany'));
    expect(repo.savedGenre, 'Fantastyka');
    expect(repo.collection.single.status, BookStatus.borrowed);
  });

  testWidgets(
      'management validates Polish errors and warns before used/unused deletion',
      (tester) async {
    final repo = GenreWidgetRepository()
      ..registry = [
        const Genre('', defaultGenre, 0),
        const Genre('a', 'Poezja', 0),
        const Genre('b', 'Esej', 0)
      ]
      ..collection = [makeBook('Book', genre: 'Poezja')];
    await tester
        .pumpWidget(MaterialApp(home: ManageGenresScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('1 książka'), findsOneWidget);
    await tapVisible(tester, find.text('Dodaj gatunek'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    expect(find.text('Wpisz nazwę gatunku.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), ' POEZJA ');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    expect(find.text('Ten gatunek już istnieje.'), findsOneWidget);
    await tapVisible(tester, find.text('Anuluj'));
    await tapVisible(tester, find.text('Edytuj gatunek').first);
    expect(find.text('Poezja'), findsWidgets);
    await tester.enterText(find.byType(TextFormField), 'Wiersze');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    expect(repo.collection.single.genre, 'Wiersze');
    // Renaming moves the edited fake entry to the end.
    await tapVisible(tester, find.text('Usuń gatunek').last);
    expect(find.textContaining('Po jego usunięciu książki zostaną'),
        findsOneWidget);
    await tapVisible(tester, find.text('Anuluj'));
    expect(repo.collection.single.genre, 'Wiersze');
    await tapVisible(tester, find.text('Usuń gatunek').last);
    await tapVisible(tester, find.text('Usuń i zmień na „Bez gatunku”'));
    expect(repo.collection.single.genre, defaultGenre);
    await tapVisible(tester, find.text('Usuń gatunek'));
    expect(find.text('Usunąć gatunek „Esej”?'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Usuń'));
    expect(repo.registry, hasLength(1));
  });

  testWidgets(
      'genre filter combines with search status both sorts and keeps total',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = GenreWidgetRepository()
      ..collection = [
        makeBook('z',
            title: 'Zebra', genre: 'Horror', status: BookStatus.borrowed),
        makeBook('a',
            title: 'Atlas', genre: 'Horror', status: BookStatus.borrowed),
        makeBook('b', title: 'Other', genre: 'Fantastyka'),
      ];
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryScreen(repository: repo))));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(GenreSelector));
    expect(find.text('Wszystkie gatunki'), findsWidgets);
    await tapVisible(tester, find.text('Horror'));
    await tapVisible(tester, find.widgetWithText(FilterChip, 'Wypożyczone'));
    List<String> titles() => tester
        .widgetList<BookCard>(find.byType(BookCard))
        .map((w) => w.book.title)
        .toList();
    expect(titles(), ['Zebra', 'Atlas']);
    await tapVisible(tester, find.byTooltip('Sortuj A–Z'));
    expect(titles(), ['Atlas', 'Zebra']);
    await tapVisible(tester, find.byTooltip('Sortuj według ostatnio dodanych'));
    expect(titles(), ['Zebra', 'Atlas']);
    await tester.enterText(find.byType(TextField), 'anna');
    await tester.pumpAndSettle();
    expect(titles(), hasLength(2));
    await tester.enterText(find.byType(TextField), 'atlas');
    await tester.pumpAndSettle();
    expect(titles(), ['Atlas']);
    expect(find.text('3 książek w kolekcji'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilterChip, 'Dostępne'));
    expect(
        find.text('Brak książek pasujących do wyszukiwania.'), findsOneWidget);
  });

  testWidgets('filter follows renamed genre and clears deleted genre',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = GenreWidgetRepository()
      ..registry = [
        const Genre('', defaultGenre, 0),
        const Genre('h', 'Horror', 0)
      ];
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryScreen(repository: repo))));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(GenreSelector));
    await tapVisible(tester, find.text('Horror'));
    await tapVisible(tester, find.text('Zarządzaj gatunkami'));
    await tapVisible(tester, find.text('Edytuj gatunek'));
    await tester.enterText(find.byType(TextFormField), 'Groza');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Groza'), findsOneWidget);
    await tapVisible(tester, find.text('Zarządzaj gatunkami'));
    await tapVisible(tester, find.text('Usuń gatunek'));
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Usuń'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Wszystkie gatunki'), findsOneWidget);
  });

  testWidgets(
      'Book Details refreshes renamed genre even when edit form is canceled',
      (tester) async {
    final repo = GenreWidgetRepository()
      ..registry = [
        const Genre('', defaultGenre, 0),
        const Genre('h', 'Horror', 0)
      ]
      ..collection = [makeBook('Existing', genre: 'Horror')];
    await tester.pumpWidget(MaterialApp(
        home:
            BookDetailsScreen(book: repo.collection.single, repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Gatunek'), findsOneWidget);
    expect(find.text('Horror'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Edytuj książkę'));
    await tapVisible(tester, find.byType(GenreSelector));
    await tapVisible(tester, find.text('Zarządzaj gatunkami'));
    await tapVisible(tester, find.text('Edytuj gatunek'));
    await tester.enterText(find.byType(TextFormField).last, 'Groza');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Groza'), findsOneWidget);
    expect(find.text('Horror'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen large text book form and selector do not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = GenreWidgetRepository();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!),
      home: AddBookScreen(
          repository: repo,
          book: makeBook('Existing', genre: 'Literatura historyczna')),
    ));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(GenreSelector));
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('Biografia i autobiografia'));
    expect(find.text('Biografia i autobiografia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'library behind Add Book follows registry changes after canceled form and preserves search sort',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = GenreWidgetRepository()
      ..registry = [
        const Genre('', defaultGenre, 0),
        const Genre('h', 'Horror', 0)
      ]
      ..collection = [
        makeBook('Zebra', genre: 'Horror'),
        makeBook('Atlas', genre: 'Horror')
      ];
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: LibraryScreen(repository: repo),
                  floatingActionButton: FloatingActionButton(
                      onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AddBookScreen(repository: repo))),
                      child: const Icon(Icons.add)),
                ))));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byType(GenreSelector));
    await tapVisible(tester, find.text('Horror'));
    await tester.enterText(find.byType(TextField), 'a');
    await tapVisible(tester, find.byTooltip('Sortuj A–Z'));
    await tapVisible(tester, find.byType(FloatingActionButton));
    await tapVisible(tester, find.byType(GenreSelector));
    await tapVisible(tester, find.text('Zarządzaj gatunkami'));
    await tapVisible(tester, find.text('Edytuj gatunek'));
    await tester.enterText(find.byType(TextFormField).last, 'Groza');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Groza'), findsOneWidget);
    expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'a');
    expect(
        tester
            .widgetList<BookCard>(find.byType(BookCard))
            .map((c) => c.book.title),
        ['Atlas', 'Zebra']);
    await repo.deleteGenre('h');
    await tester.pumpAndSettle();
    expect(find.text('Wszystkie gatunki'), findsOneWidget);
  });

  testWidgets('small screen large text management and dialogs do not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = GenreWidgetRepository()
      ..registry = [
        const Genre('', defaultGenre, 0),
        Genre('long', 'Długi gatunek literacki ' * 2, 0)
      ];
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!),
        home: ManageGenresScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('Usuń gatunek'));
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.text('Anuluj'));
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Dodaj gatunek'));
    await tester.enterText(find.byType(TextFormField), 'a' * 61);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Zapisz'));
    expect(find.text('Nazwa gatunku jest za długa.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
