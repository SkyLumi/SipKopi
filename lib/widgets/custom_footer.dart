import 'package:flutter/material.dart';

class CustomFooter extends StatelessWidget {
  const CustomFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final String? currentRoute = ModalRoute.of(context)?.settings.name;

    return BottomAppBar(
      shape: CircularNotchedRectangle(),
      notchMargin: 8,
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              Icons.home,
              color: currentRoute == '/home' ? Colors.purple : Colors.grey,
              size: 40
            ),
            onPressed: () {
              if (currentRoute != '/home') {
                Navigator.pushNamed(context, '/home');
              }
            },
          ),
          SizedBox(width: 44), // Spacer buat FAB
          IconButton(
            icon: Icon(
              Icons.person,
              color: currentRoute == '/profile' ? Colors.purple : Colors.grey,
              size: 40
            ),
            onPressed: () {
              if (currentRoute != '/profile') {
                Navigator.pushNamed(context, '/profile');
              }
            },
          ),
        ],
      ),
    );
  }
}
