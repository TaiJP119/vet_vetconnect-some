// import 'package:VetApp/features/user_auth/presentation/pages/add_event_page.dart';
import 'package:VetApp/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
// import '../../../../services/notification_service.dart';
// import 'add_event_page.dart';
import 'add_event_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<DocumentSnapshot>> _events = {};

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('events')
        .get();

    Map<DateTime, List<DocumentSnapshot>> eventsMap = {};

    for (var doc in snapshot.docs) {
      final date = (doc['date'] as Timestamp).toDate();
      final dateOnly = DateTime(date.year, date.month, date.day);
      eventsMap[dateOnly] = eventsMap[dateOnly] ?? [];
      eventsMap[dateOnly]!.add(doc);
    }

    setState(() {
      _events = eventsMap;
    });
  }

  List<DocumentSnapshot> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
  }

  void _navigateToAddEvent() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddEventPage()),
    );
    _fetchEvents(); // Refresh after adding
  }

  void _editEvent(DocumentSnapshot doc) async {
    final titleController = TextEditingController(text: doc['title']);
    final petNameController = TextEditingController(text: doc['petName']);
    DateTime date = (doc['date'] as Timestamp).toDate();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Event"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: "Title")),
              TextField(
                  controller: petNameController,
                  decoration: const InputDecoration(labelText: "Pet Name")),
              const SizedBox(height: 10),
              Text(DateFormat.yMMMd().add_jm().format(date)),
              ElevatedButton(
                child: const Text("Pick New Time"),
                onPressed: () async {
                  final newDate = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (newDate != null) {
                    final newTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(date),
                    );
                    if (newTime != null) {
                      date = DateTime(newDate.year, newDate.month, newDate.day,
                          newTime.hour, newTime.minute);
                    }
                  }
                },
              )
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            TextButton(
                child: const Text("Save"),
                onPressed: () async {
                  final oldEventId = doc['eventId'] ?? doc.id;

                  // Cancel existing notifications for the event
                  await cancelNotifications(oldEventId);

                  // Update the event in Firestore
                  await doc.reference.update({
                    'title': titleController.text,
                    'petName': petNameController.text,
                    'date': Timestamp.fromDate(date),
                  });

                  final updatedDoc = await doc.reference.get();
                  final newEventId = updatedDoc['eventId'] ?? updatedDoc.id;

                  // Reschedule notifications based on the updated event date
                  await NotificationService.scheduleMultiStageNotifications(
                      eventId: newEventId,
                      title: titleController.text,
                      dateTime: date);

                  // Store the notification in Firebase
                  // final userId = FirebaseAuth.instance.currentUser!.uid;
                  // await NotificationService.sendUserNotification(
                  //   userId: userId,
                  //   title: titleController.text,
                  //   body: '$titleController.text is starting soon!22',
                  //   type: 'calendar', // Calendar reminder type
                  //   eventDate: date, // <-- Pass the event date here
                  // );

                  Navigator.pop(context);
                  _fetchEvents(); // Refresh the event list
                }),
          ],
        );
      },
    );
  }

  void _deleteEvent(DocumentSnapshot doc) async {
    final eventId = doc['eventId'] ?? doc.id; // Use eventId or doc id
    // Cancel any scheduled notifications for this event
    await cancelNotifications(eventId);

    // Delete the event from Firestore
    await doc.reference.delete();

    // Refresh the event list
    _fetchEvents();
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Event Calendar"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pushNamedAndRemoveUntil(
                  context, "/login", (route) => false);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2100),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
            onDaySelected: _onDaySelected,
            eventLoader: _getEventsForDay,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: selectedEvents.length,
              itemBuilder: (context, index) {
                final event = selectedEvents[index];
                final date = (event['date'] as Timestamp).toDate();

                return Dismissible(
                  key: ValueKey(event.id),
                  background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Icon(Icons.delete, color: Colors.white),
                      )),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteEvent(event),
                  child: ListTile(
                    title: Text(event['title']),
                    subtitle: Text(
                        "Pet: ${event['petName']}\n${DateFormat.yMMMd().add_jm().format(date)}"),
                    onTap: () => _editEvent(event),
                  ),
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddEvent,
        child: const Icon(Icons.add),
      ),
    );
  }
}
