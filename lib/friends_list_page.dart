import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendsListPage extends StatelessWidget {
  final Function(String)? onLocateFriend; // 新增：通知地圖移動

  const FriendsListPage({super.key, this.onLocateFriend});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('請先登入')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('好友列表')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List friends = data['friends'] ?? [];

          if (friends.isEmpty) {
            return const Center(child: Text('尚無好友'));
          }

          return ListView.builder(
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friendUid = friends[index];

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(friendUid)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const ListTile(
                      title: Text('載入中...'),
                    );
                  }

                  final friendData =
                  snapshot.data!.data() as Map<String, dynamic>;

                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(friendData['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friendData['email'],
                          overflow: TextOverflow.ellipsis,
                        ),
                        _buildShareStatus(friendUid),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 📍 定位
                        IconButton(
                          icon: const Icon(Icons.my_location),
                          onPressed: () {
                            Navigator.pop(context, friendUid);
                          },
                        ),
                        // 🗑 刪除好友
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            _confirmDelete(context, friendUid);
                          },
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
    );
  }

  /// 顯示好友位置分享狀態
  Widget _buildShareStatus(String friendUid) {
    final locRef = FirebaseFirestore.instance
        .collection('locations')
        .doc(friendUid);

    return StreamBuilder<DocumentSnapshot>(
      stream: locRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Text(
            "❌ 未分享",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final share = data['shareLocation'] == true;

        return Text(
          share ? "🟢 分享中" : "🔴 關閉",
          style: TextStyle(
            color: share ? Colors.green : Colors.red,
            fontSize: 12,
          ),
        );
      },
    );
  }
  Future<void> _removeFriend(String myUid, String friendUid) async {
    final firestore = FirebaseFirestore.instance;

    // 從我這邊移除
    await firestore.collection('users').doc(myUid).update({
      'friends': FieldValue.arrayRemove([friendUid]),
    });

    // 從對方那邊移除
    await firestore.collection('users').doc(friendUid).update({
      'friends': FieldValue.arrayRemove([myUid]),
    });
  }

  void _confirmDelete(BuildContext context, String friendUid) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除好友'),
        content: const Text('確定要刪除這位好友嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              final firestore = FirebaseFirestore.instance;

              // 我這邊刪
              await firestore.collection('users').doc(myUid).update({
                'friends': FieldValue.arrayRemove([friendUid]),
              });

              // 對方那邊也刪我
              await firestore.collection('users').doc(friendUid).update({
                'friends': FieldValue.arrayRemove([myUid]),
              });
            },
            child: const Text(
              '刪除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}