import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'support_destination.dart';

Future<VoidCallback?> loadSupportAction() async {
  final destination = await loadSupportDestination();
  if (destination == null) return null;
  return () {
    web.window.open(destination.toString(), '_blank', 'noopener,noreferrer');
  };
}
