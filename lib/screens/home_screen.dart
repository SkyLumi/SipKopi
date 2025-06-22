import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/custom_footer.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String soilMoisture = '0%';
  String statusPenyiraman = 'OFF';
  bool penyiramanManual = false;
  int batasKelembaban = 30;
  String? currentUserId;
  String? currentDeviceId;
  int wateringCount = 0;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final supabase = Supabase.instance.client;

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _animationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    getCurrentUser();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void showSnackbar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  Future<void> getCurrentUser() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        currentUserId = user.id;
        await getUserDevice();
        await fetchMoisture();
        await fetchSettings();

        if (currentDeviceId != null) {
          setupRealtimeSubscription();
        }
      } else {
        showSnackbar('User tidak ditemukan. Silakan login terlebih dahulu.');
      }
    } catch (e) {
      showSnackbar('Error saat mendapatkan user: $e');
    }
  }

  Future<void> getUserDevice() async {
    try {
      // Get user device from iot_user_link table
      final response = await supabase
          .from('iot_user_link')
          .select('id_iot')
          .eq('id_user', currentUserId!)
          .single();
      
      currentDeviceId = response['id_iot'];
    } catch (e) {
      showSnackbar('Error saat mendapatkan device: $e');
    }
  }

  Future<void> fetchMoisture() async {
    if (currentDeviceId == null) return;
    
    try {
      final response = await supabase
          .from('iot_datas')
          .select('kelembaban')
          .eq('id_iot', currentDeviceId!)
          .order('waktu', ascending: false)
          .limit(1)
          .single();

      final int moistureValue = response['kelembaban'] as int;
      setState(() {
        soilMoisture = '$moistureValue%';
      });
    } catch (e) {
      showSnackbar('Error saat fetch data kelembaban: $e');
    }
  }

  Future<void> fetchSettings() async {
    if (currentDeviceId == null) return;
    
    try {
      final response = await supabase
          .from('iot_setting')
          .select('batas_kelembaban, status_penyiraman, penyiraman_manual')
          .eq('id_iot', currentDeviceId!)
          .single();

      setState(() {
        batasKelembaban = response['batas_kelembaban'] as int;
        statusPenyiraman = response['status_penyiraman'] ? 'ON' : 'OFF';
        penyiramanManual = response['penyiraman_manual'] as bool? ?? false;
      });
    } catch (e) {
      showSnackbar('Error saat fetch setting: $e');
    }
  }

  Future<void> fetchAllData() async {
    if (currentDeviceId == null) return;
    
    try {
      // Get today's date at midnight
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Fetch all required data
      final responses = await Future.wait<dynamic>([
        supabase
            .from('iot_datas')
            .select('kelembaban')
            .eq('id_iot', currentDeviceId!)
            .single(),
        supabase
            .from('iot_setting')
            .select('batas_kelembaban, status_penyiraman')
            .eq('id_iot', currentDeviceId!)
            .single(),
        supabase
            .from('iot_data_logs')
            .select('penyiraman')
            .eq('id_iot', currentDeviceId!)
            .eq('penyiraman', true)
            .gte('waktu', today.toIso8601String()),
      ]);

      final dataResponse = responses[0];
      final settingResponse = responses[1];
      final wateringResponse = responses[2];

      setState(() {
        // Update moisture
        final int moistureValue = dataResponse['kelembaban'] as int;
        soilMoisture = '$moistureValue%';
        
        // Update settings
        batasKelembaban = settingResponse['batas_kelembaban'] as int;
        statusPenyiraman = settingResponse['status_penyiraman'] ? 'ON' : 'OFF';
        
        // Update watering count
        wateringCount = (wateringResponse as List).length;
      });
    } catch (e) {
      showSnackbar('Error saat fetch data: $e');
    }
  }

  Future<void> updateSetting() async {
    if (currentDeviceId == null) return;
    
    try {
      await supabase
          .from('iot_setting')
          .update({
            'batas_kelembaban': batasKelembaban,
            'status_penyiraman': statusPenyiraman == 'ON',
            'penyiraman_manual': penyiramanManual,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id_iot', currentDeviceId!);

      showSnackbar('Berhasil memperbarui pengaturan!', isError: false);
      await fetchSettings();
    } catch (e) {
      showSnackbar('Error saat update setting: $e');
    }
  }

  Future<void> updateData(int kelembaban, bool penyiraman) async {
    if (currentDeviceId == null) return;
    
    try {
      await supabase.from('iot_datas').update({
        'kelembaban': kelembaban,
        'penyiraman': penyiraman,
        'waktu': DateTime.now().toIso8601String(),
      }).eq('id_iot', currentDeviceId!);
    } catch (e) {
      showSnackbar('Error saat update data: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getHistoryData({int limit = 10}) async {
    if (currentDeviceId == null) return [];
    
    try {
      final response = await supabase
          .from('iot_data_logs')
          .select('kelembaban, penyiraman, waktu')
          .eq('id_iot', currentDeviceId!)
          .order('waktu', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      showSnackbar('Error saat fetch history: $e');
      return [];
    }
  }

  Future<List<FlSpot>> getChartData() async {
    if (currentDeviceId == null) return [];
    
    try {
      // Get data for the last 24 hours
      final now = DateTime.now();
      final yesterday = now.subtract(Duration(hours: 24));
      
      final response = await supabase
          .from('iot_data_logs')
          .select('kelembaban, waktu')
          .eq('id_iot', currentDeviceId!)
          .gte('waktu', yesterday.toIso8601String())
          .order('waktu', ascending: true);

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(response);
      
      return data.asMap().entries.map((entry) {
        final index = entry.key.toDouble();
        final moisture = entry.value['kelembaban'] as int;
        return FlSpot(index, moisture.toDouble());
      }).toList();
    } catch (e) {
      showSnackbar('Error saat fetch chart data: $e');
      return [];
    }
  }

  Future<void> toggleManualWatering() async {
    if (currentDeviceId == null) return;
    
    try {
      final newStatus = !penyiramanManual;
      
      await supabase
          .from('iot_setting')
          .update({
            'penyiraman_manual': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id_iot', currentDeviceId!);

      setState(() {
        penyiramanManual = newStatus;
      });

      showSnackbar(
        newStatus ? 'Penyiraman manual dimulai!' : 'Penyiraman manual dihentikan!', 
        isError: false
      );
    } catch (e) {
      showSnackbar('Error saat mengubah penyiraman manual: $e');
    }
  }

  void setupRealtimeSubscription() {
    _realtimeChannel = supabase
        .channel('iot_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'iot_datas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id_iot',
            value: currentDeviceId!,
          ),
          callback: (payload) {
            // Update kelembaban secara realtime
            final newData = payload.newRecord;
            if (newData['kelembaban'] != null) {
              final int moistureValue = newData['kelembaban'] as int;
              
              setState(() {
                soilMoisture = '$moistureValue%';
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'iot_setting',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id_iot',
            value: currentDeviceId!,
          ),
          callback: (payload) {
            // Update setting secara realtime jika ada perubahan dari device lain
            final newData = payload.newRecord;
            setState(() {
              if (newData['batas_kelembaban'] != null) {
                batasKelembaban = newData['batas_kelembaban'] as int;
              }
              if (newData['status_penyiraman'] != null) {
                statusPenyiraman = newData['status_penyiraman'] ? 'ON' : 'OFF';
              }
              if (newData['penyiraman_manual'] != null) {
                penyiramanManual = newData['penyiraman_manual'] as bool;
              } 
            });
          },
        )
        .subscribe();
  }

  Color getMoistureColor() {
    final moisture = double.tryParse(soilMoisture.replaceAll('%', '')) ?? 0;
    if (moisture < 20) return Colors.red;
    if (moisture < 40) return Colors.orange;
    if (moisture < 60) return Colors.amber;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    String today = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now());
    final moisture = double.tryParse(soilMoisture.replaceAll('%', '')) ?? 0;

    return Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: toggleManualWatering, // Ganti ke toggle function
      backgroundColor: penyiramanManual ? Colors.red : const Color(0xFF6B4E3D),
      icon: Icon(
        penyiramanManual ? Icons.stop : Icons.water_drop, 
        color: Colors.white
      ),
      label: Text(
        penyiramanManual ? 'Berhenti Siram' : 'Mulai Siram', 
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)
      ),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: CustomFooter(),
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: ListView(
                padding: EdgeInsets.all(20),
                children: [
                  // Header with date
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(230),
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
                      children: [
                        Icon(Icons.calendar_today, color: Color(0xFF6B4E3D), size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            today,
                            style: TextStyle(
                              color: Color(0xFF6B4E3D),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Main moisture display
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF8B5A3C),
                          Color(0xFF6B4E3D),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(51),
                          blurRadius: 15,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.opacity, color: Colors.white, size: 28),
                            SizedBox(width: 12),
                            Text(
                              'Kelembaban Tanah',
                              style: TextStyle(
                                color: Colors.white.withAlpha(230),
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        
                        SizedBox(height: 20),
                        
                        // Circular progress indicator
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 150,
                              height: 150,
                              child: CircularProgressIndicator(
                                value: moisture / 100,
                                strokeWidth: 12,
                                backgroundColor: Colors.white.withAlpha(77),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  getMoistureColor(),
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  soilMoisture,
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  moisture < batasKelembaban ? 'Kering' : 'Optimal',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(204),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        SizedBox(height: 20),
                        
                        Text(
                          "Target kelembaban untuk kebun kopi adalah ${batasKelembaban.round()}%",
                          style: TextStyle(
                            color: Colors.white.withAlpha(230),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Auto watering toggle
                  Container(
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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setState(() {
                            statusPenyiraman = statusPenyiraman == 'ON' ? 'OFF' : 'ON';
                          });
                          updateSetting();
                        },
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: statusPenyiraman == 'ON' 
                                      ? Colors.green.withAlpha(26)
                                      : Colors.red.withAlpha(26),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.water_drop,
                                  color: statusPenyiraman == 'ON' ? Colors.green : Colors.red,
                                  size: 24,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Penyiraman Otomatis',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2D2D2D),
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      statusPenyiraman == 'ON' ? 'Aktif' : 'Nonaktif',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: statusPenyiraman == 'ON',
                                onChanged: (value) {
                                  setState(() {
                                    statusPenyiraman = value ? 'ON' : 'OFF';
                                  });
                                  updateSetting();
                                },
                                activeColor: Colors.green,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Moisture threshold slider
                  Container(
                    padding: EdgeInsets.all(20),
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
                            Icon(Icons.tune, color: Color(0xFF6B4E3D), size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Batas Kelembaban',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D2D2D),
                              ),
                            ),
                          ],
                        ),
                        
                        SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Text(
                              'Kering',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Color(0xFF6B4E3D),
                                  inactiveTrackColor: Colors.grey[300],
                                  thumbColor: Color(0xFF6B4E3D),
                                  overlayColor: Color(0xFF6B4E3D).withAlpha(51),
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12),
                                  trackHeight: 4,
                                ),
                                child: Slider(
                                  value: batasKelembaban.toDouble(),
                                  min: 10,
                                  max: 90,
                                  divisions: 80,
                                  onChanged: (value) {
                                    setState(() {
                                      batasKelembaban = value.round();
                                    });
                                  },
                                  onChangeEnd: (value) {
                                    updateSetting();
                                  },
                                ),
                              ),
                            ),
                            Text(
                              'Lembab',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        
                        Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Color(0xFF6B4E3D).withAlpha(26),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${batasKelembaban.round()}%',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6B4E3D),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Statistics chart
                  Container(
                    height: 320,
                    padding: EdgeInsets.all(20),
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
                            Icon(Icons.analytics, color: Color(0xFF6B4E3D), size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Statistik Hari Ini',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D2D2D),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        Expanded(
                          child: FutureBuilder<List<FlSpot>>(
                            future: getChartData(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return Center(child: CircularProgressIndicator());
                              }
                              
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text('Error loading chart data'),
                                );
                              }

                              final spots = snapshot.data ?? [];
                              
                              return LineChart(
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
                                        interval: spots.length > 10 ? spots.length / 5 : 1,
                                        getTitlesWidget: (value, _) {
                                          if (value >= 0 && value < spots.length) {
                                            final date = DateTime.parse(spots[value.toInt()].x.toString());
                                            return Text(
                                              '${date.hour}:00',
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
                                  maxX: spots.length > 0 ? spots.length - 1 : 0,
                                  minY: 0,
                                  maxY: 100,
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: spots,
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
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Statistics cards
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 160,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.green[400]!, Colors.green[600]!],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withAlpha(77),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.water_drop, color: Colors.white, size: 24),
                              SizedBox(height: 8),
                              Text(
                                "Telah Disiram",
                                style: TextStyle(
                                  color: Colors.white.withAlpha(230),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Spacer(),
                              Text(
                                "$wateringCount",
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                "kali hari ini",
                                style: TextStyle(
                                  color: Colors.white.withAlpha(204),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HistoryScreen(
                                  deviceId: currentDeviceId,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            height: 160,
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
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.bar_chart, color: Color(0xFF6B4E3D), size: 24),
                                SizedBox(height: 8),
                                Text(
                                  "Statistik Lengkap",
                                  style: TextStyle(
                                    color: Color(0xFF2D2D2D),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Spacer(),
                                Row(
                                  children: [
                                    Text(
                                      "Lihat Detail",
                                      style: TextStyle(
                                        color: Color(0xFF6B4E3D),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      color: Color(0xFF6B4E3D),
                                      size: 12,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 100), // Space for floating action button
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}