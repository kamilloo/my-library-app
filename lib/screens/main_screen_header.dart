import 'package:flutter/material.dart';

import 'supporter_badge.dart';
import 'tutorial_screen.dart';

const mainScreenPadding = EdgeInsets.fromLTRB(20, 12, 20, 110);

class MainScreenHeader extends StatefulWidget {
  const MainScreenHeader({
    required this.title,
    required this.onSearchChanged,
    this.searchHint = 'Szukaj tytułu lub autora',
    this.searchActions,
    super.key,
  });

  final String title;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;
  final Iterable<Widget>? searchActions;

  @override
  State<MainScreenHeader> createState() => _MainScreenHeaderState();
}

class _MainScreenHeaderState extends State<MainScreenHeader>
    with AutomaticKeepAliveClientMixin<MainScreenHeader> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final supporterOwned = SupporterBillingScope.of(context)?.owned == true;
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(widget.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          if (supporterOwned)
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 4),
              child: SupporterBadgeImage(size: 36),
            ),
          const TutorialHelpButton(),
        ]),
        const SizedBox(height: 8),
        SearchBar(
          leading: const Icon(Icons.search),
          hintText: widget.searchHint,
          onChanged: widget.onSearchChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          trailing: widget.searchActions,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// Accept Polish spelling with or without diacritics, including decomposed input.
String normalizeMainSearch(String value) {
  const accented = 'ąćęłńóśźż';
  const plain = 'acelnoszz';
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u0301\u0307\u0328]'), '')
      .replaceAllMapped(
          RegExp('[$accented]'), (match) => plain[accented.indexOf(match[0]!)]);
}
