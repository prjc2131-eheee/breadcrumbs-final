import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> uploadLocation(LatLng position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('❌ 尚未登入，無法上傳資料');
      return;
    }

    try {
      await _db.collection('bread').add({
        'uid': user.uid, // 🔹 加上 uid
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('☁️ Firestore 上傳成功: $position, user: ${user.uid}');
    } catch (e) {
      debugPrint('❌ Firestore 上傳失敗: $e');
      rethrow;
    }
  }
}