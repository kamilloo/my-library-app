# Przyjaciel Biblioteki w Google Play

**Kandydat do wydania:** natywna kompilacja Android release inicjuje Google Play
Billing automatycznie, bez flag i przełączników. Obie flagi testowe działają
wyłącznie w natywnym Android debug. Android profile pokazuje podgląd odznaki.
Flutter Web i natywny iOS nie inicjują Google Play Billing. Właściciel projektu
wykonuje operacje w Play Console.

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
   dostępność produktu w podpisanym wydaniu release bez flag testowych.
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

Poniższe kroki dotyczą podpisu debug. Task 43 wymaga dodatkowo osobnego
sprawdzenia podpisanego AAB z wewnętrznej ścieżki Play.

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

## Weryfikacja i warunki produkcji

Klient sprawdza aktualne zakupy Play przy starcie Android release (w debug
po włączeniu testowania), przy wznowieniu, przy ręcznym przywróceniu i przed
zakupem. Przy wznowieniu ponownie odpytuje Play również wtedy, gdy okno zakupu
zamknięto bez dostarczenia zdarzenia. Komunikat o zakupie wyzwala ponowne
zapytanie, które sprawdza produkt, stan i zgodność tokenu. Odznaka jest
przyznawana po potwierdzeniu przez Play i udanym zakończeniu transakcji, jeśli
wymaga ona potwierdzenia. Tokeny i stan wyświetlania żyją w pamięci procesu.
Po zimnym starcie bez połączenia odznaka pojawi się dopiero po potwierdzeniu
własności przez Play. Dane biblioteki i archiwum nie uczestniczą w tym procesie.

Kandydat zachowuje weryfikację po stronie klienta dla odznaki bez uprawnień
do funkcji. Zakup oczekujący, anulowany, błędny lub niepotwierdzony nie przyznaje
odznaki. Gdy potwierdzenie transakcji się nie powiedzie, klient ponawia próbę
przy następnym odczycie zakupów, np. po wznowieniu lub przywróceniu. Play
automatycznie zwraca niepotwierdzone zakupy po trzech dniach od zakończenia
płatności. [Cykl życia zakupu](https://developer.android.com/google/play/billing/integrate).

Weryfikację klienta można obejść przez modyfikację aplikacji lub jej środowiska.
Brakuje serwerowego rejestru tokenów, ochrony przed ich ponownym użyciem oraz
RTDN i Voided Purchases API. Odznaka znika po udanym odczycie, w którym Play
przestanie zwracać zakup po zwrocie z cofnięciem uprawnień. Sam zwrot bez
cofnięcia uprawnień zależy od tego, czy Play nadal zwraca zakup. Propagacja
może być opóźniona, a błąd odczytu zachowuje wcześniej potwierdzony stan w tej
samej sesji. Google zaleca weryfikację i potwierdzanie na zaufanym backendzie
oraz obsługę unieważnionych zamówień przed publicznym wdrożeniem.
[Bezpieczeństwo zakupów](https://developer.android.com/google/play/billing/security).

Docelowa integracja serwerowa:

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

## Weryfikacja kandydata przed publikacją

Zbuduj podpisany AAB: `flutter build appbundle --release --no-pub --build-number=18`.
Użyj numeru wyższego niż wszystkie użyte w Play Console. Właściciel sam przesyła
AAB do testów wewnętrznych i udostępnia go wyłącznie testerom licencyjnym.
Na fizycznym urządzeniu zainstaluj kompilację przez Play. Potwierdź komunikat
o płatności testowej przed zatwierdzeniem zakupu.

Lokalny kandydat Task 43, `1.0.0+18`, został zbudowany bez flag
testowych i zweryfikowany przez `jarsigner`. JBR 25 zgłosił certyfikat
samopodpisany, brak znacznika czasu i różnice w odczycie wpisów przez
`JarFile` i `JarInputStream`. Porównanie certyfikatu z kluczem upload
w Play Console i instalacja z wewnętrznej ścieżki pozostają do wykonania.
Flutter: 457 testów przeszło, analiza bez uwag.

Lista kontrolna Play Console i urządzenia:

- [ ] Przed publicznym wdrożeniem zweryfikuj integrację serwerową lub uzyskaj
      decyzję właściciela o akceptacji opisanych ograniczeń dla odznaki.
- [ ] Skonfiguruj profil płatności, produkt, opcję zakupu, ceny i regiony.
- [ ] Potwierdź wersję Billing Library, podpis, scalony manifest i dystrybucję
      w ścieżce wewnętrznej.
- [ ] Sprawdź lokalną cenę, brak trybu deweloperskiego, podziękowanie oraz
      odznakę przy **Pomoc** na ekranach **Moje książki**, **Historia** i **Pożyczone**.
- [ ] Sprawdź przerwany checkout, anulowanie, odrzucenie, płatność oczekującą,
      potwierdzenie transakcji, przywrócenie po reinstalacji i na drugim urządzeniu,
      zmianę konta oraz zwrot z cofnięciem uprawnień. Zapisz wyniki.
- [ ] Zaktualizuj politykę prywatności i deklaracje Data safety pod kątem stanu
      zakupu, odbiorców danych, ich przechowywania i retencji. Sprawdź opis
      zakupu i informacje o cenie.
- [ ] Sprawdź brak BuyCoffee w Androidzie i brak Google Play Billing w Safari.
- [ ] Uzyskaj osobną zgodę właściciela na udostępnienie płatności po
      zakończeniu testów. Jeśli dojdzie optymalizacja R8, powtórz test na
      podpisanej kompilacji z docelową konfiguracją R8.
