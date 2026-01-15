import 'package:flutter/material.dart';
import 'home_page.dart';
import 'equipment_list_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // ✅ Existing
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();

  // ✅ NEW: Profile key (must use the PUBLIC state type)
  final GlobalKey<ProfilePageState> _profileKey = GlobalKey<ProfilePageState>();

  late final List<Widget> _pages = [
    HomePage(key: _homeKey),
    const EquipmentListPage(),
    ProfilePage(key: _profileKey), // ✅ was const ProfilePage()
  ];

  String get _title {
    switch (_index) {
      case 0:
        return 'Fit Quest';
      case 1:
        return 'My Equipment';
      case 2:
        return 'My Profile';
      default:
        return 'Fit Quest';
    }
  }

  void _onTap(int i) {
    if (i == 0) {
      _homeKey.currentState?.refresh();
    }
    if (i == 2) {
      _profileKey.currentState?.refresh(); // ✅ refresh stats when Profile tab clicked
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Equipment'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
