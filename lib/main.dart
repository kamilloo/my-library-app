import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/library_repository.dart';
import 'data/library_database.dart';
import 'services/return_reminders.dart';
import 'services/local_reminder_notifications.dart';
import 'screens/return_reminder_settings.dart';
import 'screens/return_date_section.dart';
import 'models/book.dart';
import 'models/isbn.dart';
import 'models/return_date.dart';
import 'services/open_library_service.dart';
import 'screens/scan_book_screen.dart';
import 'screens/book_cover.dart';
import 'screens/book_history_section.dart';
import 'services/cover_picker.dart';
import 'services/cover_storage.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyLibraryApp());
}

class MyLibraryApp extends StatelessWidget {
  const MyLibraryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Moja biblioteka',
        locale: const Locale('pl'),
        supportedLocales: const [Locale('pl')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff315c45),
            brightness: Brightness.light,
            surface: const Color(0xfffffdf8),
          ),
          scaffoldBackgroundColor: const Color(0xfff5f2eb),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide.none,
            ),
          ),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
            ),
          ),
        ),
        home: const LibraryShell(),
      );
}

class LibraryShell extends StatefulWidget {
  const LibraryShell({super.key});

  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell>
    with WidgetsBindingObserver {
  final repository = LibraryRepository(
    reminders:
        ReturnReminders(LibraryDatabase.instance, LocalReminderNotifications()),
  );

  Future<void> refreshReminders() async {
    try {
      await repository.reminders!.reconcile();
    } catch (error) {
      debugPrint('Reminder synchronization deferred: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshReminders());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  int index = 0;
  int refreshKey = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refreshReminders());
    if (defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) => recoverCover());
    }
  }

  Future<void> recoverCover() async {
    final picker = CoverPicker();
    var handedOff = false;
    try {
      final recovered = await picker.recover();
      if (recovered == null || !mounted) return;
      final result = Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => AddBookScreen(
                  repository: repository,
                  initialCover: recovered,
                  coverPicker: picker)));
      // The form now owns cleanup, including an in-flight save after back.
      handedOff = true;
      final added = await result;
      if (added == true && mounted) setState(() => refreshKey++);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nie udało się odzyskać zdjęcia. Wybierz okładkę ponownie.')));
      }
    } finally {
      if (!handedOff) await picker.releaseExcept();
    }
  }

  Future<void> openAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddBookScreen(repository: repository)),
    );
    if (added == true) setState(() => refreshKey++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: index,
            children: [
              LibraryScreen(
                  key: ValueKey('library-$refreshKey'), repository: repository),
              HistoryScreen(
                  key: ValueKey('history-$refreshKey'), repository: repository),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.large(
          onPressed: openAdd,
          tooltip: 'Dodaj książkę',
          child: const Icon(Icons.add),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.local_library_outlined),
                selectedIcon: Icon(Icons.local_library),
                label: 'Biblioteka'),
            NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'Historia'),
          ],
        ),
      );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.repository, super.key});
  final LibraryRepository repository;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '';
  BookStatus? filter;
  bool alphabetical = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Book>>(
        future: widget.repository.books(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var books = snapshot.data!.where((book) {
            final text = '${book.title} ${book.author}'.toLowerCase();
            return text.contains(query.toLowerCase()) &&
                (filter == null || book.status == filter);
          }).toList();
          if (alphabetical) books.sort((a, b) => a.title.compareTo(b.title));
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
              children: [
                Text('${snapshot.data!.length} książek w kolekcji',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text('Moja biblioteka',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                SearchBar(
                  leading: const Icon(Icons.search),
                  hintText: 'Szukaj tytułu lub autora',
                  onChanged: (value) => setState(() => query = value),
                  trailing: [
                    IconButton(
                      icon: const Icon(Icons.sort),
                      tooltip: alphabetical
                          ? 'Sortuj według ostatnio dodanych'
                          : 'Sortuj A–Z',
                      onPressed: () =>
                          setState(() => alphabetical = !alphabetical),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                        label: const Text('Wszystkie'),
                        selected: filter == null,
                        onSelected: (_) => setState(() => filter = null)),
                    FilterChip(
                        label: const Text('Dostępne'),
                        selected: filter == BookStatus.available,
                        onSelected: (_) =>
                            setState(() => filter = BookStatus.available)),
                    FilterChip(
                        label: const Text('Wypożyczone'),
                        selected: filter == BookStatus.borrowed,
                        onSelected: (_) =>
                            setState(() => filter = BookStatus.borrowed)),
                    FilterChip(
                        label: const Text('Oddane na stałe'),
                        selected: filter == BookStatus.given,
                        onSelected: (_) =>
                            setState(() => filter = BookStatus.given)),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Twoje książki',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(alphabetical ? 'A–Z' : 'Ostatnio dodane',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                const SizedBox(height: 10),
                if (books.isEmpty)
                  const _EmptyState()
                else
                  ...books.map((book) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: BookCard(
                          book: book,
                          onTap: () async {
                            await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => BookDetailsScreen(
                                        book: book,
                                        repository: widget.repository)));
                            if (mounted) setState(() {});
                          },
                        ),
                      )),
              ],
            ),
          );
        },
      );
}

class BookCard extends StatelessWidget {
  const BookCard({required this.book, required this.onTap, super.key});
  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _BookCover(book: book, width: 54, height: 76),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(book.author,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    _StatusChip(book: book),
                    if (book.status == BookStatus.borrowed)
                      Text(
                          book.returnDate == null
                              ? 'Nie ustawiono terminu zwrotu'
                              : 'Termin zwrotu: ${formatReturnDate(book.returnDate!)}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ])),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

class _BookCover extends StatelessWidget {
  const _BookCover(
      {required this.book, required this.width, required this.height});
  final Book book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => BookCover(
      reference: book.coverUrl,
      title: book.title,
      width: width,
      height: height);
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final label = switch (book.status) {
      BookStatus.available => 'Dostępna',
      BookStatus.borrowed =>
        'Wypożyczona${book.borrowedBy == null ? '' : ' · ${book.borrowedBy}'}',
      BookStatus.given => 'Oddana na stałe',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(99)),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
    );
  }
}

class AddBookScreen extends StatefulWidget {
  const AddBookScreen(
      {required this.repository,
      this.book,
      this.coverPicker,
      this.initialCover,
      this.isbnService,
      super.key});
  final OpenLibraryService? isbnService;
  final CoverPicker? coverPicker;
  final String? initialCover;
  final LibraryRepository repository;
  final Book? book;

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final author = TextEditingController();
  final isbn = TextEditingController();
  bool lookingUp = false;
  String? lookupMessage;
  late final isbnService = widget.isbnService ?? OpenLibraryService();
  String condition = 'Dobry';
  String? coverUrl;
  bool saving = false;
  bool selectingCover = false;
  late final CoverPicker coverPicker = widget.coverPicker ?? CoverPicker();

  bool get editing => widget.book != null;

  @override
  void initState() {
    super.initState();
    final book = widget.book;
    if (book != null) {
      title.text = book.title;
      author.text = book.author;
      isbn.text = book.barcode ?? '';
      condition = book.condition;
      coverUrl = book.coverUrl;
    }
    coverUrl = widget.initialCover ?? coverUrl;
  }

  Future<void> selectCover({ImageSource? source}) async {
    if (saving || selectingCover) return;
    setState(() => selectingCover = true);
    try {
      final result = source != null
          ? await coverPicker.pick(source)
          : await coverPicker.adjust(
              (await widget.repository.coverStorage.resolve(coverUrl!)).path);
      if (mounted && result != null) setState(() => coverUrl = result);
      await coverPicker.releaseExcept(mounted ? coverUrl : null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nie udało się otworzyć zdjęcia. Sprawdź dostęp do aparatu w ustawieniach lub wybierz zdjęcie z urządzenia.')));
      }
    } finally {
      if (mounted) {
        setState(() => selectingCover = false);
      } else {
        await coverPicker.releaseExcept();
      }
    }
  }

  Future<void> lookupIsbn() async {
    if (lookingUp || saving || selectingCover) return;
    final normalized = normalizeIsbn(isbn.text);
    if (normalized == null) {
      setState(() => lookupMessage = 'Wpisz poprawny ISBN-10 lub ISBN-13.');
      return;
    }
    final requestedIsbn = isbn.text;
    setState(() {
      lookingUp = true;
      lookupMessage = null;
    });
    try {
      final book = await isbnService.lookupByIsbn(normalized);
      if (!mounted || saving || isbn.text != requestedIsbn) return;
      if (book == null) {
        setState(() => lookupMessage =
            'Nie znaleziono książki. Możesz wpisać dane ręcznie lub spróbować ponownie.');
        return;
      }
      // Check current values after the await, including edits made while loading.
      if (title.text.trim().isEmpty) title.text = book.title;
      if (author.text.trim().isEmpty) author.text = book.author;
      setState(() {
        coverUrl ??= book.coverUrl;
        lookupMessage =
            'Uzupełniono puste pola z Open Library. Wpisane dane zachowano.';
      });
    } on TimeoutException {
      if (mounted && isbn.text == requestedIsbn) {
        setState(() => lookupMessage =
            'Przekroczono czas wyszukiwania. Spróbuj ponownie.');
      }
    } catch (_) {
      if (mounted && isbn.text == requestedIsbn) {
        setState(() => lookupMessage =
            'Nie udało się pobrać danych. Sprawdź połączenie z internetem i spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => lookingUp = false);
    }
  }

  Future<void> scanBook() async {
    final scanned = await Navigator.push<ScannedBook>(
      context,
      MaterialPageRoute(builder: (_) => const ScanBookScreen()),
    );
    if (scanned == null || !mounted) return;
    title.text = scanned.book.title;
    author.text = scanned.book.author;
    isbn.text = scanned.isbn;
    coverUrl = scanned.book.coverUrl;
    unawaited(coverPicker.releaseExcept(coverUrl));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dane książki uzupełniono z Open Library.')),
    );
  }

  @override
  void dispose() {
    title.dispose();
    author.dispose();
    isbn.dispose();
    if (!saving && !selectingCover) {
      unawaited(coverPicker.releaseExcept());
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || selectingCover || !formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      if (editing) {
        final updated = await widget.repository.updateBook(
          id: widget.book!.id,
          title: title.text,
          author: author.text,
          barcode: isbn.text,
          condition: condition,
          coverUrl: coverUrl,
          updateCover: true,
        );
        if (mounted) Navigator.pop(context, updated);
        return;
      }
      await widget.repository.addBook(
        title: title.text,
        author: author.text,
        coverUrl: coverUrl,
        barcode: isbn.text,
        condition: condition,
      );
      if (mounted) Navigator.pop(context, true);
    } on DuplicateIsbnException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(DuplicateIsbnException.message)),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
            'Unexpected book ${editing ? 'edit' : 'save'} failure: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Nie udało się zapisać książki. Spróbuj ponownie.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      } else {
        await coverPicker.releaseExcept();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: Text(editing ? 'Edytuj książkę' : 'Dodaj książkę')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (!editing) ...[
            FilledButton.icon(
              onPressed: saving || selectingCover ? null : scanBook,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Skanuj kod kreskowy lub QR')),
            ),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('lub wpisz ręcznie')),
                  Expanded(child: Divider())
                ])),
          ],
          Form(
            key: formKey,
            child: Column(children: [
              BookCover(
                  reference: coverUrl,
                  title: 'Okładka',
                  width: 100,
                  height: 144,
                  storage: widget.repository.coverStorage),
              Text(coverUrl == null ? 'Dodaj okładkę' : 'Zmień okładkę'),
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton.icon(
                    onPressed: saving || selectingCover
                        ? null
                        : () => selectCover(source: ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Wybierz zdjęcie z urządzenia')),
                TextButton.icon(
                    onPressed: saving || selectingCover
                        ? null
                        : () => selectCover(source: ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Zrób zdjęcie')),
                if (coverUrl != null && !CoverStorage.isNetwork(coverUrl!))
                  TextButton(
                      onPressed:
                          saving || selectingCover ? null : () => selectCover(),
                      child: const Text('Przytnij i dopasuj')),
                if (coverUrl != null)
                  TextButton(
                      onPressed: saving || selectingCover
                          ? null
                          : () {
                              setState(() => coverUrl = null);
                              unawaited(coverPicker.releaseExcept());
                            },
                      child: const Text('Usuń okładkę')),
              ]),
              if (selectingCover) const LinearProgressIndicator(),
              const SizedBox(height: 18),
              TextFormField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Tytuł'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Wpisz tytuł'
                      : null),
              const SizedBox(height: 14),
              TextFormField(
                  controller: author,
                  decoration: const InputDecoration(labelText: 'Autor'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Wpisz autora'
                      : null),
              const SizedBox(height: 14),
              TextFormField(
                  controller: isbn,
                  keyboardType: TextInputType.text,
                  onChanged: (_) => setState(() => lookupMessage = null),
                  decoration: const InputDecoration(
                      labelText: 'ISBN lub kod kreskowy (opcjonalnie)')),
              if (!editing) ...[
                TextButton.icon(
                  onPressed:
                      lookingUp || saving || selectingCover ? null : lookupIsbn,
                  icon: const Icon(Icons.search),
                  label: const Text('Pobierz dane z ISBN'),
                ),
                if (lookingUp) ...[
                  const LinearProgressIndicator(),
                  const Text('Pobieranie danych…'),
                ],
                if (lookupMessage != null) ...[
                  Text(lookupMessage!, semanticsLabel: lookupMessage),
                  if (!lookingUp)
                    TextButton(
                      onPressed: saving || selectingCover ? null : lookupIsbn,
                      child: const Text('Spróbuj ponownie'),
                    ),
                ],
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                  initialValue: condition,
                  decoration: const InputDecoration(labelText: 'Stan'),
                  items: const ['Nowa', 'Dobry', 'Zużyta']
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) => setState(() => condition = value!)),
              const SizedBox(height: 22),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: saving || selectingCover ? null : save,
                      child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Text(saving
                              ? 'Zapisywanie…'
                              : editing
                                  ? 'Zapisz zmiany'
                                  : 'Zapisz książkę')))),
            ]),
          ),
        ]),
      );
}

class BookDetailsScreen extends StatefulWidget {
  const BookDetailsScreen(
      {required this.book, required this.repository, super.key});
  final Book book;
  final LibraryRepository repository;

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  late Book book = widget.book;

  Future<void> edit() async {
    final updated = await Navigator.push<Book>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddBookScreen(repository: widget.repository, book: book),
      ),
    );
    if (updated != null && mounted) setState(() => book = updated);
  }

  Future<void> lend() async {
    final request = await showModalBottomSheet<_LoanRequest>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const LendSheet());
    if (request == null) return;
    if (request.permanent) {
      await widget.repository.giveBook(book, request.borrower);
      book =
          book.copyWith(status: BookStatus.given, borrowedBy: request.borrower);
    } else {
      await widget.repository
          .lendBook(book, request.borrower, request.returnDate);
      book = book.copyWith(
          status: BookStatus.borrowed,
          borrowedBy: request.borrower,
          borrowedDate: DateTime.now(),
          returnDate: request.returnDate);
    }
    if (mounted) setState(() {});
  }

  Future<void> returnBook() async {
    await widget.repository.returnBook(book);
    if (!mounted) return;
    setState(() =>
        book = book.copyWith(status: BookStatus.available, clearLoan: true));
  }

  Future<void> deleteBook() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć książkę?'),
        content: Text(
          'Książka „${book.title}” oraz jej historia zostaną trwale usunięte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteBook(book.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Szczegóły książki'),
          actions: [
            IconButton(
                onPressed: edit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edytuj książkę'),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: _BookCover(book: book, width: 118, height: 168)),
          const SizedBox(height: 18),
          Text(book.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text(book.author,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Center(child: _StatusChip(book: book)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _Detail(label: 'Stan', value: book.condition)),
            const SizedBox(width: 10),
            Expanded(child: _Detail(label: 'Kategoria', value: book.directory))
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Detail(label: 'ISBN', value: book.barcode ?? '—')),
            const SizedBox(width: 10),
            Expanded(
                child: _Detail(label: 'Dodano', value: _date(book.createdAt)))
          ]),
          const SizedBox(height: 24),
          if (book.status == BookStatus.borrowed) ...[
            ReturnDateSection(
              book: book,
              repository: widget.repository,
              onBookChanged: (updated) => setState(() => book = updated),
            ),
            const SizedBox(height: 20),
          ],
          BookHistorySection(
            key: ValueKey('${book.id}:${book.updatedAt.toIso8601String()}'),
            repository: widget.repository,
            bookId: book.id,
          ),
          if (book.status == BookStatus.borrowed &&
              widget.repository.reminders != null) ...[
            const SizedBox(height: 20),
            ReturnReminderSettings(
              key: ValueKey(
                  'reminder-${book.id}:${book.updatedAt.toIso8601String()}'),
              book: book,
              repository: widget.repository,
            ),
          ],
          if (book.description.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(book.description)
          ],
          const SizedBox(height: 24),
          if (book.status == BookStatus.available)
            FilledButton(
                onPressed: lend,
                child: const Padding(
                    padding: EdgeInsets.all(15),
                    child: Text('Wypożycz książkę')))
          else if (book.status == BookStatus.borrowed)
            FilledButton(
                onPressed: returnBook,
                child: const Padding(
                    padding: EdgeInsets.all(15),
                    child: Text('Oznacz jako zwróconą'))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: deleteBook,
            icon: const Icon(Icons.delete_outline),
            label: const Padding(
              padding: EdgeInsets.all(15),
              child: Text('Usuń książkę'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ]),
      );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600))
          ])));
}

class LendSheet extends StatefulWidget {
  const LendSheet({super.key});
  @override
  State<LendSheet> createState() => _LendSheetState();
}

class _LendSheetState extends State<LendSheet> {
  final borrower = TextEditingController();
  bool permanent = false;
  DateTime? returnDate;

  @override
  void dispose() {
    borrower.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wypożycz książkę',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              TextField(
                  controller: borrower,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Imię osoby wypożyczającej')),
              const SizedBox(height: 12),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Oddaj na stałe'),
                  value: permanent,
                  onChanged: (value) => setState(() => permanent = value)),
              if (!permanent)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Termin zwrotu'),
                    subtitle: Text(returnDate == null
                        ? 'Opcjonalnie'
                        : _date(returnDate!)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final value = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 3650)));
                      if (value != null) setState(() => returnDate = value);
                    }),
              const SizedBox(height: 14),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: borrower.text.trim().isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              _LoanRequest(
                                  borrower.text.trim(), returnDate, permanent)),
                      child: const Padding(
                          padding: EdgeInsets.all(15),
                          child: Text('Potwierdź wypożyczenie')))),
            ]),
      );
}

class _LoanRequest {
  const _LoanRequest(this.borrower, this.returnDate, this.permanent);
  final String borrower;
  final DateTime? returnDate;
  final bool permanent;
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({required this.repository, super.key});
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<HistoryEntry>>(
        future: repository.history(),
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
          children: [
            Text('Wszystkie zmiany zapisane lokalnie',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('Historia',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.data!.isEmpty)
              const _EmptyState(message: 'Brak historii wypożyczeń.')
            else
              ...snapshot.data!.map((item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading:
                        CircleAvatar(child: Icon(_historyIcon(item.action))),
                    title: Text(item.bookTitle),
                    subtitle: Text(item.detail ?? item.action),
                    trailing: Text(_date(item.timestamp),
                        style: Theme.of(context).textTheme.bodySmall),
                  )),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {this.message = 'Brak książek pasujących do wyszukiwania.'});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Column(children: [
        Icon(Icons.auto_stories_outlined,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center)
      ]));
}

String _date(DateTime date) => '${date.day}.${date.month}.${date.year}';

IconData _historyIcon(String action) => switch (action) {
      'added' => Icons.bookmark_add_outlined,
      'borrowed' => Icons.handshake_outlined,
      'returned' => Icons.keyboard_return,
      'given' => Icons.card_giftcard,
      'return_date_changed' => Icons.edit_calendar_outlined,
      'loan_extended' => Icons.more_time,
      _ => Icons.history,
    };
