import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'route_map_page.dart';

class SharedRoutesPage extends StatelessWidget {
  const SharedRoutesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shared_routes')
          .where('toUid', isEqualTo: uid)
          .orderBy('sharedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text('尚未收到任何分享'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final share = docs[index].data() as Map<String, dynamic>;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('routes')
                  .doc(share['routeId'])
                  .get(),
              builder: (context, routeSnap) {
                if (!routeSnap.hasData) {
                  return const ListTile(title: Text('載入中...'));
                }

                final route =
                routeSnap.data!.data() as Map<String, dynamic>?;

                if (route == null) return const SizedBox();

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(share['fromUid'])
                      .get(),
                  builder: (context, userSnap) {
                    final user =
                    userSnap.data?.data() as Map<String, dynamic>?;

                    final name = user?['name'] ?? '好友';

                    final ts = share['sharedAt'] as Timestamp?;
                    final time = ts == null
                        ? ''
                        : DateFormat('yyyy/MM/dd HH:mm')
                        .format(ts.toDate());

                    return ListTile(
                      leading: const Icon(Icons.route),
                      title: Text(route['name'] ?? '未命名路線'),
                      subtitle: Text('來自 $name ・ $time'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RouteMapPage(routeData: route),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}