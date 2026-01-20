import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RouteMapPage extends StatefulWidget {
  final Map<String, dynamic> routeData;

  const RouteMapPage({super.key, required this.routeData});

  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  final MapController mapController = MapController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final points = (widget.routeData['points'] as List)
          .map((p) => LatLng(p['lat'], p['lng']))
          .toList();

      if (points.isEmpty) return;

      final bounds = LatLngBounds.fromPoints(points);

      mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(140),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = (widget.routeData['points'] as List)
        .map((p) => LatLng(p['lat'], p['lng']))
        .toList();

    final int colorValue =
        (widget.routeData['color'] as int?) ?? Colors.blue.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routeData['name'] ?? '路線'),
      ),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: points.first,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 4,
                color: Color(colorValue),
              ),
            ],
          ),
        ],
      ),
    );
  }
}