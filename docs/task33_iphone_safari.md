# Zadanie 33 — Moja Biblioteka w Safari na iPhonie

| Platforma | Ścieżka użytkownika |
| --- | --- |
| Safari na iPhonie | Otwórz stronę HTTPS i wybierz **Użyj w przeglądarce**. |
| Przeglądarka na Androidzie | Wybierz **Zainstaluj na Androidzie**. Gdy brakuje zweryfikowanego adresu Google Play, strona wyświetla informację o dostępności. |
| Aplikacja Android | Dotychczasowe środowisko aplikacji i oficjalna ścieżka na Androidzie. |
| Przeglądarka na komputerze | Środowisko developerskie. Adres z parametrem `?app=1` otwiera Flutter Web bez sprawdzania urządzenia. |

## Publikacja statyczna

Zadanie `web-build` w Flutter CI tworzy artefakt `my-library-iphone-web`. Lokalnie użyj wersji Flutter z CI oraz Node.js 20 lub nowszego. Uruchom polecenia z katalogu projektu.

```sh
flutter pub get
dart run sqflite_common_ffi_web:setup
flutter build web --release --no-web-resources-cdn --base-href /app/
node tool/prepare_web.mjs
```

Artefakt CI jest budowany dla `/app/`. Na iPhonie Safari ten adres uruchamia bibliotekę bez dodatkowego wyboru platformy. Do testów na komputerze użyj `/app/?app=1`. Ikony manifestu pochodzą z `assets/icon/my_library_icon_1024.png`.

Opublikuj zawartość `build/web` pod stałym adresem HTTPS. Przy publikacji pod ścieżką, np. `/biblioteka/`, dodaj `--base-href /biblioteka/` do polecenia Flutter. Serwer powinien zwracać JavaScript jako `text/javascript` i pliki WASM jako `application/wasm`. Udostępniaj pliki z jednej wersji jako całość. Ustaw ponowną walidację HTTP dla plików o stałych nazwach, w szczególności dla `offline-worker.js`. Cache service workera przechowuje zestaw plików tej samej wersji i przełącza wersję po zamknięciu klientów korzystających z poprzedniej.

Przed budową wpisz oficjalny adres Google Play w `web/play-config.json`, gdy zostanie zweryfikowany. Przeglądarka akceptuje stronę szczegółów pakietu `com.kamilloo.mylibrary` w domenie Google Play.

Przed publiczną publikacją sprawdź [profil i warunki publikacji wsparcia](voluntary_support.md).
Na stronie wejściowej sprawdź stopkę, a w aplikacji ekran **Pomoc → O aplikacji**.
Po przygotowaniu trybu offline zweryfikuj ekran bez połączenia. Po ponownym
połączeniu potwierdź, że dopiero dotknięcie przycisku otwiera adres BuyCoffee.to
w osobnej karcie i pozostawia bibliotekę w bieżącej karcie.

## Przechowywanie i prywatność

Safari otwiera tę samą bibliotekę Flutter i używa tego samego schematu oraz zapytań SQLite co Android. SQLite skompilowany do WebAssembly zapisuje bazę w IndexedDB, co pozwala zachować transakcje, migracje i format kopii. Bezpośrednie użycie IndexedDB wymagałoby osobnej implementacji zapytań, transakcji, migracji i eksportu SQLite. Wybrany wariant zwiększa rozmiar zasobów potrzebnych przy pierwszym uruchomieniu i korzysta z eksperymentalnego backendu webowego. Zdjęcia wybrane lub zrobione w Safari są konwertowane lokalnie do JPEG i zapisywane w bazie przeglądarki. Kopia zawiera standardowy plik SQLite i osobne JPEG, tak jak na Androidzie. Import sprawdza spis plików, sumy kontrolne, schemat i integralność przed ekranem potwierdzenia. Zastąpienie rekordów i zdjęć w Safari odbywa się w jednej transakcji. Wersja przeglądarkowa przyjmuje pliki .mlbak do 64 MiB i ogranicza sumę rozpakowanych danych do 64 MiB ze względu na pamięć urządzenia.

Dobrowolne wsparcie nie zapisuje danych o wpłatach. Płatność odbywa się na stronie BuyCoffee.to otwieranej bez danych biblioteki i bez nagłówka odsyłającego.

Dane są przypisane do adresu witryny i profilu Safari. Wyczyszczenie danych witryny lub usunięcie ich przez system może skasować bibliotekę. Eksportuj kopie regularnie i zachowuj je w aplikacji Pliki. Pliki `.mlbak` są niezaszyfrowane. Skaner i wybrane zdjęcia są przetwarzane na urządzeniu. Wyszukiwanie metadanych w Open Library i okładki z adresów URL wymagają połączenia. Skanowanie ISBN zwraca kod do formularza także bez połączenia.

## Weryfikacja na rzeczywistym iPhonie

Zapisz model iPhone’a, wersję iOS, adres HTTPS, wersję kompilacji i wynik każdego kroku.

1. W zwykłej karcie Safari otwórz stronę online i wybierz **Użyj w przeglądarce**.
2. Przejdź przez konfigurację początkową.
3. Dodaj książkę ze zdjęciem i ponownie wyświetl jej okładkę.
4. Zeskanuj kod kreskowy ISBN.
5. Zeskanuj kod QR wypożyczenia.
6. Otwórz **Pomoc** i sprawdź komunikat **Zasoby do pracy offline są gotowe**.
7. Włącz tryb samolotowy i upewnij się, że Wi-Fi jest wyłączone.
8. Zamknij Safari i uruchom je ponownie.
9. Ponownie otwórz adres aplikacji offline.
10. Zrób lub wybierz zdjęcie i zapisz książkę.
11. Zeskanuj kod QR i obsługiwany kod kreskowy offline.
12. Zapisz rekordy, zamknij Safari i ponownie otwórz aplikację.
13. Sprawdź zapisane rekordy, historię i lokalne okładki.
14. Zaimportuj plik `.mlbak` z Androida i sprawdź rekordy oraz zdjęcia.
15. Wyeksportuj plik `.mlbak` w Safari, zmień testowy rekord i przywróć plik. Zweryfikuj wynik. Sprawdź również import tego pliku na Androidzie.

Na Androidzie otwórz stronę w przeglądarce i sprawdź priorytet przycisku Google Play oraz komunikat dla pustej konfiguracji. Zweryfikuj aplikację natywną przy użyciu [listy regresji Androida](android_qa_checklist.md). Testy w przeglądarkach komputerowych służą do weryfikacji technicznej.
