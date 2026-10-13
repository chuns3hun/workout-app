import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

Widget lineChart(List<double> ys) {
  if (ys.length < 2) {
    return const SizedBox(
        height: 100,
        child: Center(
            child: Text('기록 2개 이상부터 그래프 표시',
                style: TextStyle(color: Colors.grey, fontSize: 12))));
  }

  final minY = ys.reduce((a, b) => a < b ? a : b);
  final maxY = ys.reduce((a, b) => a > b ? a : b);
  final margin = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.1;

  return SizedBox(
    height: 160,
    child: Padding(
      padding: const EdgeInsets.only(right: 16, top: 16, left: 8, bottom: 8),
      child: LineChart(
        LineChartData(
          minY: minY - margin,
          maxY: maxY + margin,
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white12, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) =>
                FlLine(color: Colors.white12, strokeWidth: 0.5),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])
              ],
              isCurved: true,
              color: Colors.tealAccent,
              barWidth: 2,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.tealAccent.withOpacity(0.08),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
