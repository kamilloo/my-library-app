import 'dart:async';

import 'package:flutter/material.dart';

import '../models/open_library_search.dart';
import '../services/open_library_service.dart';

class SearchBooksScreen extends StatefulWidget {
  const SearchBooksScreen(
      {required this.service,
      this.initialTitle = '',
      this.initialAuthor = '',
      super.key});
  final OpenLibraryService service;
  final String initialTitle;
  final String initialAuthor;
  @override
  State<SearchBooksScreen> createState() => _SearchBooksScreenState();
}

class _SearchBooksScreenState extends State<SearchBooksScreen> {
  late final title = TextEditingController(text: widget.initialTitle);
  late final author = TextEditingController(text: widget.initialAuthor);
  List<OpenLibrarySearchResult> results = [];
  bool loading = false;
  bool searched = false;
  bool hasMore = false;
  bool failedMore = false;
  int page = 0;
  int revision = 0;
  final pending = <(String, String, int), Future<OpenLibrarySearchPage>>{};
  String? error;

  void edited(String _) {
    setState(() {
      revision++;
      loading = false;
      results = [];
      page = 0;
      hasMore = false;
      searched = false;
      error = null;
    });
  }

  Future<void> search({bool more = false}) async {
    if (loading) return;
    final queryTitle = title.text.trim();
    final queryAuthor = author.text.trim();
    if (queryTitle.isEmpty && queryAuthor.isEmpty) {
      setState(() => error = 'Wpisz tytuł lub autora.');
      return;
    }
    final nextPage = more ? page + 1 : 1;
    if (nextPage > OpenLibraryService.maxSearchPages) return;
    final request = ++revision;
    setState(() {
      loading = true;
      searched = true;
      error = null;
      failedMore = more;
      if (!more) {
        results = [];
        page = 0;
        hasMore = false;
      }
    });
    final key = (queryTitle, queryAuthor, nextPage);
    Future<OpenLibrarySearchPage>? task;
    try {
      task = pending[key] ??= widget.service
          .searchBooks(title: queryTitle, author: queryAuthor, page: nextPage);
      final response = await task;
      if (!mounted || request != revision) return;
      setState(() {
        results = more ? [...results, ...response.results] : response.results;
        page = nextPage;
        hasMore = response.hasMore && page < OpenLibraryService.maxSearchPages;
      });
    } on TimeoutException {
      if (mounted && request == revision) {
        setState(() => error = 'Przekroczono czas wyszukiwania.');
      }
    } on OpenLibrarySearchException catch (exception) {
      if (mounted && request == revision) {
        setState(() => error = exception.message);
      }
    } catch (_) {
      if (mounted && request == revision) {
        setState(() => error =
            'Nie udało się wyszukać książek. Sprawdź połączenie z internetem.');
      }
    } finally {
      if (identical(pending[key], task)) pending.remove(key);
      if (mounted && request == revision) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    revision++;
    title.dispose();
    author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Szukaj w Open Library')),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                TextField(
                    controller: title,
                    onChanged: edited,
                    decoration: const InputDecoration(labelText: 'Tytuł')),
                const SizedBox(height: 12),
                TextField(
                    controller: author,
                    onChanged: edited,
                    decoration: const InputDecoration(labelText: 'Autor')),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: loading ? null : () => search(),
                    icon: const Icon(Icons.search),
                    label: const Text('Szukaj')),
                if (loading) ...[
                  const LinearProgressIndicator(),
                  const Text('Wyszukiwanie…'),
                ],
                if (error != null) ...[
                  Text(error!),
                  TextButton(
                      onPressed:
                          loading ? null : () => search(more: failedMore),
                      child: const Text('Spróbuj ponownie')),
                ],
              ])),
          Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(searched && !loading && error == null
                          ? 'Nie znaleziono książek. Spróbuj zmienić tytuł lub autora.'
                          : 'Wpisz tytuł lub autora i wybierz „Szukaj”.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: results.length + 1,
                      itemBuilder: (context, index) {
                        if (index == results.length) {
                          return hasMore
                              ? TextButton(
                                  onPressed:
                                      loading ? null : () => search(more: true),
                                  child: const Text('Pokaż więcej'),
                                )
                              : const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                      'Koniec wyników (maksymalnie 5 stron).'));
                        }
                        final book = results[index];
                        return Card(
                            child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: 50,
                                    height: 72,
                                    child: book.coverUrl == null
                                        ? const Icon(Icons.menu_book)
                                        : Image.network(book.coverUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.menu_book))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(book.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text(book.author.isEmpty
                                        ? 'Nieznany autor'
                                        : book.author),
                                    if (book.year != null)
                                      Text('Rok wydania: ${book.year}'),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, book),
                                        child: const Text('Wybierz książkę')),
                                  ],
                                )),
                              ]),
                        ));
                      },
                    )),
        ])),
      );
}
