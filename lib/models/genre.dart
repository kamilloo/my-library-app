import 'package:unorm_dart/unorm_dart.dart' as unicode;

const defaultGenre = 'Bez gatunku';
const starterGenres = [
  'Fantastyka',
  'Science fiction',
  'Kryminał',
  'Thriller',
  'Romans',
  'Horror',
  'Literatura obyczajowa',
  'Literatura historyczna',
  'Biografia i autobiografia',
  'Literatura faktu',
  'Przygodowa',
];

String normalizedGenre(String name) => unicode.nfc(name.trim().toLowerCase());

class GenreException implements Exception {
  const GenreException(this.message);
  final String message;
  @override
  String toString() => message;
}

String validateGenreName(String input) {
  if (RegExp(r'[\x00-\x1F\x7F-\x9F\u2028\u2029]').hasMatch(input)) {
    throw const GenreException(
        'Nazwa gatunku nie może zawierać znaków sterujących ani nowych linii.');
  }
  final name = unicode.nfc(input.trim());
  if (name.isEmpty) throw const GenreException('Wpisz nazwę gatunku.');
  if (name.runes.length > 60) {
    throw const GenreException('Nazwa gatunku jest za długa.');
  }
  if ([normalizedGenre(defaultGenre), normalizedGenre('Bez kategorii')]
      .contains(normalizedGenre(name))) {
    throw const GenreException('Ta nazwa gatunku jest zarezerwowana.');
  }
  return name;
}

class Genre {
  const Genre(this.id, this.name, this.bookCount);
  final String id;
  final String name;
  final int bookCount;
}
