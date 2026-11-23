import 'dart:convert';

import 'package:flutter/services.dart';

Uri? validateSupportDestination(String value) {
  final uri = Uri.tryParse(value);
  // Require a plain creator slug and reject credentials, ports, and tracking.
  if (uri == null ||
      !RegExp(r'^https://buycoffee\.to/[a-z0-9]+(?:-[a-z0-9]+)*$')
          .hasMatch(value) ||
      uri.toString() != value) {
    return null;
  }
  return uri;
}

Future<Uri?> loadSupportDestination() async {
  try {
    final config =
        jsonDecode(await rootBundle.loadString('assets/support.json'));
    if (config is Map<String, dynamic> && config['url'] is String) {
      return validateSupportDestination(config['url'] as String);
    }
  } on Exception {
    // Help remains available even if the optional configuration is missing.
  }
  return null;
}
