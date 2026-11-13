import 'package:shared_preferences/shared_preferences.dart';

abstract class TutorialPreferences {
  Future<bool> isCompleted();
  Future<void> complete();
}

class LocalTutorialPreferences implements TutorialPreferences {
  static const completionKey = 'tutorial_completed_v1';

  @override
  Future<bool> isCompleted() async =>
      (await SharedPreferences.getInstance()).getBool(completionKey) ?? false;

  @override
  Future<void> complete() async {
    final saved = await (await SharedPreferences.getInstance())
        .setBool(completionKey, true);
    if (!saved) throw StateError('Nie udało się zapisać ustawienia.');
  }
}
