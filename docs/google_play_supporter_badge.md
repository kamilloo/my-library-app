# Przyjaciel Biblioteki w Google Play

**Stan wydania:** integracja klienta jest dostępna w Androidzie do testów
licencyjnych. Kompilacje release i profile nie uruchamiają płatności, także przy
podaniu flagi testowej. Właściciel projektu wykonuje wszystkie operacje w Play
Console. Wydania bez aktywnej integracji pokazują podgląd odznaki bez przycisków
zakupu i przywracania.

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
   identyfikatora opcji zakupu. `badge_one_time` to zgłoszony identyfikator
   wymagający potwierdzenia w sekcji opcji zakupu w Play Console.
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
   dostępność dystrybucji. Bieżący AAB release nie zawiera aktywnego checkoutu.
   Test ścieżki zakupowej w AAB wymaga docelowej weryfikacji i kontrolowanego
   włączenia w wydaniu wewnętrznym.
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

## Testy na fizycznym urządzeniu

**BLOCKED** — wszystkie kroki poniżej wymagają fizycznego urządzenia
z kontem testera licencji. Testy z atrapą sklepu nie wykonują płatności.

Zbuduj i zainstaluj debug APK o zgodnym identyfikatorze pakietu. Konto testera
licencji może testować podpis debug bez przesyłania tej kompilacji do sklepu.
Zweryfikuj konto użyte w oknie zakupu i widoczny komunikat o zakupie testowym.

```sh
flutter build apk --debug --dart-define=PLAY_SUPPORTER_BILLING_TEST=true
```

- W **Pomoc → Wesprzyj Moją Bibliotekę** sprawdź dostępność produktu
  `library_supporter_badge`, cenę lokalną z Play i otwarcie okna zakupu.
  Zakończ zakup testowy. Sprawdź podziękowanie na ekranie wsparcia, odznakę
  po lewej stronie tytułu **Pomoc** i brak możliwości ponownego zakupu.
  Uruchom aplikację ponownie i sprawdź, czy Play przywraca odznakę.
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

Klient testowy używa zapytania o aktualne zakupy Play przy starcie, wznowieniu,
ręcznym przywróceniu i przed zakupem. Komunikat o zakupie wyzwala ponowne
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

- [ ] Zatwierdź, zaimplementuj i przetestuj weryfikację serwerową.
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
