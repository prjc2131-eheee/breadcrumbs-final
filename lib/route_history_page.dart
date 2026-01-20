import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'route_map_page.dart';
import 'routes_page.dart';

class RouteHistoryPage extends StatelessWidget {
  const RouteHistoryPage({super.key});

  void _shareRoute(
      BuildContext context,
      String routeId,
      ) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final List friends =
    List.from(userDoc.data()?['friends'] ?? []);

    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('你目前沒有好友')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('分享給好友'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: friends.map((friendUid) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(friendUid)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const ListTile(
                        title: Text('讀取中...'),
                      );
                    }

                    final userData = snapshot.data!.data()
                    as Map<String, dynamic>?;

                    final friendName =
                        userData?['name'] ?? '未命名使用者';

                    final photoUrl = userData?['photoURL'];

                    return ListTile(
                      leading: photoUrl != null
                          ? CircleAvatar(
                        backgroundImage:
                        NetworkImage(photoUrl),
                      )
                          : const CircleAvatar(
                        child: Icon(Icons.person),
                      ),
                      title: Text(friendName),
                      onTap: () async {
                        await FirebaseFirestore.instance
                            .collection('shared_routes')
                            .add({
                          'routeId': routeId,
                          'fromUid': uid,
                          'toUid': friendUid,
                          'sharedAt': Timestamp.now(),
                        });

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                            Text('✅ 已分享給 $friendName'),
                          ),
                        );
                      },
                    );
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'ℹ️ 長按路線可刪除',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('routes')
                  .where('userId', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                if (!snapshot.hasData ||
                    snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('尚未儲存任何路線'),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data()
                    as Map<String, dynamic>;

                    final int colorValue =
                        (data['color'] as int?) ??
                            Colors.blue.value;

                    final Timestamp? ts =
                    data['createdAt'] as Timestamp?;
                    final String timeText = ts == null
                        ? ''
                        : DateFormat('yyyy/MM/dd HH:mm')
                        .format(ts.toDate());

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(colorValue),
                      ),
                      title:
                      Text(data['name'] ?? '未命名路線'),
                      subtitle: Text(timeText),

                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () {
                              _shareRoute(
                                context,
                                docs[index].id,
                              );
                            },
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RouteMapPage(routeData: data),
                          ),
                        );
                      },

                      onLongPress: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title:
                            const Text('刪除路線'),
                            content: const Text(
                                '確定要刪除這條路線嗎？'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  Colors.red,
                                ),
                                onPressed: () async {
                                  await FirebaseFirestore.instance
                                      .collection('routes')
                                      .doc(docs[index].id)
                                      .delete();

                                  Navigator.pop(context);
                                },
                                child:
                                const Text('刪除'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
    );
  }
}