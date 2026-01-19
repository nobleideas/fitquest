import 'package:flutter/material.dart';
import 'home_page.dart';
import 'equipment_list_page.dart';
import 'profile_page.dart';
import '../services/push_token_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();

  // ✅ Equipment key
  final GlobalKey<EquipmentListPageState> _equipmentKey =
      GlobalKey<EquipmentListPageState>();

  final GlobalKey<ProfilePageState> _profileKey = GlobalKey<ProfilePageState>();

  late final List<Widget> _pages = [
    HomePage(key: _homeKey),
    EquipmentListPage(key: _equipmentKey),
    ProfilePage(key: _profileKey),
  ];

  @override
  void initState() {
    super.initState();

    // ✅ register push token once when the app shell starts
    PushTokenService.instance.initAndRegister();
  }

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
    if (i == 1) {
      _equipmentKey.currentState?.refresh();
    }
    if (i == 2) {
      _profileKey.currentState?.refresh();
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
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center),
            label: 'Equipment',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
