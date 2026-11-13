import 'package:flutter/material.dart';
import '../data/library_repository.dart';
import '../models/genre.dart';

Future<Genre?> editGenre(BuildContext context, LibraryRepository repository,
    {Genre? genre}) async {
  var input = genre?.name ?? '';
  final key = GlobalKey<FormState>();
  String? error;
  bool saving = false;
  final result = await showDialog<Genre>(
    context: context,
    builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
              scrollable: true,
              title: Text(genre == null ? 'Dodaj gatunek' : 'Edytuj gatunek'),
              content: Form(
                  key: key,
                  child: TextFormField(
                    initialValue: input,
                    onChanged: (value) => input = value,
                    autofocus: true,
                    decoration: InputDecoration(
                        labelText: 'Nazwa gatunku', errorText: error),
                    validator: (value) {
                      try {
                        validateGenreName(value ?? '');
                        return null;
                      } on GenreException catch (e) {
                        return e.message;
                      }
                    },
                  )),
              actions: [
                TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('Anuluj')),
                FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!key.currentState!.validate()) return;
                            setState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              final saved = await repository.saveGenre(input,
                                  id: genre?.id);
                              if (context.mounted) {
                                Navigator.pop(context, saved);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setState(() {
                                  saving = false;
                                  error = e is GenreException
                                      ? e.message
                                      : 'Nie udało się zapisać gatunku.';
                                });
                              }
                            }
                          },
                    child: const Text('Zapisz')),
              ],
            )),
  );
  return result;
}

enum _GenreAction { all, create, manage }

class GenreSelector extends StatefulWidget {
  const GenreSelector(
      {required this.repository,
      required this.value,
      required this.onChanged,
      this.enabled = true,
      this.filter = false,
      super.key});
  final LibraryRepository repository;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final bool filter;
  @override
  State<GenreSelector> createState() => _GenreSelectorState();
}

class _GenreSelectorState extends State<GenreSelector> {
  Future<void> choose() async {
    try {
      final genres = await widget.repository.genres();
      if (!mounted) return;
      final selected = await showDialog<Object>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('Gatunek'), children: [
          if (widget.filter)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(context, _GenreAction.all),
                child: const Text('Wszystkie gatunki')),
          ...genres.map((g) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, g), child: Text(g.name))),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(context, _GenreAction.create),
              child: const Text('Dodaj gatunek')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(context, _GenreAction.manage),
              child: const Text('Zarządzaj gatunkami')),
        ]),
      );
      if (!mounted || selected == null) return;
      if (selected == _GenreAction.create) {
        final created = await editGenre(context, widget.repository);
        if (created != null && mounted) widget.onChanged(created.name);
      } else if (selected == _GenreAction.manage) {
        final old = genres.where((g) => g.name == widget.value).firstOrNull;
        await Navigator.push<void>(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ManageGenresScreen(repository: widget.repository)));
        final current = await widget.repository.genres();
        if (!mounted) return;
        final updated = current.where((g) => g.id == old?.id).firstOrNull;
        widget
            .onChanged(updated?.name ?? (widget.filter ? null : defaultGenre));
      } else {
        widget.onChanged(selected is Genre ? selected.name : null);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nie udało się wczytać gatunków.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Gatunek'),
        subtitle: Text(widget.value ??
            (widget.filter ? 'Wszystkie gatunki' : defaultGenre)),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: widget.enabled ? choose : null,
      );
}

class ManageGenresScreen extends StatefulWidget {
  const ManageGenresScreen({required this.repository, super.key});
  final LibraryRepository repository;
  @override
  State<ManageGenresScreen> createState() => _ManageGenresScreenState();
}

class _ManageGenresScreenState extends State<ManageGenresScreen> {
  late Future<List<Genre>> data = widget.repository.genres();
  void refresh() => setState(() {
        data = widget.repository.genres();
      });

  Future<void> remove(Genre genre) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Usuń gatunek'),
              content: Text(genre.bookCount == 0
                  ? 'Usunąć gatunek „${genre.name}”?'
                  : 'Ten gatunek jest przypisany do ${genre.bookCount} książek. Po jego usunięciu książki zostaną oznaczone jako „Bez gatunku”.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Anuluj')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(genre.bookCount == 0
                        ? 'Usuń'
                        : 'Usuń i zmień na „Bez gatunku”')),
              ],
            ));
    if (confirmed != true) return;
    try {
      await widget.repository.deleteGenre(genre.id);
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nie udało się usunąć gatunku.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Zarządzaj gatunkami')),
        body: FutureBuilder<List<Genre>>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: TextButton(
                        onPressed: refresh,
                        child: const Text('Spróbuj ponownie')));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(padding: const EdgeInsets.all(20), children: [
                FilledButton(
                    onPressed: () async {
                      await editGenre(context, widget.repository);
                      if (mounted) refresh();
                    },
                    child: const Text('Dodaj gatunek')),
                ...snapshot.data!.map((genre) => Column(children: [
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(genre.name),
                          subtitle: Text('${genre.bookCount} książek')),
                      if (genre.id.isNotEmpty)
                        Wrap(children: [
                          TextButton(
                              onPressed: () async {
                                await editGenre(context, widget.repository,
                                    genre: genre);
                                if (mounted) refresh();
                              },
                              child: const Text('Edytuj gatunek')),
                          TextButton(
                              onPressed: () => remove(genre),
                              child: const Text('Usuń gatunek')),
                        ]),
                      const Divider(),
                    ])),
              ]);
            }),
      );
}
