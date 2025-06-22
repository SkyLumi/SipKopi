import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  final String? deviceId;
  
  const HistoryScreen({super.key, this.deviceId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final supabase = Supabase.instance.client;
  String selectedPeriod = 'today';
  List<Map<String, dynamic>> stats = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchStats();
  }

  Future<void> fetchStats() async {
    setState(() => isLoading = true);
    try {
      final now = DateTime.now();
      DateTime startDate;
      
      switch (selectedPeriod) {
        case 'week':
          startDate = now.subtract(Duration(days: 7));
          break;
        case 'month':
          startDate = now.subtract(Duration(days: 30));
          break;
        default: // today
          startDate = DateTime(now.year, now.month, now.day);
      }

      final response = await supabase
          .from('iot_data_logs')
          .select('kelembaban, penyiraman, waktu')
          .eq('id_iot', widget.deviceId ?? '')
          .gte('waktu', startDate.toIso8601String())
          .order('waktu', ascending: true);

      setState(() {
        stats = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading statistics: $e')),
      );
    }
  }

  List<FlSpot> getChartData() {
    return stats.asMap().entries.map((entry) {
      final index = entry.key.toDouble();
      final moisture = entry.value['kelembaban'] as int;
      return FlSpot(index, moisture.toDouble());
    }).toList();
  }

  Map<String, dynamic> calculateStats() {
    if (stats.isEmpty) return {
      'avgMoisture': 0,
      'minMoisture': 0,
      'maxMoisture': 0,
      'wateringCount': 0,
    };

    final moistureValues = stats.map((s) => s['kelembaban'] as int).toList();
    final wateringCount = stats.where((s) => s['penyiraman'] == true).length;

    return {
      'avgMoisture': moistureValues.reduce((a, b) => a + b) / moistureValues.length,
      'minMoisture': moistureValues.reduce((a, b) => a < b ? a : b),
      'maxMoisture': moistureValues.reduce((a, b) => a > b ? a : b),
      'wateringCount': wateringCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    final statsData = calculateStats();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Statistik Detail'),
        backgroundColor: Color(0xFF6B4E3D),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8C5A0),
              Color(0xFFF5E6D3),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Period selector
              Container(
                margin: EdgeInsets.all(16),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(26),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPeriodButton('Hari Ini', 'today'),
                    _buildPeriodButton('Minggu', 'week'),
                    _buildPeriodButton('Bulan', 'month'),
                  ],
                ),
              ),

              // Stats cards
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Rata-rata',
                        '${statsData['avgMoisture'].round()}%',
                        Icons.water_drop,
                        Colors.blue,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Min-Max',
                        '${statsData['minMoisture']}% - ${statsData['maxMoisture']}%',
                        Icons.show_chart,
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Watering count card
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _buildStatCard(
                  'Total Penyiraman',
                  '${statsData['wateringCount']} kali',
                  Icons.water,
                  Colors.green,
                ),
              ),

              SizedBox(height: 16),

              // Chart
              Expanded(
                child: Container(
                  margin: EdgeInsets.all(16),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(26),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: isLoading
                      ? Center(child: CircularProgressIndicator())
                      : LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 20,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.grey[300]!,
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 35,
                                  interval: 20,
                                  getTitlesWidget: (value, _) => Text(
                                    '${value.toInt()}%',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: stats.length > 10 ? stats.length / 5 : 1,
                                  getTitlesWidget: (value, _) {
                                    if (value >= 0 && value < stats.length) {
                                      final date = DateTime.parse(stats[value.toInt()]['waktu']);
                                      String timeFormat;
                                      if (selectedPeriod == 'today') {
                                        timeFormat = 'HH:mm';
                                      } else if (selectedPeriod == 'week') {
                                        timeFormat = 'E';
                                      } else {
                                        timeFormat = 'dd/MM';
                                      }
                                      return Text(
                                        DateFormat(timeFormat).format(date),
                                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                      );
                                    }
                                    return Text('');
                                  },
                                ),
                              ),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border(
                                left: BorderSide(color: Colors.grey[300]!),
                                bottom: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            minX: 0,
                            maxX: stats.length > 0 ? stats.length - 1 : 0,
                            minY: 0,
                            maxY: 100,
                            lineBarsData: [
                              LineChartBarData(
                                spots: getChartData(),
                                isCurved: true,
                                barWidth: 3,
                                color: Color(0xFF6B4E3D),
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: Color(0xFF6B4E3D),
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Color(0xFF6B4E3D).withAlpha(26),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String label, String period) {
    final isSelected = selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedPeriod = period;
        });
        fetchStats();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF6B4E3D) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Color(0xFF6B4E3D),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Color(0xFF2D2D2D),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
} 