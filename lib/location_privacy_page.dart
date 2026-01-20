import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationPrivacyPage extends StatelessWidget {
  const LocationPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("請先登入")),
      );
    }

    final uid = user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("位置分享設定"),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final List friends = data['friends'] ?? [];
          final List shareTo = data['shareTo'] ?? [];
          final List hideFrom = data['hideFrom'] ?? [];

          if (friends.isEmpty) {
            return const Center(child: Text("目前沒有好友"));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "誰能看到我的位置",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ...friends.map((friendUid) {
                final isOn = shareTo.contains(friendUid);

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(friendUid)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox();
                    }

                    final friendData =
                    snapshot.data!.data() as Map<String, dynamic>;

                    return SwitchListTile(
                      title: Text(friendData['name'] ?? '好友'),
                      value: isOn,
                      onChanged: (value) {
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({
                          'shareTo': value
                              ? FieldValue.arrayUnion([friendUid])
                              : FieldValue.arrayRemove([friendUid]),
                        });
                      },
                    );
                  },
                );
              }).toList(),

              const Divider(height: 40),

              const Text(
                "我要不要看他的定位",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ...friends.map((friendUid) {
                final isHidden = hideFrom.contains(friendUid);

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(friendUid)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox();
                    }

                    final friendData =
                    snapshot.data!.data() as Map<String, dynamic>;

                    return SwitchListTile(
                      title: Text(friendData['name'] ?? '好友'),
                      subtitle: Text(isHidden ? "已隱藏" : "顯示中"),
                      value: !isHidden,
                      onChanged: (value) {
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({
                          'hideFrom': value
                              ? FieldValue.arrayRemove([friendUid])
                              : FieldValue.arrayUnion([friendUid]),
                        });
                      },
                    );
                  },
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}