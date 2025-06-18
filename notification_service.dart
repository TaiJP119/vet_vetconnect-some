import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  // ------------------ Initialization for Local Notifications ------------------
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);

    tz.initializeTimeZones();
    // 🔐 Ask Android 13+ permission
    await _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
  }

  // ------------------ Schedule Local Calendar Notification ------------------

  // ------------------ Cancel Local Notification ------------------
  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  // ------------------ Firestore (FCM/Calendar) Notification Save ------------------
  static Future<void> sendUserNotification({
    required String userId,
    required String title,
    required String body,
    required String type, // 'fcm' or 'calendar'
    required DateTime
        eventDate, // Add eventDate to store for 24 hours before event
  }) async {
    // Step 1: Store notification in Firestore (userNotifications collection)
    try {
      if (type == 'calendar') {
        final timeRemaining = eventDate.difference(DateTime.now());

        // If the event is within 24 hours, Firestore handles the scheduling
        if (timeRemaining.inHours <= 24 && timeRemaining.inHours > 0) {
          await FirebaseFirestore.instance.collection('userNotifications').add({
            'userId': userId,
            'title': title, // Store event title
            'body': 'Tomorrow you have the event11: $title.',
            'type': type,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'eventDate': Timestamp.fromDate(eventDate),
          });
          print("Calendar notification stored for 24 hours before event.");
        }
      } else if (type == 'fcm') {
        await FirebaseFirestore.instance.collection('userNotifications').add({
          'userId': userId,
          'title': title,
          'body': body,
          'type': type,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
        print("FCM notification stored in Firestore.");
      }
    } catch (e) {
      print("Error storing notification in Firestore: $e");
    }

    // Step 2: Send FCM Notification (for FCM type)
    if (type == 'fcm') {
      await _sendFCMNotification(userId, title, body);
    }

    // Step 3: Send Local Notification (for Calendar type or others)
    if (type == 'calendar') {
      await _sendLocalNotification(title, body);
    }
  }

  // ------------------ Delete Firestore Notification for Calendar Events ------------------
  static Future<void> deleteFirestoreNotification(String eventTitle) async {
    // Delete the Firestore notification when event is updated or deleted
    await FirebaseFirestore.instance
        .collection('userNotifications')
        .where('eventTitle', isEqualTo: eventTitle)
        .get()
        .then((querySnapshot) {
      for (var doc in querySnapshot.docs) {
        doc.reference.delete();
      }
    });
    print("Deleted Firestore notification for event: $eventTitle");
  }

  // ------------------ Send FCM Notification via HTTP (Data-only) ------------------
  static Future<void> _sendFCMNotification(
      String userId, String title, String body) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    final fcmToken = userDoc['fcmToken'];

    if (fcmToken != null) {
      final serverKey = 'YOUR_SERVER_KEY'; // FCM server key
      final url = Uri.parse('https://fcm.googleapis.com/fcm/send');

      final payload = {
        'to': fcmToken,
        'data': {
          'title': title, // Send the title in data field
          'body': body, // Send the body in data field
          'type': 'fcm', // You can add extra data, like 'type', etc.
        },
      };

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'key=$serverKey',
      };

      try {
        final response = await http.post(
          url,
          headers: headers,
          body: json.encode(payload),
        );

        if (response.statusCode == 200) {
          print('FCM data-only notification sent successfully!');
        } else {
          print('Failed to send notification: ${response.body}');
        }
      } catch (e) {
        print('Error sending notification: $e');
      }
    }
  }

  // ------------------ Send Local Notification ------------------
  static Future<void> _sendLocalNotification(String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'event_channel',
        'Event Notifications',
        channelDescription: 'Reminder for pet events',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
    await _notifications.show(0, title, body, details);
  }

  //------------------ schedule MultiStage Notifications ------------------

  static Future<void> scheduleMultiStageNotifications({
    required String eventId,
    required String title,
    required DateTime dateTime,
  }) async {
    int id1 = eventId.hashCode;
    int id2 = eventId.hashCode + 1;
    int id3 = eventId.hashCode + 2;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'event_channel',
        'Event Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await _notifications.zonedSchedule(
      id1,
      'Upcoming Event',
      '$title in 1 hour!',
      tz.TZDateTime.from(dateTime.subtract(const Duration(hours: 1)), tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );

    await _notifications.zonedSchedule(
      id2,
      'Upcoming Event',
      '$title in 10 minutes!',
      tz.TZDateTime.from(
          dateTime.subtract(const Duration(minutes: 10)), tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );

    await _notifications.zonedSchedule(
      id3,
      'Event Started',
      '$title is starting now!',
      tz.TZDateTime.from(dateTime, tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  static Future<void> scheduleSingleStageNotifications({
    required String eventId,
    required String title,
    required DateTime dateTime,
  }) async {
    int id4 = eventId.hashCode;
    final now = DateTime.now();
    final scheduleTime = dateTime
        .subtract(const Duration(hours: 24))
        .add(const Duration(minutes: 1));

    print('🔔 Scheduling local notif: $title');
    print('🕒 Current time: $now');
    print('📅 Scheduled for: $scheduleTime');

    if (scheduleTime.isBefore(now)) {
      print('⚠️ Not scheduling, scheduled time is in the past.');
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'event_channel',
        'Event Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await _notifications.zonedSchedule(
      id4,
      'Yo! Event Reminder',
      '$title is starting tomorrow!',
      tz.TZDateTime.from(scheduleTime, tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );

    print('✅ Local notification scheduled.');
  }
}
