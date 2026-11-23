import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/browser_files.dart';
import '../services/library_backup.dart';
import '../services/local_reminder_notifications.dart';

class LibraryBackupScreen extends StatefulWidget {
  const LibraryBackupScreen({super.key, this.service});

  final LibraryBackup? service;

  @override
  State<LibraryBackupScreen> createState() => _LibraryBackupScreenState();
}

class _LibraryBackupScreenState extends State<LibraryBackupScreen> {
  late final _service =
      widget.service ?? LibraryBackup(reminders: libraryReturnReminders);
  String? _progress;
  String? _feedback;
  bool _confirming = false;

  final _browserBackup = BrowserLibraryBackup();
  Uint8List? _download;

  Future<bool?> _confirmRestore() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Przywrócić kopię zapasową?'),
        content: const Text(
          'Przywrócenie kopii zapasowej zastąpi wszystkie książki, wypożyczenia, historię i ustawienia zapisane obecnie w aplikacji. Tych danych nie będzie można odzyskać bez wcześniejszej kopii zapasowej. Czy chcesz kontynuować?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Przywróć dane'),
          ),
        ],
      ),
    );
  }

  void _saveDownload() {
    downloadBackup(_browserBackup.exportName, _download!);
    setState(() {
      _download = null;
      _feedback = 'Rozpoczęto pobieranie kopii zapasowej.';
    });
  }

  Future<void> _run({required bool restore}) async {
    if (_progress != null) return;
    setState(() {
      _feedback = null;
      _download = null;
      _progress = restore
          ? 'Wybieranie i sprawdzanie kopii zapasowej…'
          : 'Przygotowywanie i zapisywanie kopii zapasowej…';
    });
    Directory? work;
    var replacing = false;
    var feedback = 'Operacja została anulowana.';
    try {
      if (kIsWeb) {
        if (!restore) {
          final bytes = await _browserBackup.export();
          if (mounted) setState(() => _download = bytes);
          feedback = 'Kopia jest gotowa do pobrania.';
        } else {
          final staged = await _browserBackup.prepareRestore();
          if (staged != null) {
            try {
              if (mounted) {
                setState(() => _confirming = true);
                final confirmed = await _confirmRestore();
                if (confirmed == true && mounted) {
                  replacing = true;
                  setState(() {
                    _confirming = false;
                    _progress = 'Przywracanie danych…';
                  });
                  await _browserBackup.restore(
                      staged.verifiedPath, staged.covers);
                  feedback = 'Dane zostały przywrócone pomyślnie.';
                }
              }
            } finally {
              await _browserBackup.discard(staged.verifiedPath);
            }
          }
        }
        return;
      }
      work = await _service.workspace();
      if (!restore) {
        if (await _service.export(work)) {
          feedback = 'Kopia zapasowa została zapisana.';
        }
      } else if (await _service.prepareRestore(work) && mounted) {
        setState(() => _confirming = true);
        final confirmed = await _confirmRestore();
        if (confirmed == true && mounted) {
          replacing = true;
          setState(() {
            _confirming = false;
            _progress = 'Przywracanie danych…';
          });
          await _service.restore(work);
          feedback = 'Dane zostały przywrócone pomyślnie.';
        }
      }
    } catch (error) {
      if (!restore) {
        feedback = 'Nie udało się zapisać kopii zapasowej. Spróbuj ponownie.';
      } else if (replacing) {
        feedback = error is RestoreFailure && error.previousLibraryVerified
            ? 'Nie udało się przywrócić danych. Poprzednia biblioteka została zachowana.'
            : 'Nie udało się zakończyć przywracania danych. Uruchom ponownie aplikację i sprawdź bibliotekę.';
      } else if (error is PlatformException && error.code == 'future_version') {
        feedback =
            'Ta kopia zapasowa pochodzi z nowszej wersji aplikacji i nie może zostać przywrócona.';
      } else {
        feedback =
            'Nie można odczytać kopii zapasowej. Wybierz prawidłowy plik.';
      }
    } finally {
      try {
        await work?.delete(recursive: true);
      } on FileSystemException {
        // Stale private workspaces are removed on startup.
      }
      if (mounted) {
        setState(() {
          _progress = null;
          _confirming = false;
          _feedback = feedback;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kopia zapasowa'),
          automaticallyImplyLeading: !busy,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Kopie zapasowe tworzysz ręcznie. Plik nie jest szyfrowany i może zawierać dane osobowe. Przechowuj go w bezpiecznym miejscu.',
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                const Text(
                  'Wyczyszczenie danych witryny w Safari może usunąć bibliotekę. Zachowaj kopię w aplikacji Pliki. W przeglądarce limit kopii wynosi 64 MiB.',
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : () => _run(restore: false),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Eksportuj kopię zapasową'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _run(restore: true),
                icon: const Icon(Icons.restore),
                label: const Text('Przywróć kopię zapasową'),
              ),
              if (_download != null) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saveDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Pobierz plik .mlbak'),
                ),
              ],
              if (busy && !_confirming) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(semanticsLabel: _progress),
              ],
              if (_progress != null || _feedback != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_progress ?? _feedback!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
