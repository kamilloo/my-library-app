import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/screens/library_backup_screen.dart';
import 'package:my_library/screens/tutorial_screen.dart';
import 'package:my_library/services/library_backup.dart';

class TestWorkspace implements Directory {
  @override
  Future<Directory> delete({bool recursive = false}) async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestBackup extends LibraryBackup {
  bool selected = true;
  bool fail = false;
  int restores = 0;

  @override
  Future<Directory> workspace() async => TestWorkspace();

  @override
  Future<bool> export(Directory work) async {
    if (fail) throw PlatformException(code: 'document_failure');
    return selected;
  }

  @override
  Future<bool> prepareRestore(Directory work) async => selected;

  @override
  Future<void> restore(Directory work) async {
    restores++;
  }
}

Finder button<T extends Widget>(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is T),
    );

void main() {
  testWidgets('Help button placement, navigation and enlarged text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: const LoanHelpScreen(),
    ));

    final tutorial = button<OutlinedButton>('Samouczek — 7 slajdów');
    final backup = button<OutlinedButton>('Kopia zapasowa');
    expect(tutorial, findsOneWidget);
    expect(backup, findsOneWidget);
    expect(
        tester.getRect(tutorial).bottom, lessThan(tester.getRect(backup).top));

    await tester.tap(backup);
    await tester.pumpAndSettle();
    final export = button<FilledButton>('Eksportuj kopię zapasową');
    final restore = button<OutlinedButton>('Przywróć kopię zapasową');
    expect(find.byType(LibraryBackupScreen), findsOneWidget);
    await tester.scrollUntilVisible(export, 150);
    expect(tester.getSize(export).width, 280);
    await tester.scrollUntilVisible(restore, 150);
    expect(tester.getSize(restore).width, 280);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Pomoc'), findsOneWidget);

    final headings = [
      'SMS i komunikacja o wypożyczeniu',
      'Wypożyczenia i synchronizacja danych',
      'Kopia zapasowa i przywracanie danych',
    ];
    final list = tester.widget<ListView>(find.byType(ListView));
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    final headers = children
        .whereType<Semantics>()
        .map((heading) => (heading.child as Text).data)
        .toList();
    expect(headers.skip(1).take(3), headings);
    final last = children.whereType<Text>().map((text) => text.data).last;
    expect(
        last,
        endsWith(
            'Dane można odzyskać tylko wtedy, gdy wcześniej zapisano kopię zapasową.'));
    expect(
      children.whereType<Text>().map((text) => text.data),
      containsAllInOrder(backupHelp.map((paragraph) => paragraph.text)),
    );
    await tester.scrollUntilVisible(find.text(headings.last), 240,
        maxScrolls: 100);
    expect(find.text(headings.last), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection and explicit confirmation control restore',
      (tester) async {
    final service = TestBackup();
    await tester
        .pumpWidget(MaterialApp(home: LibraryBackupScreen(service: service)));
    final restore = find.text('Przywróć kopię zapasową');
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(find.text('Przywrócić kopię zapasową?'), findsOneWidget);
    expect(service.restores, 0);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(find.text('Operacja została anulowana.'), findsOneWidget);
    expect(service.restores, 0);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przywróć dane'));
    await tester.pumpAndSettle();
    expect(service.restores, 1);
    expect(find.text('Dane zostały przywrócone pomyślnie.'), findsOneWidget);
  });

  testWidgets('cancelled and failed saves do not report success',
      (tester) async {
    final service = TestBackup()..selected = false;
    await tester
        .pumpWidget(MaterialApp(home: LibraryBackupScreen(service: service)));
    final export = find.text('Eksportuj kopię zapasową');
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(find.text('Operacja została anulowana.'), findsOneWidget);
    service.fail = true;
    await tester.tap(export);
    await tester.pumpAndSettle();
    expect(find.text('Kopia zapasowa została zapisana.'), findsNothing);
    expect(
        find.text('Nie udało się zapisać kopii zapasowej. Spróbuj ponownie.'),
        findsOneWidget);
  });
}
