import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library/screens/book_cover.dart';
import 'package:my_library/services/cover_storage.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';

void main() {
  testWidgets('absent and missing local images display placeholder',
      (tester) async {
    for (final reference in [null, '', '/missing/book-cover.jpg']) {
      await tester.pumpWidget(MaterialApp(
          home: BookCover(
              reference: reference,
              title: 'Placeholder',
              width: 100,
              height: 144)));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.text('Placeholder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('URL selects network image and offline failure shows placeholder',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: BookCover(
            reference: 'https://covers.openlibrary.org/b/id/123-L.jpg',
            title: 'Offline',
            width: 100,
            height: 144)));
    expect(tester.widget<Image>(find.byType(Image)).image, isA<NetworkImage>());
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('managed and absolute local files render without network',
      (tester) async {
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('cover-widget')))!;
    try {
      final file = File('${root.path}/covers/test.jpg');
      await tester.runAsync(() async {
        await Directory('${root.path}/covers').create();
        await file.writeAsBytes(base64Decode(pixel));
      });
      for (final reference in [file.path, 'covers/test.jpg']) {
        await tester.pumpWidget(MaterialApp(
            home: BookCover(
                key: ValueKey(reference),
                reference: reference,
                title: 'Local',
                width: 100,
                height: 144,
                storage: CoverStorage(directory: () async => root))));
        await tester.runAsync(() async =>
            Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        expect(
            tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
        expect(find.text('Local'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
