import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class ScanQRScreen extends StatefulWidget {
  final String email; 
  final String nama;
  final String password;

  const ScanQRScreen({super.key, required this.email, required this.nama, required this.password });

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool isScanned = false;

  final SupabaseClient supabase = Supabase.instance.client;

  void _showError(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
    ),
  );
  setState(() => isScanned = false);
  }


  void _handleBarcode(BarcodeCapture capture) async {
    if (isScanned) return;

    final barcodes = capture.barcodes;
    final deviceId = barcodes.isNotEmpty ? barcodes.first.rawValue : null;

    if (deviceId == null) return;

    setState(() => isScanned = true);

    try {
      // Sign up user via Supabase Auth
      final response = await Supabase.instance.client.auth.signUp(
        email: widget.email,
        password: widget.password,
      );

      final user = response.user;
      if (user == null) {
        throw AuthException('Registrasi gagal: user null');
      }

      // Insert user ke table `users`
      await Supabase.instance.client.from('users').insert({
        'id': user.id,
        'email': widget.email,
        'nama': widget.nama,
      });

      await Supabase.instance.client.from('iot_user_link').insert({
        'id_user': user.id,
        'id_iot': deviceId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registrasi dan Scan QR berhasil!'),
          backgroundColor: Colors.green,
        ),
      );

      // Delay lalu redirect ke login
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pushReplacementNamed(context, '/login');

    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Terjadi kesalahan: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _handleBarcode,
            ),

            if (isScanned)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.green),
                      SizedBox(height: 12),
                      Text(
                        'Memproses QR...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            const Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Arahkan kamera ke QR Code',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
