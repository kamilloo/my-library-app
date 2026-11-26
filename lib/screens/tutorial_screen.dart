import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../models/owner_name.dart';
import '../services/browser_files.dart';
import '../services/tutorial_preferences.dart';
import 'library_backup_screen.dart';
import 'support_screen.dart';
import 'supporter_badge.dart';

class TutorialHelpButton extends StatelessWidget {
  const TutorialHelpButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        icon: const Icon(Icons.help_outline),
        label: const Text('Pomoc'),
        onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => const LoanHelpScreen(),
            )),
      );
}

const loanHelpSections = <TutorialSlide>[
  TutorialSlide(
    'SMS i komunikacja o wypożyczeniu',
    'SMS może wiązać się z opłatami operatora. Długie wiadomości i polskie znaki mogą powodować podział na wiele SMS-ów i dodatkowe opłaty.\n\n'
        'Wybierz „Udostępnij wiadomość”, aby otworzyć systemową listę aplikacji, lub „Kopiuj wiadomość”, aby wkleić tekst w wybranej aplikacji. Wysyłasz wiadomość samodzielnie.\n\n'
        'Treść SMS może być widoczna dla operatora lub innych usług. SMS nie zapewnia szyfrowania od końca do końca ani niezależnego potwierdzenia tożsamości nadawcy.\n\n'
        'Moja Biblioteka nie odczytuje SMS-ów automatycznie i nie synchronizuje urządzeń. Ważne zmiany potwierdzajcie bezpośrednio ze sobą.',
    Icons.sms_outlined,
  ),
  TutorialSlide(
    'Wypożyczenia i synchronizacja danych',
    'Każde urządzenie przechowuje własną kopię informacji o wypożyczeniu. Zapis właściciela jest rozstrzygający dla rzeczywistego wypożyczenia. Osoba pożyczająca ma oddzielną lokalną kopię na liście „Pożyczone”, poza kolekcją własnych książek.\n\n'
        'Daty i statusy nie synchronizują się automatycznie. Skanowanie QR importuje kopię informacji, a SMS służy do komunikacji między stronami. Czytelną wiadomość dodasz przez „Dodaj z SMS”, a książkę od dowolnej osoby przez „Dodaj ręcznie”. Po uzgodnieniu zmian może być konieczna aktualizacja własnych lokalnych zapisów.\n\n'
        'Imię i nazwisko możesz podać na ekranie powitalnym. Jeśli pole pozostanie puste, aplikacja poprosi o nazwę przy kolejnym wypożyczeniu. Nazwa pozostaje na tym urządzeniu, dopóki nie udostępnisz informacji o wypożyczeniu w QR lub SMS. To etykieta wyświetlana jako „Właściciel”, bez weryfikacji tożsamości. Aby ją zmienić lub usunąć, otwórz „Pokaż kod QR”, wybierz „Edytuj nazwę właściciela” i zapisz nową nazwę lub puste pole. Po zmianie pokaż odświeżony kod do zeskanowania.\n\n'
        'Usunięcie lokalnego zapisu z listy „Pożyczone” nie usuwa zapisu właściciela. Kod QR nie potwierdza tożsamości ani własności książki.',
    Icons.sync_disabled_outlined,
  ),
];

const backupHelpTitle = 'Kopia zapasowa i przywracanie danych';

const backupHelp = <({String? heading, String text})>[
  (
    heading: null,
    text:
        'Moja Biblioteka przechowuje Twoje książki i informacje o wypożyczeniach lokalnie na urządzeniu. Dane nie są automatycznie synchronizowane ani zapisywane w chmurze.',
  ),
  (
    heading: 'Jak utworzyć kopię zapasową?',
    text: '1. Otwórz ekran „Kopia zapasowa”.\n'
        '2. Wybierz „Eksportuj kopię zapasową”.\n'
        '3. Wskaż miejsce zapisania pliku, np. folder na telefonie lub Dysk Google.\n'
        '4. Zachowaj kopię pliku poza telefonem, aby móc odzyskać dane w razie jego zgubienia, uszkodzenia lub wymiany.\n\n'
        'Kopia zapasowa zawiera książki, gatunki, historię, informacje o wypożyczeniach, zapisane nazwy właścicieli, ustawienia przypomnień oraz okładki przechowywane lokalnie. Okładki pobierane z internetu mogą wymagać ponownego połączenia z siecią.',
  ),
  (
    heading: 'Jak przywrócić dane?',
    text: '1. Zainstaluj i uruchom aplikację Moja Biblioteka.\n'
        '2. Otwórz ekran „Kopia zapasowa”.\n'
        '3. Wybierz „Przywróć kopię zapasową”.\n'
        '4. Wskaż wcześniej zapisany plik kopii zapasowej.\n'
        '5. Przeczytaj ostrzeżenie i potwierdź przywrócenie danych.\n'
        '6. Po zakończeniu sprawdź, czy Twoje książki i historia są dostępne.',
  ),
  (
    heading: 'Ważne informacje',
    text: 'Przywrócenie kopii zapasowej zastępuje wszystkie dane aktualnie zapisane w aplikacji. Nie łączy dwóch bibliotek. Przed przywróceniem warto wykonać kopię obecnych danych.\n\n'
        'Plik kopii zapasowej może zawierać dane osobowe, w tym imiona i nazwiska właścicieli oraz osób wypożyczających książki. Przechowuj go w bezpiecznym miejscu i nie udostępniaj osobom nieupoważnionym.\n\n'
        'Kopia zapasowa nie jest tworzona automatycznie. Wykonuj ją regularnie, szczególnie po dodaniu nowych książek lub zmianie informacji o wypożyczeniach.\n\n'
        'Odinstalowanie aplikacji lub wyczyszczenie jej danych może spowodować utratę całej lokalnej biblioteki. Dane można odzyskać tylko wtedy, gdy wcześniej zapisano kopię zapasową.',
  ),
];

class _HelpTitle extends StatelessWidget {
  const _HelpTitle();

  @override
  Widget build(BuildContext context) {
    const title = Text('Pomoc');
    if (SupporterBillingScope.of(context)?.owned != true) return title;
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SupporterBadgeImage(size: 36),
        SizedBox(width: 8),
        Flexible(child: title),
      ],
    );
  }
}

class LoanHelpScreen extends StatelessWidget {
  const LoanHelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const _HelpTitle()),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.slideshow_outlined),
                label: const Text('Samouczek — 7 slajdów'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (tutorialContext) => TutorialScreen(
                      manual: true,
                      onFinish: () async => Navigator.pop(tutorialContext),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Kopia zapasowa'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LibraryBackupScreen()),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.favorite),
                label: const Text(supportScreenTitle),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text('Wyszukiwanie i gatunki',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 12),
              const Text(
                'W „Moje książki” szukaj według tytułu lub autora. '
                'Dotknij nazwy gatunku lub „Wszystkie gatunki”, aby zmienić filtr, '
                'dodać gatunek albo wybrać „Zarządzaj gatunkami”.\n\n'
                'W „Historii” szukaj według tytułu lub autora, jeśli książka '
                'wciąż jest w kolekcji. W „Pożyczone” możesz też wpisać '
                'nazwę właściciela.',
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 16),
                FutureBuilder<bool>(
                  future: offlineResourcesReady(),
                  builder: (context, snapshot) {
                    final status = switch (snapshot.data) {
                      true => 'Zasoby do pracy offline są gotowe.',
                      false => 'Tryb offline nie jest gotowy.',
                      null => 'Sprawdzanie zasobów do pracy offline…',
                    };
                    return Semantics(liveRegion: true, child: Text(status));
                  },
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Możesz przeglądać i edytować zapisane książki, zarządzać '
                'wypożyczeniami oraz skanować kody bez internetu. Pobieranie '
                'informacji o nowych książkach z Open Library wymaga połączenia.',
              ),
              for (final section in loanHelpSections) ...[
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(section.title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 12),
                Text(section.description),
              ],
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(backupHelpTitle,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              for (final paragraph in backupHelp) ...[
                if (paragraph.heading != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(paragraph.heading!,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
                const SizedBox(height: 12),
                Text(paragraph.text),
              ],
            ],
          ),
        ),
      );
}

class TutorialSlide {
  const TutorialSlide(this.title, this.description, this.icon);
  final String title;
  final String description;
  final IconData icon;
}

// Append future features here only after their implementation has merged.
const tutorialSlides = [
  TutorialSlide(
      'Witaj w Mojej Bibliotece!',
      'Twoje książki zawsze pod ręką. Zarządzaj swoją kolekcją i wypożyczeniami w jednym miejscu.',
      Icons.menu_book_rounded),
  TutorialSlide(
      'Dodawaj książki',
      'Skanuj kod ISBN, wyszukuj po tytule lub autorze albo dodawaj książki ręcznie. Ustaw własną okładkę.',
      Icons.document_scanner_outlined),
  TutorialSlide(
      'Zarządzaj wypożyczeniami',
      'Zapisuj, komu pożyczasz książki, ustalaj terminy zwrotu i przeglądaj historię.',
      Icons.people_alt_outlined),
  TutorialSlide(
      'Pokazuj kod QR',
      'Po wypożyczeniu pokaż kod QR. W „Pożyczone” wybierz „Skanuj kod QR”, „Dodaj z SMS” lub „Dodaj ręcznie”. SMS wymaga odczytania wiadomości, sprawdzenia pól i potwierdzenia zapisu. Wpis ręczny działa bez internetu i bez aplikacji u właściciela.',
      Icons.qr_code_2_rounded),
  TutorialSlide(
      'Proś o przedłużenie',
      'Przygotuj prośbę o przedłużenie, skopiuj ją lub udostępnij w wybranej aplikacji i wyślij samodzielnie. Po uzgodnieniu z właścicielem wybierz „Zmień termin zwrotu” i popraw lokalny zapis.',
      Icons.sms_outlined),
  TutorialSlide(
      'Pilnuj terminów zwrotu',
      'Włącz przypomnienia o zwrocie książek, zmieniaj terminy i przedłużaj wypożyczenia.',
      Icons.event_available_outlined),
  TutorialSlide(
      'Twoja biblioteka, Twoje zasady',
      'Książki i historia są przechowywane na Twoim urządzeniu. Możesz korzystać z biblioteki także bez internetu.',
      Icons.phonelink_lock_outlined),
];

class TutorialGate extends StatefulWidget {
  const TutorialGate(
      {required this.preferences,
      required this.libraryBuilder,
      this.repository,
      super.key});
  final TutorialPreferences preferences;
  final LibraryRepository? repository;
  final WidgetBuilder libraryBuilder;

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate> {
  bool? completed;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    bool value;
    try {
      value = await widget.preferences.isCompleted();
    } catch (_) {
      // A broken preference store must never trap users outside their library.
      value = true;
    }
    if (mounted) setState(() => completed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (completed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (completed!) return widget.libraryBuilder(context);
    final repository = widget.repository;
    return TutorialScreen(
      saveOwnerName: repository == null
          ? null
          : (name) async {
              if (await repository.preferredOwnerName() == null) {
                await repository.savePreferredOwnerName(name);
              }
            },
      onFinish: () async {
        await widget.preferences.complete();
        if (mounted) setState(() => completed = true);
      },
    );
  }
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen(
      {required this.onFinish,
      this.saveOwnerName,
      this.manual = false,
      super.key});
  final Future<void> Function() onFinish;
  final Future<void> Function(String)? saveOwnerName;
  final bool manual;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final controller = PageController();
  int page = 0;
  bool saving = false;
  String ownerName = '';
  String? ownerError;
  String? error;

  bool validateWelcomeName() {
    try {
      validateOwnerName(ownerName);
      return true;
    } on FormatException catch (error) {
      setState(() => ownerError = error.message);
      move(0);
      return false;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void move(int value) => controller.jumpToPage(value);

  Future<void> finish() async {
    if (saving || !validateWelcomeName()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final name = validateOwnerName(ownerName);
      if (name != null) await widget.saveOwnerName?.call(name);
      await widget.onFinish();
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Nie udało się zapisać ustawienia. Spróbuj ponownie.';
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: widget.manual && !saving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !saving && page > 0) move(page - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Jak korzystać z aplikacji'),
          actions: [
            if (widget.manual)
              IconButton(
                tooltip: 'Zamknij pomoc',
                onPressed: saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: tutorialSlides.length,
                onPageChanged: (value) {
                  if (page == 0) FocusScope.of(context).unfocus();
                  setState(() => page = value);
                },
                itemBuilder: (context, index) {
                  final slide = tutorialSlides[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(children: [
                          const SizedBox(height: 24),
                          ExcludeSemantics(
                            child: CircleAvatar(
                              radius: 64,
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Icon(slide.icon,
                                  size: 72,
                                  color: theme.colorScheme.onPrimaryContainer),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(slide.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium),
                          const SizedBox(height: 20),
                          Text(slide.description,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge),
                          if (index == 0 && widget.saveOwnerName != null) ...[
                            const SizedBox(height: 20),
                            TextFormField(
                              initialValue: ownerName,
                              enabled: !saving,
                              textCapitalization: TextCapitalization.words,
                              maxLength: ownerNameMaxLength,
                              onChanged: (value) => setState(() {
                                ownerName = value;
                                ownerError = null;
                              }),
                              decoration: InputDecoration(
                                labelText: 'Twoje imię i nazwisko',
                                errorText: ownerError,
                              ),
                            ),
                            const Text(
                              'Opcjonalnie. Nazwa pojawi się jako „Właściciel” '
                              'w udostępnianych informacjach o wypożyczeniu.',
                            ),
                          ],
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            Semantics(
              liveRegion: true,
              label: 'Strona ${page + 1} z ${tutorialSlides.length}',
              child: ExcludeSemantics(
                  child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < tutorialSlides.length; i++)
                    Container(
                      margin: const EdgeInsets.all(4),
                      width: i == page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == page
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ]),
                Text('${page + 1} / ${tutorialSlides.length}'),
              ])),
            ),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(error!, semanticsLabel: error)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton(
                  onPressed: page == 0 || saving ? null : () => move(page - 1),
                  child: const Text('Wstecz'),
                )),
                const SizedBox(width: 16),
                Expanded(
                    child: FilledButton(
                  onPressed: saving
                      ? null
                      : page == tutorialSlides.length - 1
                          ? finish
                          : () {
                              if (page != 0 || validateWelcomeName()) {
                                move(page + 1);
                              }
                            },
                  child: Text(
                      page == tutorialSlides.length - 1 ? 'Zakończ' : 'Dalej'),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
