import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../utils.dart';
import 'session_page.dart';

class CalendarPage extends StatefulWidget {
  final Store store;
  const CalendarPage({super.key, required this.store});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _month = DateTime.now();

  void _move(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  Widget _cell(BuildContext context, int day, String todayStr) {
    final dKey = dateKey(DateTime(_month.year, _month.month, day));
    final session = widget.store.sessions.firstWhere(
      (s) => s.date == dKey,
      orElse: () => Session(dKey, []),
    );
    final hasData = session.exercises.isNotEmpty;
    final isToday = dKey == todayStr;

    Color bg = Colors.transparent;
    if (hasData) {
      bg = session.isFinished
          ? Colors.green.withOpacity(0.35)
          : Colors.redAccent.withOpacity(0.35);
    }

    return GestureDetector(
      onTap: hasData
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        SessionPage(store: widget.store, session: session)),
              )
          : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: Colors.tealAccent, width: 1.5)
              : Border.all(color: Colors.white10, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$day',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: isToday ? Colors.tealAccent : Colors.white,
                )),
            if (session.summaryText.isNotEmpty) ...[
              const Spacer(),
              Text(session.summaryText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 9, color: Colors.white70, height: 1.1)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
    final todayStr = dateKey(DateTime.now());

    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('${_month.year}년 ${_month.month}월'),
          actions: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _move(-1)),
            IconButton(
                icon: const Icon(Icons.today),
                onPressed: () => setState(() => _month = DateTime.now())),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _move(1)),
          ],
        ),
        body: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              Text('일', style: TextStyle(color: Colors.red, fontSize: 12)),
              Text('월', style: TextStyle(fontSize: 12)),
              Text('화', style: TextStyle(fontSize: 12)),
              Text('수', style: TextStyle(fontSize: 12)),
              Text('목', style: TextStyle(fontSize: 12)),
              Text('금', style: TextStyle(fontSize: 12)),
              Text('토', style: TextStyle(color: Colors.blue, fontSize: 12)),
            ],
          ),
          const Divider(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 0.8),
              itemCount: firstWeekday + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstWeekday) return const SizedBox.shrink();
                return _cell(context, index - firstWeekday + 1, todayStr);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
