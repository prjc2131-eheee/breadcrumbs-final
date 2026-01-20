import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

class FriendsMapPage extends StatefulWidget {
  final String friendUid;
  final String friendName;

  const FriendsMapPage({
    super.key,
    required this.friendUid,
    required this.friendName,
  });

  @override
  State<FriendsMapPage> createState() => _FriendsMapPageState();
}

class _FriendsMapPageState extends State<FriendsMapPage> {
  final mapController = MapController();

  LatLng? friendCurrentPosition;

  StreamSubscription? locationSub;
  StreamSubscription? privacySub;

  final myUid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _listenPrivacy();
  }

  /// 🔐 監聽「我是否隱藏此好友」
  void _listenPrivacy() {
    privacySub = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .snapshots()
        .listen((doc) {
      final data = doc.data() as Map<String, dynamic>?;

      if (data == null) return;

      final List hideFrom = data['hideFrom'] ?? [];

      final isHidden = hideFrom.contains(widget.friendUid);

      if (isHidden) {
        _stopListeningLocation();
        setState(() {
          friendCurrentPosition = null;
        });
      } else {
        _startListeningLocation();
      }
    });
  }

  /// ▶️ 監聽好友位置
  void _startListeningLocation() {
    if (locationSub != null) return;

    locationSub = FirebaseFirestore.instance
        .collection('locations')
        .doc(widget.friendUid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;

      final lat = data['lat'];
      final lng = data['lng'];

      if (lat == null || lng == null) return;

      setState(() {
        friendCurrentPosition = LatLng(lat, lng);
      });

      mapController.move(friendCurrentPosition!, 16);
    });
  }

  /// ⛔ 停止監聽
  void _stopListeningLocation() {
    locationSub?.cancel();
    locationSub = null;
  }

  @override
  void dispose() {
    locationSub?.cancel();
    privacySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.friendName} 的位置")),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: LatLng(23.0, 120.0),
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.bread',
          ),
          if (friendCurrentPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: friendCurrentPosition!,
                  width: 40,
                  height: 40,
                  child: const Text("🧑‍🤝‍🧑", style: TextStyle(fontSize: 35)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}