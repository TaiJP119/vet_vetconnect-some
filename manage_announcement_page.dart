import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_banner_page.dart';
import 'edit_banner_page.dart';

class ManageAnnouncementsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final announcementsRef = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Announcements'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              // your logout logic here
              Navigator.pushNamedAndRemoveUntil(
                  context, "/login", (_) => false);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => AddBannerPage()));
        },
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: announcementsRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return Center(child: Text('No announcements'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final ann = docs[i].data() as Map<String, dynamic>;
              return Card(
                margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: ListTile(
                  leading: ann['imageUrl'] != null &&
                          ann['imageUrl'].toString().isNotEmpty
                      ? Image.network(ann['imageUrl'],
                          width: 40, height: 40, fit: BoxFit.cover)
                      : Icon(Icons.campaign, color: Colors.amber, size: 32),
                  title: Text(ann['banner'] ?? 'No Title'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ann['message'] ?? ''),
                      if ((ann['url'] ?? '').isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.link, color: Colors.blue, size: 16),
                            SizedBox(width: 4),
                            Text(ann['url'],
                                style: TextStyle(
                                    color: Colors.blue, fontSize: 13)),
                          ],
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: Colors.amber),
                        onPressed: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => EditBannerPage(
                                      docId: docs[i].id, data: ann)));
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                    title: Text('Delete Banner'),
                                    content: Text(
                                        'Are you sure you want to delete this banner?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text('Cancel')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: Text('Delete')),
                                    ],
                                  ));
                          if (confirm == true) {
                            await docs[i].reference.delete();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
