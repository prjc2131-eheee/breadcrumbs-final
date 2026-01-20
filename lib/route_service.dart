import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RouteService {
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final route = data['routes'][0]['geometry']['coordinates'] as List;

      return route.map((coord) {
        final lon = coord[0] as double;
        final lat = coord[1] as double;
        return LatLng(lat, lon);
      }).toList();
    } else {
      throw Exception('OSRM 請求失敗: ${response.statusCode}');
    }
  }

  // =====================================================
  // 👣【B】實際走過的路（我們現在新增的）
  // =====================================================

  final List<LatLng> _recordedPoints = [];

  /// 加入一個實際定位點
  void addPoint(LatLng point) {
    _recordedPoints.add(point);
  }

  /// 清除目前紀錄
  void clear() {
    _recordedPoints.clear();
  }

  /// 儲存到 Firestore
  Future<void> saveRoute({
    required String uid,
    required String name,
    required int colorValue,
    required String userName,
    String? userPhoto,
  }) async {
    if (_recordedPoints.length < 2) return;

    await FirebaseFirestore.instance.collection('routes').add({
      'userId': uid,
      'userPhoto': userPhoto,
      'name': name.isEmpty ? '未命名路線' : name,
      'color': colorValue,
      'createdAt': Timestamp.now(),
      'points': _recordedPoints.map((p) => {
        'lat': p.latitude,
        'lng': p.longitude,
      }).toList(),
    });
  }
}