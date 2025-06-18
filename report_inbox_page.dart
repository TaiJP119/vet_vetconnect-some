import 'package:VetApp/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:photo_view/photo_view.dart';

class AdminReportInboxPage extends StatefulWidget {
  const AdminReportInboxPage({super.key});

  @override
  _AdminReportInboxPageState createState() => _AdminReportInboxPageState();
}

class _AdminReportInboxPageState extends State<AdminReportInboxPage> {
  String? _selectedStatus;
  String? _selectedIssueType;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Report Inbox")),
      body: Column(
        children: [
          _buildFilterControls(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('userReports')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Full report list from Firestore
                final reports = snapshot.data!.docs;

                // Apply filtering
                final filteredReports = reports.where((doc) {
                  final data = doc.data() as Map;
                  final matchesStatus = _selectedStatus == null ||
                      data['status'] == _selectedStatus;
                  final matchesIssueType = _selectedIssueType == null ||
                      data['issueType'] == _selectedIssueType;
                  return matchesStatus && matchesIssueType;
                }).toList();

                return ListView.builder(
                  itemCount: filteredReports.length,
                  itemBuilder: (context, index) {
                    final report = filteredReports[index];
                    final data = report.data() as Map;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        title: Text(data['description']),
                        subtitle: Text(
                            "Submitted by: ${data['username']} - Status: ${data['status']}"),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (data['isRead'] != true)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Text('!',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _viewReportDetails(report.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.reply),
                              onPressed: () => _replyToReport(report.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        children: [
          DropdownButton<String>(
            hint: const Text("Filter by Status"),
            value: _selectedStatus,
            items: [null, 'Open', 'In Progress', 'Resolved', 'Ignored']
                .map((status) => DropdownMenuItem<String>(
                      value: status,
                      child: Text(status ?? 'All'),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedStatus = value;
              });
            },
          ),
          DropdownButton<String>(
            hint: const Text("Filter by Issue Type"),
            value: _selectedIssueType,
            items: [
              null,
              'General Issue',
              'Bug Report',
              'Technical Issue',
              'Other'
            ]
                .map((type) => DropdownMenuItem<String>(
                      value: type,
                      child: Text(type ?? 'All'),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedIssueType = value;
              });
            },
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedStatus = null;
                _selectedIssueType = null;
              });
            },
            child: const Text("Clear Filters"),
          ),
        ],
      ),
    );
  }

  void _showZoomableImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Hero(
              tag: imageUrl,
              child: PhotoView(
                imageProvider: NetworkImage(imageUrl),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _viewReportDetails(String reportId) async {
    final reportDoc = await FirebaseFirestore.instance
        .collection('userReports')
        .doc(reportId)
        .get();
    final data = reportDoc.data() as Map<String, dynamic>;
    // Extract the event date from the report, using the 'timestamp' field
    DateTime eventDate = (data['timestamp'] as Timestamp).toDate();
    showDialog(
      context: context,
      builder: (context) {
        String? localStatus = data['status'];
        final replyController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Report Details"),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Title: ${data['issueType']}"),
                    Text("Description: ${data['description']}"),
                    Text("Status: $localStatus"),
                    Text("Submitted by: ${data['username']}"),
                    Text(
                      "Submitted on: ${data['timestamp']?.toDate().toString().split('.')[0] ?? 'Unknown'}",
                    ),
                    if (data['adminReply'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text("Admin Reply: ${data['adminReply']}"),
                      ),
                    if (data['imageUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: GestureDetector(
                          onTap: () => _showZoomableImage(data['imageUrl']),
                          child: Hero(
                            tag: data['imageUrl'],
                            child: Image.network(
                              data['imageUrl'],
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text("Update Status:"),
                    DropdownButton<String>(
                      value: localStatus,
                      isExpanded: true,
                      items: ['Open', 'In Progress', 'Resolved', 'Ignored']
                          .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(status),
                              ))
                          .toList(),
                      onChanged: (newStatus) async {
                        if (newStatus != null) {
                          await FirebaseFirestore.instance
                              .collection('userReports')
                              .doc(reportId)
                              .update({'status': newStatus});
                          setDialogState(() {
                            localStatus = newStatus;
                          });
                          setState(() {}); // Refresh main UI
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text("Admin Reply:"),
                    TextField(
                      controller: replyController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          hintText: "Enter your reply..."),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final replyText = replyController.text.trim();
                    if (replyText.isNotEmpty) {
                      final reply = {
                        'sender': 'admin',
                        'message': replyText,
                        'timestamp': FieldValue.serverTimestamp(),
                      };

                      // Update the report with the admin reply
                      await FirebaseFirestore.instance
                          .collection('userReports')
                          .doc(reportId)
                          .update({
                        'adminReply': replyText,
                      });

                      // Fetch report data again to retrieve userId
                      final reportDoc = await FirebaseFirestore.instance
                          .collection('userReports')
                          .doc(reportId)
                          .get();

                      if (reportDoc.exists) {
                        final reportData =
                            reportDoc.data() as Map<String, dynamic>;

                        // Ensure the 'userId' is present in the report data
                        final userId = reportData['userId'];
                        print("UserID: $userId"); // Debug print

                        if (userId == null) {
                          print(
                              "No userId found in report data for report: $reportId");
                          return;
                        }

                        // Store the notification in Firestore and send it as FCM
                        try {
                          await NotificationService.sendUserNotification(
                            userId: userId,
                            title: 'Admin Reply',
                            body: replyText,
                            type: 'fcm', // FCM notification
                            eventDate:
                                eventDate, // <-- Pass the event date here
                          );
                          print(
                              'Notification sent to user $userId with message: $replyText');
                        } catch (e) {
                          print('Error saving notification to Firestore: $e');
                        }

                        // Verify notification is stored in Firestore
                        final notificationsSnapshot = await FirebaseFirestore
                            .instance
                            .collection('userNotifications')
                            .where('userId', isEqualTo: userId)
                            .get();

                        if (notificationsSnapshot.docs.isEmpty) {
                          print(
                              "No notifications found in Firestore for user $userId.");
                        } else {
                          notificationsSnapshot.docs.forEach((doc) {
                            print('Notification: ${doc.data()}');
                          });
                        }
                      }

                      setState(() {});
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Reply and update sent.")),
                      );
                    }
                  },
                  child: const Text("Send Reply"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _markReportResolved(String reportId) async {
    await FirebaseFirestore.instance
        .collection('userReports')
        .doc(reportId)
        .update({'status': 'Resolved'});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Report marked as resolved.")),
    );
  }

  void _replyToReport(String reportId) async {
    final replyController = TextEditingController();

    // Fetch current status for fallback
    final docSnapshot = await FirebaseFirestore.instance
        .collection('userReports')
        .doc(reportId)
        .get();
    final data = docSnapshot.data() as Map<String, dynamic>;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Reply to Report"),
          content: TextField(
            controller: replyController,
            decoration: const InputDecoration(labelText: "Your reply"),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final replyText = replyController.text.trim();

                if (replyText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Reply cannot be empty.")),
                  );
                  return;
                }

                try {
                  await FirebaseFirestore.instance
                      .collection('userReports')
                      .doc(reportId)
                      .update({
                    'adminReply': replyText,
                  });

                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Reply and update sent.")),
                  );
                } catch (e) {
                  print("Reply error: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to send reply: $e")),
                  );
                }
              },
              child: const Text("Send Reply"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }
}
