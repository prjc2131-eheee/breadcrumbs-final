import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// 取得當前位置 (單次)，回傳 LatLng，如果失敗回傳 null
  static Future<LatLng?> getCurrentLocation({bool simulate = false}) async {
    if (simulate) {
      // 模擬位置
      return LatLng(23.0169109, 120.2324343);
    }

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('⚠️ LocationService 取得單次位置失敗: $e');
      return null;
    }
  }

  /// 取得位置更新的 Stream (持續定位)
  /// 這是供 HomePage 訂閱以實現持續追蹤的核心方法。
  static Stream<LatLng> getPositionStream({bool simulate = false}) {
    if (simulate) {
      // 模擬位置 Stream：每 5 秒發送一個點，模擬緩慢移動
      // 實際專案中，您可能會使用更複雜的模擬路徑
      return Stream.periodic(const Duration(seconds: 5), (count) {
        // 模擬從起始點 (23.0169, 120.2324) 往東北方緩慢移動
        double lat = 23.0169 + (count * 0.0001);
        double lng = 120.2324 + (count * 0.0001);
        return LatLng(lat, lng);
      }).asBroadcastStream(); // 確保可以被訂閱多次 (如果需要)
    }

    // 1. 檢查權限
    Future<void> _checkAndRequestPermission() async {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // 權限仍被拒絕，拋出錯誤
          throw Exception("Location permission denied.");
        }
      }
    }

    // 2. 使用 Stream.fromFuture 確保權限檢查先執行
    return Stream.fromFuture(_checkAndRequestPermission()).asyncExpand((_) {
      // 3. 實時取得位置 Stream
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation, // 導航級別的精度
          distanceFilter: 5, // 最小距離變動（公尺）才觸發更新
        ),
      ).map((Position position) {
        // 將 Geolocator 的 Position 轉換為 LatLng 供 App 使用
        return LatLng(position.latitude, position.longitude);
      }).handleError((e) {
        print('⚠️ LocationService 實時位置 Stream 錯誤: $e');
        throw e; // 拋出錯誤供訂閱者處理
      });
    });
  }
}