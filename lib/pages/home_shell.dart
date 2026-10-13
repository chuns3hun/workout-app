import 'package:flutter/material.dart';
import '../store.dart';
import 'calendar_page.dart';
import 'more_page.dart';
import 'session_page.dart';
import 'stats_page.dart';

/// 하단 탭: 오늘 / 달력 / 통계 / 더보기
class HomeShell extends StatefulWidget {
  final Store store;
  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: [
          SessionPage(store: st),
          CalendarPage(store: st),
          StatsPage(store: st),
          MorePage(store: st),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center), label: '오늘'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '달력'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '통계'),
          NavigationDestination(icon: Icon(Icons.menu), label: '더보기'),
        ],
      ),
    );
  }
}