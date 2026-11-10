import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/book.dart';
import 'return_reminders.dart';

class LocalReminderNotifications extends ReminderNotifications {
  @override
  Future<bool> needsRationale() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await const MethodChannel('my_library/reminders')
            .invokeMethod<bool>('notificationRationale') ??
        false;
  }

  @override
  Future<void> openSettings() async {
    await prepare();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (android != null) await android.openAppNotificationSettings();
    if (ios != null) await ios.openAppNotificationSettings();
  }

  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  static const channel = AndroidNotificationChannel(
    'book_returns',
    'Terminy zwrotu',
    description: 'Dobrowolne przypomnienia o zwrocie książek',
    importance: Importance.defaultImportance,
  );

  @override
  Future<void> prepare() async {
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    if (initialized) return;
    await plugin.initialize(
        settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_book'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    initialized = true;
  }

  @override
  Future<bool> authorized({bool request = false}) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      if (request && await android.areNotificationsEnabled() != true) {
        await android.requestNotificationsPermission();
      }
      final channels = await android.getNotificationChannels();
      final blocked = channels?.any(
              (c) => c.id == channel.id && c.importance == Importance.none) ??
          false;
      return await android.areNotificationsEnabled() == true && !blocked;
    }
    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      if (request) {
        return await ios.requestPermissions(
                alert: true, sound: true, badge: false) ==
            true;
      }
      final permissions = await ios.checkPermissions();
      return permissions?.isEnabled == true;
    }
    return false;
  }

  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);

  @override
  Future<Map<int, String?>> pendingRequests() async => {
        for (final request in await plugin.pendingNotificationRequests())
          request.id: request.payload,
      };

  @override
  Future<void> schedule(int id, Book book, tz.TZDateTime date) =>
      plugin.zonedSchedule(
        id: id,
        title: 'Termin zwrotu książki',
        body: 'Dziś termin zwrotu: „${book.title}”.',
        scheduledDate: date,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(channel.id, channel.name,
              channelDescription: channel.description,
              visibility: NotificationVisibility.private),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminderFingerprint(book, date),
      );
}
