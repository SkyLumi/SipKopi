import 'package:flutter/material.dart';
import 'package:sipkopi/screens/verifikasi_screen.dart';

class ForgotPasswordScreen extends StatelessWidget {
  final _emailController = TextEditingController();
  final Color coffeeColor = Color(0xFFA97C68);

  ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lupa Password'),
        backgroundColor: coffeeColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan email kamu\ndan kami akan bantu reset password-mu.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: 'Email',
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final input = _emailController.text;
                if (input.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Mohon masukkan data terlebih dahulu')),
                  );
                } else {
                  // Logika untuk reset password bisa ditambahkan di sini
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Permintaan reset password dikirim')),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const VerifikasiScreen()),
                    );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: coffeeColor,
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Kirim Permintaan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
