import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:latlong2/latlong.dart' show Distance, LengthUnit;
import 'location_service.dart';
import 'firestore_service.dart';
import 'route_service.dart';
import 'friends_page.dart';
import 'friends_list_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'favorites_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'route_history_page.dart';
import 'location_privacy_page.dart';
import 'routes_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // === 核心狀態 ===
  LatLng? currentPosition;
  LatLng? destination;
  final MapController mapController = MapController();
  final List<LatLng> pathPoints = [];
  List<String> friendUids = [];
  Map<String, Map<String, dynamic>> allUsers = {};
  final RouteService routeService = RouteService();
  List<String> myHideFrom = [];
  Map<String, bool> locationPrivacy = {};
  List<String> hideFrom = [];
  List<String> shareTo = [];


  bool shareLocation = false;
  // === 錄製狀態與 Stream 管理 (取代 Timer) ===
  bool isRecording = false;
  bool favoriteMode = false;
  LatLng? lastRecordedPosition;
  double minDistance = 5.0; // GPS 最小移動距離（公尺）
  StreamSubscription<LatLng>? _locationSubscription;
  StreamSubscription<LatLng>? _singleLocationSubscription;

  // === 登入相關 ===
  User? user = FirebaseAuth.instance.currentUser;

  // 初始化時檢查登入狀態
  @override
  void initState() {
    super.initState();

    // 🔐 監聽登入狀態（唯一入口）
    FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
      if (!mounted) return;

      setState(() {
        user = newUser;
      });

      // ✅ 一定要等登入完成
      if (newUser != null) {
        // 只有這裡才能用 uid
        _loadShareSetting();
        _loadFriends();
        _loadLocationPrivacy();
        _loadPrivacySetting();

        final uid = newUser.uid;

        // 監聽自己的使用者資料
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots()
            .listen((doc) {
          final data = doc.data();
          if (data == null) return;

          if (!mounted) return;

          setState(() {
            myHideFrom = List<String>.from(data['hideFrom'] ?? []);
          });
        });
      }
    });

    // 🌍 監聽所有使用者（頭像 / 名字 / shareTo）
    FirebaseFirestore.instance.collection('users').snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        allUsers[doc.id] = doc.data() as Map<String, dynamic>;
      }

      if (!mounted) return;
      setState(() {});
    });
  }

  // === 資源清理：App 關閉時停止追蹤 ===
  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  // === 登入/登出邏輯 (不變) ===
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 登入成功')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 登入失敗：$e')),
      );
    }
  }

  Future<void> signOut() async {
    _stopRecording();
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> updateShareLocation(bool value) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'shareLocation': value,
    });
  }
  Future<void> _loadFriends() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final data = userDoc.data();
    if (data == null) return;

    setState(() {
      friendUids = List<String>.from(data['friends'] ?? []);
    });

    print(" 好友列表: $friendUids");
  }

  Future<void> _loadLocationPrivacy() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('location_privacy')
        .get();

    final Map<String, bool> temp = {};

    for (var doc in snapshot.docs) {
      temp[doc.id] = doc['allow'] == true;
    }

    setState(() {
      locationPrivacy = temp;
    });

    debugPrint("🔒 隱私設定: $locationPrivacy");
  }

  Future<void> _loadPrivacySetting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final data = doc.data();
    if (data == null) return;

    setState(() {
      hideFrom = List<String>.from(data['hideFrom'] ?? []);
      shareTo = List<String>.from(data['shareTo'] ?? []);
    });

    debugPrint("🙈 hideFrom = $hideFrom");
    debugPrint("📤 shareTo = $shareTo");
  }

  // === 錄製控制：切換開始/結束 ===
  void _toggleRecording() {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛑 請先登入才能開始記錄路線')),
      );
      return;
    }

    if (isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() {
    setState(() {
      isRecording = true;
      pathPoints.clear();
      lastRecordedPosition = null;
    });

    _locationSubscription = LocationService.getPositionStream().listen(
          (position) {
        _processNewLocation(position);
      },
      onError: (e) {
        _stopRecording();
        debugPrint('❌ GPS 追蹤 Stream 錯誤: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS 追蹤發生錯誤，已停止記錄: $e')),
        );
      },
      onDone: () {
        debugPrint('GPS Stream 完成 (通常不會發生)');
      },
      cancelOnError: false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 路線記錄開始，持續追蹤中...')),
    );
  }

  void _stopRecording() async {
    _locationSubscription?.cancel();
    _locationSubscription = null;

    setState(() {
      isRecording = false;
    });

    if (user == null || pathPoints.length < 2) return;

    String routeName = '';
    Color selectedColor = Colors.orange;
    Color pickerColor = selectedColor;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('儲存本次路線？'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '路線名稱',
                    ),
                    onChanged: (v) => routeName = v,
                  ),
                  const SizedBox(height: 12),
                  ColorPicker(
                    pickerColor: selectedColor,
                    onColorChanged: (color) {
                      setDialogState(() {
                        selectedColor = color;
                      });
                    },
                    enableAlpha: false,
                    displayThumbColor: true,
                  ),
                ],)
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不儲存'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
    if (shouldSave == true) {
      await routeService.saveRoute(
        uid: user!.uid,
        name: routeName,
        colorValue: selectedColor.value,
        userName: user!.displayName ?? '匿名',
        userPhoto: user!.photoURL,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 路線已儲存')),
      );
    }
    routeService.clear();
  }

  // === 處理新的位置點、濾波並上傳 (核心邏輯) ===
  void _processNewLocation(LatLng position) async {
    bool shouldRecord = false;

    // 1. 濾波器邏輯：檢查距離是否大於 minDistance (10m)
    if (lastRecordedPosition == null) {
      shouldRecord = true;
    } else {
      final distance = Distance().as(LengthUnit.Meter, lastRecordedPosition!, position);

      if (distance >= minDistance) {
        shouldRecord = true;
      } else {
        debugPrint('Debug: 距離太近 (${distance.toStringAsFixed(2)}m)，忽略此點 (GPS 雜訊)');
      }
    }

    // 2. 執行記錄和上傳
    if (shouldRecord) {
      try {
        setState(() {
          currentPosition = position;
          pathPoints.add(position);
          routeService.addPoint(position);
        });
        lastRecordedPosition = position;

        await FirestoreService.uploadLocation(position);
        debugPrint('☁️ Firestore 上傳成功: $position');

      } catch (e) {
        debugPrint('❌ Firestore 上傳失敗: $e');
      }
    } else {
      setState(() {
        currentPosition = position;
      });
    }

    mapController.move(currentPosition!, mapController.camera.zoom);
  }

  // === 地圖操作方法 (不變) ===
  void _goToCurrentPosition() {
    if (currentPosition != null) {
      mapController.move(currentPosition!, 16);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有位置可回到')),
      );
    }
  }

  void _clearRoute() {
    setState(() {
      destination = null;
      pathPoints.clear();
      lastRecordedPosition = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('路線已清除')),
    );
  }

  void _setDestination(LatLng point) async {
    setState(() {
      destination = point;
    });

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先取得目前位置')),
      );
      return;
    }

    _stopRecording();

    try {
      final routePoints = await RouteService.getRoute(currentPosition!, destination!);
      setState(() {
        pathPoints
          ..clear()
          ..addAll(routePoints);
      });
      mapController.move(destination!, 15);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法取得路線: $e')),
      );
    }
  }

  void _getCurrentLocationOnce() async {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛑 請先登入才能取得位置')),
      );
      return;
    }

    try {
      // 1. 檢查權限 (避免因為沒權限導致後面不上傳)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // 2. 獲取位置
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );

      setState(() {
        currentPosition = LatLng(pos.latitude, pos.longitude);
      });

      mapController.move(currentPosition!, 16);

      // 3. 上傳到 Firestore
      final uid = user!.uid;

      await FirebaseFirestore.instance
          .collection('locations')
          .doc(uid)
          .set({
        'uid': uid, // 建議存入 uid，方便後續查詢
        'lat': pos.latitude,
        'lng': pos.longitude,
        'shareLocation': shareLocation, // 使用你 State 裡的變數
        'updatedAt': FieldValue.serverTimestamp(), // 確保使用 Firebase 伺服器時間
      }, SetOptions(merge: false)); // 這裡改 false 可以直接覆蓋掉舊的亂資料

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📡 位置已更新並同步')),
      );

    } catch (e) {
      debugPrint('❌ 取得位置失敗: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取得位置失敗: $e')),
      );
    }
  }

  void _showAddFavoriteDialog(LatLng point) {
    final TextEditingController commentController =
    TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增收藏地點 ⭐'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('標記者：${user?.displayName ?? "匿名"}'),
            const SizedBox(height: 10),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: '留言',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            child: const Text('儲存'),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('favorites')
                  .add({
                'uid': user!.uid,
                'name': user!.displayName ?? '匿名',
                'comment': commentController.text,
                'lat': point.latitude,
                'lng': point.longitude,
                'createdAt': Timestamp.now(),
              });

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('⭐ 收藏地點已新增')),
              );
            },
          ),
        ],
      ),
    );
  }
  void _showFavoriteDetail(String docId, Map<String, dynamic> data) {
    final Timestamp ts = data['createdAt'] as Timestamp;
    final DateTime time = ts.toDate();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('收藏地點'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('標記者：${data['name']}'),
            const SizedBox(height: 8),
            Text('留言：${data['comment']}'),
            const SizedBox(height: 8),
            Text(
              '紀錄時間：'
                  '${time.year}/${time.month}/${time.day} '
                  '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
          if (data['uid'] == user?.uid)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmDeleteFavorite(docId);
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
  void _confirmDeleteFavorite(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除收藏'),
        content: const Text('確定要刪除這個收藏地點嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('favorites')
                  .doc(docId)
                  .delete();

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🗑 收藏地點已刪除')),
              );
            },
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }
  void _moveToFavorite(LatLng point) {
    setState(() {
      destination = null;
    });

    mapController.move(point, 17);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⭐ 已移動到收藏地點')),
    );
  }
  void _loadShareSetting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (doc.exists && doc.data()!.containsKey('shareLocation')) {
      setState(() {
        shareLocation = doc['shareLocation'];
      });
    }
  }

  void _showFriendDialog(String name, String? photoUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 👤 左邊頭像
                ClipOval(
                  child: photoUrl != null
                      ? Image.network(
                    photoUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                      : Container(
                    width: 48,
                    height: 48,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.person, size: 28),
                  ),
                ),

                const SizedBox(width: 14),

                // 🧑 右邊名字
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _moveToFriend(String friendUid) async {
    final doc = await FirebaseFirestore.instance
        .collection('locations')
        .doc(friendUid)
        .get();

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('好友尚未分享位置')),
      );
      return;
    }

    final data = doc.data()!;
    final lat = data['lat'];
    final lng = data['lng'];

    mapController.move(LatLng(lat, lng), 16.0,);
  }

  Widget _colorDot(
      Color color,
      Color selected,
      Function(Color) onTap,
      ) {
    return GestureDetector(
      onTap: () => setState(() => onTap(color)),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected == color ? Colors.black : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Breadcrumbs Tracker')),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ... Drawer UI 保持不變
            UserAccountsDrawerHeader(
              accountName: Text(user?.displayName ?? '尚未登入'),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null ? const Icon(Icons.person, size: 40) : null,
              ),
              decoration: const BoxDecoration(color: Colors.deepPurple),
            ),
            if (user == null)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('使用 Google 登入'),
                onTap: () async {
                  Navigator.pop(context);
                  await signInWithGoogle();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('登出'),
                onTap: () async {
                  Navigator.pop(context);
                  await signOut();
                },
              ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text("好友申請"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FriendsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text("好友列表"),
                onTap: () async {
                  Navigator.pop(context);
                  final selectedUid = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FriendsListPage()),
                  );
                  if (selectedUid != null) {
                    _moveToFriend(selectedUid);
                  }
                }
            ),
            ListTile(
              leading: const Icon(Icons.bookmark),
              title: const Text('收藏地點'),
              onTap: () async {
                Navigator.pop(context);

                final LatLng? result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FavoritesPage()),
                );

                if (result != null) {
                  _moveToFavorite(result);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text('歷史路線'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RoutesPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: const Text("位置分享設定"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LocationPrivacyPage(),
                  ),
                );
              },
            ),
            if (user != null)
              SwitchListTile(
                secondary: const Icon(Icons.share_location),
                title: const Text('分享我的位置給好友'),
                value: shareLocation,
                onChanged: (value) {
                  setState(() {
                    shareLocation = value;
                  });
                  updateShareLocation(value);
                },
              ),
            if (user != null)
              SwitchListTile(
                secondary: const Icon(Icons.star),
                title: const Text('收藏地點模式'),
                value: favoriteMode,
                onChanged: (value) {
                  setState(() {
                    favoriteMode = value;
                  });
                },
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 1. 地圖層 (保持不變)
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: currentPosition ?? LatLng(23.0169, 120.2324),
              initialZoom: 16,
              onTap: (tapPosition, point) {
                if (!favoriteMode) {
                  // 收藏模式「關閉」→ 保持原本功能
                  _setDestination(point);
                }
              },
              onLongPress: (tapPosition, point) {
                if (favoriteMode) {
                  _showAddFavoriteDialog(point); // ⭐⭐ 這行是關鍵
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.breadcrumbs',
              ),
              if (pathPoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: pathPoints, color: isRecording ? Colors.orange : Colors.blue, strokeWidth: 4),
                  ],
                ),
              if (currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
              if (destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: destination!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.flag, color: Colors.green, size: 40),
                    ),
                  ],
                ),
              if (user != null)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('locations')
                      .where('shareLocation', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();

                    final List<Marker> markers = [];

                    for (final doc in snapshot.data!.docs) {
                      final uid = doc.id;

                      // 1️⃣ 必須是好友
                      if (!friendUids.contains(uid)) continue;

                      final friendData = allUsers[uid];
                      if (friendData == null) continue;

                      // 2️⃣ 對方有分享給我
                      final List friendShareTo =
                      List<String>.from(friendData['shareTo'] ?? []);
                      if (!friendShareTo.contains(user!.uid)) continue;

                      // 3️⃣ 我沒有隱藏他
                      if (hideFrom.contains(uid)) continue;

                      final data = doc.data() as Map<String, dynamic>;
                      final lat = data['lat'];
                      final lng = data['lng'];

                      final iconUrl = friendData['photoURL'];
                      final name = friendData['name'] ?? '好友';

                      markers.add(
                        Marker(
                          width: 35,
                          height: 35,
                          point: LatLng(lat, lng),
                          child: GestureDetector(
                            onTap: () => _showFriendDialog(name, iconUrl),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: iconUrl != null
                                    ? Image.network(iconUrl, fit: BoxFit.cover)
                                    : const Icon(Icons.person, size: 28),
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return MarkerLayer(markers: markers);
                  },
                ),
              if (user != null)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('favorites')
                      .where('uid', isEqualTo: user!.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();

                    return MarkerLayer(
                      markers: snapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;

                        return Marker(
                          width: 40,
                          height: 40,
                          point: LatLng(data['lat'], data['lng']),
                          child: GestureDetector(
                            onTap: () => _showFavoriteDetail(doc.id, data),
                            child: const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 40,
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ],
          ),

          // 2. 獨立的「開始/停止記錄」按鈕 (定位到左下角)
          // ⚠️ 注意：這個 Positioned Widget 必須在 Stack 的 children 列表內！
          Positioned(
            bottom: 140, // 距離底部
            left: 20,    // 距離左側 20
            child: FloatingActionButton.extended(
              heroTag: "btn_record",
              onPressed: _toggleRecording,
              label: Text(isRecording ? '停止記錄 (ON)' : '開始記錄 (OFF)',
                  style: const TextStyle(fontWeight: FontWeight.bold)
              ),
              icon: Icon(isRecording ? Icons.stop : Icons.play_arrow),
              backgroundColor: isRecording ? Colors.red : Colors.green, // 顏色切換
              foregroundColor: Colors.white,
            ),
          ),
        ], // Stack 的 children 結束
      ), // body 結束

      // 3. 右下角的操作按鈕 (回到位置、清除路線)
      // 保持在 Scaffold 的 floatingActionButton 屬性中，位於右下角
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end, // 確保右對齊
        children: [
          // 回到最新位置
          FloatingActionButton(
            heroTag: "btn_goto",
            onPressed: _goToCurrentPosition,
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.location_searching),
          ),
          const SizedBox(height: 10),

          // 清除路線
          FloatingActionButton(
            heroTag: "btn_clear",
            onPressed: _clearRoute,
            backgroundColor: Colors.white,
            foregroundColor: Colors.red,
            child: const Icon(Icons.delete),
          ),
          const SizedBox(height: 10), // 增加底部間距

          // 取得目前位置（不記錄）
          FloatingActionButton(
            heroTag: "btn_get_location",
            onPressed: _getCurrentLocationOnce,
            backgroundColor: Colors.white,
            foregroundColor: Colors.orange,
            child: const Icon(Icons.navigation),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}