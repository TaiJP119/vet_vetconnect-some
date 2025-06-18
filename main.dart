import 'package:VetApp/admin/add_banner_page.dart';
import 'package:VetApp/admin/admin_home_page.dart';
import 'package:VetApp/features/user_auth/presentation/pages/notification_page.dart';
import 'package:VetApp/vet/vet_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Pages and features
import 'package:VetApp/features/app/splash_screen/splash_screen.dart';
import 'package:VetApp/features/user_auth/presentation/pages/login_page.dart';
import 'package:VetApp/features/user_auth/presentation/pages/sign_up_page.dart';
import 'package:VetApp/features/user_auth/presentation/pages/home_page.dart';
import 'package:VetApp/features/user_auth/presentation/pages/ai_page.dart';
import 'package:VetApp/features/user_auth/presentation/pages/profile_page.dart';
import 'package:VetApp/features/user_auth/presentation/pages/vet_finder_page.dart';
import 'package:VetApp/features/pet_management/screens/add_pet_page.dart';

// Services
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Global key to manage the navigation state
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: "API-KEYS",
        appId: "APP-ID",
        messagingSenderId: "ID",
        projectId: "PROJECTNAME",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // Initialize Firebase Messaging
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    // Handle foreground notification
    if (message.notification != null) {
      await _showNotification(
        message.notification!.title ?? 'No Title',
        message.notification!.body ?? 'No Body',
      );
    }
  });

  // Listen for notification taps in the foreground and navigate accordingly
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('A new onMessageOpenedApp event was published!');

    // Handle the navigation when the user taps the notification
    if (message.data['click_action'] == 'FLUTTER_NOTIFICATION_CLICK') {
      // Navigate to the report details page with the reportId
      navigatorKey.currentState!.pushNamed(
        '/reportDetails', // Replace with your report details route
        arguments: {
          'reportId': message
              .data['reportId'], // Pass the reportId from the notification data
        },
      );
    }
  });

  runApp(const ProviderScope(child: MyApp()));
}

// Function to show notifications when app is in the foreground
Future<void> _showNotification(String title, String body) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'your_channel_id',
    'Your Channel Name',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: false,
  );

  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    platformChannelSpecifics,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Use the global navigator key
      debugShowCheckedModeBanner: false,
      title: 'VetApp',
      initialRoute: '/',
      routes: {
        '/': (context) => SplashScreen(child: LoginPage()),
        '/login': (context) => LoginPage(),
        '/signUp': (context) => SignUpPage(),
        '/home': (context) => HomePage(),
        '/ai': (context) => AIPage(),
        '/addPet': (context) => const AddPetPage(),
        '/profile': (context) => const ProfilePage(),
        '/vetfinder': (context) => VetFinderPage(),
        '/vetHome': (context) => VetHomePage(),
        '/adminHome': (context) => AdminHomePage(),
        '/reportDetails': (context) =>
            ReportDetailsPage(), // Your report details page
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/notifications') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => NotificationPage(userId: args['userId']),
          );
        }
        return null; // Unknown route
      },
    );
  }
}

class ReportDetailsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> arguments =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;

    final String reportId = arguments?['reportId'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text("Report Details")),
      body: Center(
        child: Text('Report ID: $reportId'),
      ),
    );
  }
}
