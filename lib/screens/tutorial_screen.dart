import 'package:flutter/material.dart';

import '../services/tutorial_preferences.dart';

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
        'Wysyłasz SMS ręcznie w swojej aplikacji do wiadomości. Otwarcie edytora SMS nie potwierdza wysłania ani dostarczenia wiadomości.\n\n'
        'Treść SMS może być widoczna dla operatora lub innych usług. SMS nie zapewnia szyfrowania od końca do końca ani niezależnego potwierdzenia tożsamości nadawcy.\n\n'
        'Moja Biblioteka nie odczytuje SMS-ów automatycznie i nie synchronizuje urządzeń. Ważne zmiany potwierdzajcie bezpośrednio ze sobą.\n\n'
        'Opcjonalny numer odbiorcy uzupełnia aplikację SMS. Zapisz go osobnym przyciskiem tylko na tym urządzeniu; zapisanie pustego numeru usuwa kontakt.',
    Icons.sms_outlined,
  ),
  TutorialSlide(
    'Wypożyczenia i synchronizacja danych',
    'Każde urządzenie przechowuje własną kopię informacji o wypożyczeniu. Zapis właściciela jest rozstrzygający dla rzeczywistego wypożyczenia. Osoba pożyczająca ma oddzielną lokalną kopię na liście „Pożyczone”, poza kolekcją własnych książek.\n\n'
        'Daty i statusy nie synchronizują się automatycznie. Skanowanie QR importuje kopię informacji, a SMS służy do komunikacji między stronami. Czytelną wiadomość dodasz przez „Dodaj z SMS”, a książkę od dowolnej osoby przez „Dodaj ręcznie”. Po uzgodnieniu zmian może być konieczna aktualizacja własnych lokalnych zapisów.\n\n'
        'Usunięcie lokalnego zapisu z listy „Pożyczone” nie usuwa zapisu właściciela. Kod QR nie potwierdza tożsamości ani własności książki.',
    Icons.sync_disabled_outlined,
  ),
];

class LoanHelpScreen extends StatelessWidget {
  const LoanHelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pomoc')),
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
      'Udostępniaj kod QR',
      'Po wypożyczeniu pokaż kod QR. W „Pożyczone” wybierz „Skanuj kod QR”, „Dodaj z SMS” lub „Dodaj ręcznie”. SMS wymaga odczytania wiadomości, sprawdzenia pól i potwierdzenia zapisu. Wpis ręczny działa bez internetu i bez aplikacji u właściciela.',
      Icons.qr_code_2_rounded),
  TutorialSlide(
      'Proś o przedłużenie',
      'Przygotuj prośbę o przedłużenie i wyślij ją ręcznie w aplikacji SMS. Po uzgodnieniu z właścicielem wybierz „Zmień termin zwrotu” i popraw lokalny zapis.',
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
      {required this.preferences, required this.libraryBuilder, super.key});
  final TutorialPreferences preferences;
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
    return TutorialScreen(onFinish: () async {
      await widget.preferences.complete();
      if (mounted) setState(() => completed = true);
    });
  }
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen(
      {required this.onFinish, this.manual = false, super.key});
  final Future<void> Function() onFinish;
  final bool manual;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final controller = PageController();
  int page = 0;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void move(int value) => controller.jumpToPage(value);

  Future<void> finish() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
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
                onPageChanged: (value) => setState(() => page = value),
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
                          : () => move(page + 1),
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
