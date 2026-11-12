import 'package:flutter/services.dart';

/// Opening a composer provides no delivery or cancellation receipt.
class LoanSms {
  const LoanSms();
  static const channel = MethodChannel('my_library/offline_loans');

  Future<bool> compose(String text, String phone) async {
    try {
      await channel.invokeMethod<void>('sms', {'text': text, 'phone': phone});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> share(String text) async {
    try {
      await channel.invokeMethod<void>('share', {'text': text});
      return true;
    } catch (_) {
      return false;
    }
  }
}
