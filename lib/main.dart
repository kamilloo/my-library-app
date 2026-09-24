import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/library_repository.dart';
import 'models/book.dart';
import 'screens/scan_book_screen.dart';

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

class _LibraryShellState extends State<LibraryShell> {
  final repository = LibraryRepository();
  int index = 0;
  int refreshKey = 0;

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
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
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
                            await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => BookDetailsScreen(
                                        book: book,
                                        repository: widget.repository)));
                            setState(() {});
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
                  ])),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.book,
    required this.width,
    required this.height,
  });

  final Book book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        book.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: width > 80 ? 18 : 11,
        ),
      ),
    );

    if (book.coverUrl == null || book.coverUrl!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        book.coverUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
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
  const AddBookScreen({required this.repository, super.key});
  final LibraryRepository repository;

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final author = TextEditingController();
  final isbn = TextEditingController();
  String condition = 'Dobry';
  String? coverUrl;
  bool saving = false;

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
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    await widget.repository.addBook(
      title: title.text,
      author: author.text,
      coverUrl: coverUrl,
      barcode: isbn.text,
      condition: condition,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dodaj książkę')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          FilledButton.icon(
            onPressed: scanBook,
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
          Form(
            key: formKey,
            child: Column(children: [
              if (coverUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    coverUrl!,
                    width: 100,
                    height: 144,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 18),
              ],
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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'ISBN lub kod kreskowy (opcjonalnie)')),
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
                      onPressed: saving ? null : save,
                      child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Text(
                              saving ? 'Zapisywanie…' : 'Zapisz książkę')))),
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
    setState(() =>
        book = book.copyWith(status: BookStatus.available, clearLoan: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Szczegóły książki')),
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

String _date(DateTime date) => '${date.month}/${date.day}/${date.year}';

IconData _historyIcon(String action) => switch (action) {
      'added' => Icons.bookmark_add_outlined,
      'borrowed' => Icons.handshake_outlined,
      'returned' => Icons.keyboard_return,
      'given' => Icons.card_giftcard,
      _ => Icons.history,
    };
