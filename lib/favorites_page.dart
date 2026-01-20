import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('請先登入')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏地點 ⭐')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance  
            .collection('favorites')
            .where('uid', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('尚未新增收藏'));
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              return ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: Text(
                  data['comment'] == null || data['comment'].toString().isEmpty
                      ? '未命名地點'
                      : data['comment'],
                ),
                subtitle: Text('標記者：${data['name']}'),
                onTap: () {
                  Navigator.pop(
                    context,
                    LatLng(data['lat'], data['lng']),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}