# Przyjaciel Biblioteki w Google Play

**Stan wydania:** Task 43 przygotowuje rzeczywisty checkout Google Play w
natywnej kompilacji Android **release**. Jest uruchamiany automatycznie, bez
przełącznika deweloperskiego. Kompilacje profile pozostają bez płatności;
symulacja i testy licencyjne są dostępne wyłącznie w debug po podaniu odpowiedniej
flagi. Zmiana nie jest wdrożona do opublikowanej wersji 17; przed nowym
wydaniem wymagane są przegląd bezpieczeństwa i testy fizyczne.

Oficjalna grafika pochodzi z pliku właściciela `Przyjaciel Biblioteki Badge.png`.
W aplikacji używamy [wersji 576 × 576](../assets/supporter/przyjaciel_biblioteki.png)
bez kadrowania. Po potwierdzeniu własności odznaka pojawia się po lewej stronie
tytułu **Pomoc**. Jej zakup nie zmienia funkcji aplikacji ani danych biblioteki.

## Konfiguracja ręczna

1. Sprawdź, czy konto dewelopera ma aktywny profil płatności sprzedawcy.
   Uzupełnij wymagane dane podatkowe, bankowe i weryfikacyjne.
   [Konfiguracja Google Play](https://developer.android.com/google/play/billing/getting-ready).
2. W aplikacji `com.kamilloo.mylibrary` właściciel wskazał istniejący produkt
   jednorazowy `library_supporter_badge`. Klient wysyła ten identyfikator do Play.
   W szczegółach produktu porównaj pole identyfikatora produktu z polem
   identyfikatora opcji zakupu. Zgłoszone `badge_one_time` zawiera podkreślenia,
   a identyfikatory opcji zakupu dopuszczają małe litery, cyfry i łączniki.
   Dokładna nazwa opcji wymaga potwierdzenia w Play Console.
   [Pola produktu i opcji zakupu](https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts).
3. Sprawdź nazwę **Przyjaciel Biblioteki** i opis podany przez właściciela.
   > Pamiątkowa odznaka wspierającego rozwój aplikacji Moja Biblioteka. Zakup jednorazowy, bez dodatkowych funkcji.
4. Dodaj jedną standardową opcję zakupu typu **Buy** z bezterminową własnością,
   oznaczoną jako zgodna wstecznie. Wtyczka odczytuje standardową opcję
   przez `getOneTimePurchaseOfferDetails()`. Kod używa `buyNonConsumable`.
   [Zgodność opcji zakupu](https://developer.android.com/google/play/billing/one-time-product-multi-purchase-options-offers).
5. Właściciel ustawił cenę **15.00 PLN** w Polsce. Przed aktywacją sprawdź
   ceny i dostępność w regionach. Aplikacja wyświetla sformatowaną cenę
   zwróconą przez Google Play.
6. Na potrzeby autoryzowanych testów aktywuj produkt i opcję zakupu w wybranych
   regionach i poczekaj na propagację. Sprawdź dokumentację konfiguracji opcji.
   [Produkty jednorazowe](https://developer.android.com/google/play/billing/one-time-products).
7. Używaj zamrożonego `pubspec.lock`. `in_app_purchase` 3.3.1 i
   `in_app_purchase_android` 0.5.5 korzystają z Play Billing Library 9.1.0.
   Przed wysyłką potwierdź wersję rozwiązaną przez Gradle i deklarację
   `com.google.android.play.billingclient.version` w scalonym manifeście oraz
   sprawdź aktualne terminy Play. Android V1 obsługuje API 24 i nowsze.
   [Wersje wtyczki](https://pub.dev/packages/in_app_purchase_android/changelog),
   [terminy Play Billing](https://developer.android.com/google/play/billing/deprecation-faq).
8. Użyj wewnętrznej ścieżki testów, aby sprawdzić podpis, instalację z Play i
   dostępność dystrybucji. Po zbudowaniu kodu Task 43 nowy AAB release zawiera
   checkout — **nie kieruj takiego AAB do produkcji** przed ukończeniem listy
   testów i oceną ryzyka integracji wyłącznie klienckiej.
9. Dodaj konta do testowania licencji i listy dostępu do ścieżki wewnętrznej,
   jeśli z niej korzystasz. Na fizycznym urządzeniu zaloguj właściwe konto w
   Google Play. Nie używaj zwykłych metod płatności w testach.
   [Testowanie Play Billing](https://developer.android.com/google/play/billing/test).

## Zrzuty ekranu z testowego sklepu

Zrzuty pochodzą z testu widżetów Flutter. Cena 2,49 € jest przykładową ceną
z atrapy Play, która symuluje potwierdzenie zakupu.

| Ekran | Przed zakupem | Po zakupie |
| --- | --- | --- |
| Wesprzyj Moją Bibliotekę | [Podgląd i zakup](screenshots/task36/support-before-purchase.png) | [Odznaka i podziękowanie](screenshots/task36/support-after-purchase.png) |
| Pomoc | [Tytuł](screenshots/task36/help-before-purchase.png) | [Tytuł z odznaką](screenshots/task36/help-after-purchase.png) |

## Symulacja udanego zakupu

Uruchom aplikację na Androidzie:

```sh
flutter run --debug --dart-define=PLAY_SUPPORTER_BILLING_TEST=true
```

1. Otwórz **Pomoc → Wesprzyj Moją Bibliotekę**.
2. W sekcji **Tryb deweloperski** włącz **Symuluj zakup odznaki**.
3. Sprawdź oficjalną grafikę, podziękowanie i tekst **Symulacja zakupu — tylko do testów**.
4. Wróć do **Pomoc** i sprawdź odznakę po lewej stronie tytułu.
5. Wyłącz symulację na ekranie wsparcia i sprawdź, czy odznaka zniknęła.
6. Włącz symulację, zamknij proces aplikacji i uruchom ją ponownie. Przełącznik będzie wyłączony.

Symulacja działa w pamięci procesu. Dane biblioteki i archiwa `.mlbak` są od niej
niezależne. Do tego scenariusza wystarczy urządzenie lub emulator z Androidem.
Konto testera i połączenie z Google Play są zbędne. Przełącznik jest dostępny
wyłącznie w natywnej kompilacji Android debug z powyższą flagą.

## Testy licencyjne na fizycznym urządzeniu

**BLOCKED** — wszystkie kroki poniżej wymagają fizycznego urządzenia
z kontem testera licencji. Testy z atrapą sklepu nie wykonują płatności.

Zbuduj i zainstaluj debug APK o zgodnym identyfikatorze pakietu. Konto testera
licencji może testować podpis debug bez przesyłania tej kompilacji do sklepu.
Właściciel musi osobno dodać konto w Play Console jako testera licencji.
Przełącznik w aplikacji nie konfiguruje konta. Zweryfikuj konto w oknie zakupu
i widoczny komunikat o zakupie testowym.

```sh
flutter build apk --debug --dart-define=PLAY_SUPPORTER_LICENSE_TEST=true
```

1. Otwórz **Pomoc**.
2. Wybierz **Wesprzyj Moją Bibliotekę**.
3. W sekcji **Tryb deweloperski** włącz **Testowanie zakupów Google Play**.
   Po ponownym uruchomieniu aplikacji przełącznik jest domyślnie wyłączony.
4. Sprawdź, czy wczytały się produkt `library_supporter_badge` oraz lokalna
   cena zwrócona przez Google Play.
5. Kup odznakę za pomocą skonfigurowanego konta testera licencji Google Play.
6. Sprawdź, czy odznaka pojawiła się po lewej stronie tytułu **Pomoc**.
7. Wybierz **Przywróć zakup** i sprawdź potwierdzenie przywrócenia. Po restarcie
   włącz testowanie ponownie, aby aplikacja odczytała własność z Google Play.
8. Wyłącz testowanie i sprawdź, czy nie można rozpocząć kolejnego zakupu.
   W trakcie zakupu, oczekiwania na płatność i potwierdzania transakcji
   przełącznik jest zablokowany.

Dodatkowe scenariusze:
- Sprawdź odrzucenie płatności, zamknięcie okna zakupu oraz opóźnioną płatność
  zatwierdzoną i odrzuconą. Odznaka powinna pojawić się po potwierdzeniu.
  Sprawdź wznowienie aplikacji i powrót po chwilowej utracie sieci.
- Użyj **Przywróć zakup** po wyczyszczeniu danych, po reinstalacji i na drugim
  urządzeniu z tym samym kontem. Użyj też konta bez zakupu. Play wybiera konto
  według zasad instalacji aplikacji, więc przy wielu kontach sprawdź osobno
  instalację i konto pokazane w oknie płatności.
- Na testowym zamówieniu wykonaj zwrot z cofnięciem dostępu. Po propagacji
  odśwież własność i sprawdź zniknięcie odznaki. Przy błędzie połączenia status
  potwierdzony wcześniej pozostaje widoczny w tej samej sesji.
- Wyeksportuj i przywróć `.mlbak` niezależnie od zakupu. Sprawdź katalog,
  historię, skanowanie i wypożyczenia dla konta z odznaką i bez niej. Na
  fizycznym iPhonie potwierdź dotychczasowe otwarcie BuyCoffee w Safari.
  Kupienie odznaki i dobrowolna wpłata przez BuyCoffee są niezależne.


## Task 43: ryzyko weryfikacji wyłącznie w aplikacji

**Uwaga przed publikacją płatności za prawdziwe pieniądze:** aktualna
integracja nie wywołuje Google Play Developer API przez zaufany serwer.
Sprawdza zakup odczytany przez Play Billing na urządzeniu, identyfikator
produktu, stan PURCHASED/RESTORED, niepusty token i zgodność tokenu z
powiadomieniem. To **nie jest kryptograficzna ani serwerowa weryfikacja tokenu**.
Na zmodyfikowanym urządzeniu odpowiedzi klienta mogą zostać sfałszowane.
Nie należy opisywać tego jako w pełni bezpiecznego rozwiązania antyfraudowego.

Przed wejściem na produkcję właściciel powinien świadomie zaakceptować to
ograniczenie lub wdrożyć weryfikację serwerową, idempotencję tokenów i
obsługę zwrotów przez Google Play Developer API i RTDN. Klucz usługi Google
nigdy nie może znaleźć się w aplikacji. Błąd komunikacji nie dowodzi zwrotu,
a brak potwierdzenia transakcji może zakończyć się automatycznym zwrotem.

**Weryfikacja wydania wewnętrznego:** sprawdź nowy AAB instalowany z Play
(numer wersji wyższy niż 17), pobraną cenę w PLN, pierwszą płatność testową,
stan pending, anulowanie, błąd, odzyskanie zakupu po restarcie i instalacji
na innym urządzeniu, blokadę ponownego zakupu, acknowledge, zwrot i
revocation oraz brak kontrolek deweloperskich. Sprawdź równolegle skanowanie,
Open Library, okładki, bazę SQLite, przypomnienia, wypożyczenia i .mlbak.
Wydanie podpisz kluczem upload i zweryfikuj podpis. Odrębnie rozwiąż
ostrzeżenie R8/DEX oraz wykonaj test urządzenia fizycznego.

[Rekomendacje bezpieczeństwa Google](https://developer.android.com/google/play/billing/security) ·
[Cykl życia zakupów](https://developer.android.com/google/play/billing/lifecycle/one-time)

## Weryfikacja i warunki produkcji

W Android release klient sprawdza aktualne zakupy Play przy uruchomieniu,
po wznowieniu aplikacji, przy ręcznym przywróceniu i przed zakupem.
W debug odczyt uruchamia się dopiero po włączeniu przełącznika testowego. Komunikat o zakupie wyzwala ponowne
zapytanie, które sprawdza produkt, stan i zgodność tokenu. Odznaka jest
przyznawana po potwierdzeniu przez Play i udanym zakończeniu transakcji, jeśli
wymaga ona potwierdzenia. Tokeny i stan wyświetlania żyją w pamięci procesu.
Po zimnym starcie bez połączenia odznaka pojawi się dopiero po potwierdzeniu
własności przez Play. Dane biblioteki i archiwum nie uczestniczą w tym procesie.

Odpowiedzi klienta można zmodyfikować na zmodyfikowanym urządzeniu. Sklep może
zwrócić dane z opóźnieniem. Zmiana konta lub cofnięcie dostępu pojawią się po
udanej synchronizacji własności przez Play. Integracja klienta nie obejmuje
powiadomień o cofnięciu dostępu. Błąd zapytania nie jest podstawą do usunięcia
odznaki. [Cykl życia zakupu](https://developer.android.com/google/play/billing/integrate).

Task 36 nie wprowadza backendu. Poniższy projekt integracji serwerowej
wymaga osobnego zatwierdzenia.

- Własny endpoint HTTPS przyjmuje token i ogranicza nadużycia. Backend używa
  tożsamości serwisowej z minimalnymi uprawnieniami, a pakiet pochodzi z jego
  konfiguracji. Wywołuje `purchases.productsv2.getproductpurchasev2` i sprawdza
  stan `PURCHASED`, identyfikator pozycji i stan użycia. Błędy przejściowe
  rozróżnia od potwierdzonego cofnięcia uprawnień.
- Przetwarzaj i potwierdzaj zakup idempotentnie według tokenu. Potwierdź go w
  ciągu trzech dni od zakończenia płatności, np. przez `purchases.products.acknowledge`.
  Zakup pozostaje niezużyty. Użyj powiadomień RTDN i okresowej rekonsyliacji
  zwrotów w celu aktualizacji własności. Przywracanie powinno sprawdzać dowód
  zakupu dla aktualnego kontekstu Play i ograniczać możliwość powtórnego użycia
  tokenu poza tym kontekstem.
  [API weryfikacji zakupu](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2),
  [bezpieczeństwo zakupów](https://developer.android.com/google/play/billing/security).

Przed włączeniem checkoutu w wydaniu produkcyjnym:

- [ ] Zatwierdź i przetestuj weryfikację serwerową lub jawnie zaakceptuj
      ograniczenia modelu wyłącznie klienckiego przed dopuszczeniem realnych płatności.
- [ ] Skonfiguruj profil płatności, produkt, opcję zakupu, ceny i regiony.
- [ ] Potwierdź wersję Billing Library, podpis, scalony manifest i dystrybucję
      w ścieżce wewnętrznej.
- [ ] Zapisz wyniki testów fizycznych, w tym przywrócenie, zwrot i zmianę konta.
- [ ] Zaktualizuj politykę prywatności i deklaracje Data safety pod kątem stanu
      zakupu, odbiorców danych, ich przechowywania i retencji. Sprawdź opis
      zakupu i informacje o cenie.
- [ ] Sprawdź brak BuyCoffee w Androidzie i brak Google Play Billing w Safari.
- [ ] Uzyskaj osobną zgodę właściciela na zmianę blokady produkcyjnej po
      spełnieniu warunków i przed udostępnieniem płatności.
