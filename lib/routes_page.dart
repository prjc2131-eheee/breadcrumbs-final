import 'package:flutter/material.dart';
import 'route_history_page.dart';
import 'shared_routes_page.dart';

class RoutesPage extends StatelessWidget {
  const RoutesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('歷史路線'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '我的路線'),
              Tab(text: '收到分享'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            RouteHistoryPage(),   // 你原本的
            SharedRoutesPage(),   // 新的
          ],
        ),
      ),
    );
  }
}