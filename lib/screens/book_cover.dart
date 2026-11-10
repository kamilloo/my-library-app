import 'dart:io';
import 'package:flutter/material.dart';
import '../services/cover_storage.dart';

class BookCover extends StatelessWidget {
  const BookCover(
      {required this.reference,
      required this.title,
      required this.width,
      required this.height,
      this.storage,
      super.key});
  final String? reference;
  final String title;
  final double width;
  final double height;
  final CoverStorage? storage;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(9)),
      child: Text(title.isEmpty ? 'Brak okładki' : title,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(fontFamily: 'serif', fontSize: width > 80 ? 18 : 11)),
    );
    final value = reference;
    if (value == null || value.isEmpty) return placeholder;
    Widget image;
    if (CoverStorage.isNetwork(value)) {
      image = Image.network(value,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder);
    } else {
      image = FutureBuilder<File>(
        future: (storage ?? CoverStorage()).resolve(value),
        builder: (context, snapshot) => snapshot.hasData
            ? Image.file(snapshot.data!,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder)
            : placeholder,
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(9), child: image);
  }
}
