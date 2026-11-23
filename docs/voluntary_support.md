# Dobrowolne wsparcie Mojej Biblioteki

Moja Biblioteka pozostaje bezpłatna. Katalogowanie i wypożyczenia, biblioteki
dowolnej wielkości oraz kopie zapasowe i przywracanie są dostępne bez wpłat.
Aplikacja nie oferuje abonamentów, reklam, płatnych funkcji, wyróżnień ani nagród.
Wpłata nie zmienia danych, zachowania aplikacji ani sposobu obsługi użytkownika.

## Gdzie znajduje się wsparcie

- **Safari na iPhonie:** w aplikacji otwórz **Pomoc → O aplikacji**. Ekran jest
  dostępny offline po przygotowaniu zasobów aplikacji. Przycisk **☕ Wesprzyj
  projekt** otwiera zewnętrzną kartę po dotknięciu. Witryna płatności wymaga sieci.
- **Strona wejściowa w tym repozytorium:** sekcja wsparcia jest pod przyciskami
  otwarcia aplikacji i instalacji. Link ma atrybuty `target="_blank"` i
  `rel="noopener noreferrer"`.
- **Oficjalna strona [mojabiblioteka.app](https://mojabiblioteka.app):** serwuje
  osobną stronę marketingową. Jej źródło nie jest częścią tego repozytorium.
  Fragment do wstawienia przed końcem istniejącej stopki znajduje się poniżej.
  Przed publikacją należy potwierdzić źródło i hosting oraz ścieżkę Safari do
  aplikacji HTTPS. Zachowaj główne odnośniki Google Play dla Androida i kieruj
  Safari na iPhonie do wersji przeglądarkowej. Komputery pozostają środowiskiem testowym.
- **Android:** ten sam ekran w **Pomoc → O aplikacji** wyświetla wyłącznie
  informacje. Implementacja natywna nie udostępnia żadnej akcji płatności.
  Funkcja nie pojawia się w samouczku ani w operacjach biblioteki.

## Konfiguracja i prywatność

Platformą wsparcia jest BuyCoffee.to. [Konfiguracja](../assets/support.json)
zawiera adres [buycoffee.to/moja-biblioteka](https://buycoffee.to/moja-biblioteka).
Flutter Web i strona wejściowa używają tego samego pliku. Dozwolony jest wyłącznie
adres HTTPS w domenie buycoffee.to z prostą nazwą profilu, bez parametrów, fragmentu,
portu czy danych logowania. Błędna konfiguracja ukrywa akcję. Po zmianie konfiguracji
zbuduj ponownie cały artefakt webowy i odśwież spis zasobów offline.

Otwarcie linku nie przekazuje danych biblioteki ani adresu strony odsyłającej.
BuyCoffee.to obsługuje płatność w swojej witrynie. Aplikacja nie otrzymuje danych
płatności, nie zapisuje historii wpłat, nie identyfikuje wspierających i nie śledzi
otwarć linku. Aplikacja działa bez konta i bez połączenia z BuyCoffee.to.

## Warunki publikacji

Adres profilu zwrócił HTTP 200 i tytuł „Postaw kawę dla moja Biblioteka”.
Właściciel projektu musi przed publiczną publikacją potwierdzić kontrolę nad
profilem, gotowość do przyjmowania wpłat i brak opcji cyklicznych lub nagród
skonfigurowanych dla projektu. Nie wykonano płatności.

[Google Play](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
uzależnia wyjątek dla płatności między osobami od przekazania 100% wpłaty twórcy
oraz braku treści, usług lub nagród cyfrowych w zamian.
[BuyCoffee.to](https://buycoffee.to/rules/pl/serwis.pdf) podaje 10% prowizji od
jednorazowych wpłat (7,5% opłaty serwisowej i 2,5% kosztu transakcji). Sama
rezygnacja z korzyści nie spełnia warunku 100%. Nawigacja do płatności w Androidzie
pozostaje wyłączona do czasu udokumentowania odpowiedniej podstawy w aktualnej
polityce i uzyskania zgody właściciela projektu. Publikacja strony i aplikacji
webowej ma osobne warunki weryfikacji.

## Testowanie

Uruchom `flutter test test/support_test.dart` i pełne kontrole CI. Po zbudowaniu
webu wykonaj [weryfikację Safari i trybu offline](task33_iphone_safari.md).
Zapisz testową książkę, otwórz ekran informacji i wróć. Sprawdź, czy rekord
przetrwał przeładowanie także przy braku sieci. Po przywróceniu połączenia
dotknij przycisku, sprawdź adres nowej karty i wróć do biblioteki. Na Androidzie
przejdź tą samą ścieżką i potwierdź brak przycisku oraz działanie samouczka,
kopii zapasowych, skanera i wypożyczeń.

## Fragment stopki dla oficjalnej strony

Wstaw w miejscu przeznaczonym na informacje dodatkowe. W miejsce `SUPPORT_URL`
wstaw aktualną wartość z pliku konfiguracyjnego po weryfikacji profilu.

```html
<section aria-labelledby="support-title">
  <h2 id="support-title">☕ Wesprzyj rozwój Mojej Biblioteki</h2>
  <p>Moja Biblioteka jest darmową aplikacją do katalogowania książek i zarządzania wypożyczeniami.</p>
  <p>Jeśli aplikacja jest dla Ciebie przydatna, możesz dobrowolnie wesprzeć jej dalszy rozwój.</p>
  <p>Wsparcie jest całkowicie opcjonalne i nie wiąże się z żadnymi dodatkowymi korzyściami. Wszystkie funkcje aplikacji pozostają bezpłatne.</p>
  <p>❤️ Dziękuję za każde wsparcie!</p>
  <a href="SUPPORT_URL" target="_blank" rel="noopener noreferrer">☕ Wesprzyj projekt</a>
</section>
```
