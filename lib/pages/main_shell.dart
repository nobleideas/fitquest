import 'package:flutter/material.dart';
import 'home_page.dart';
import 'equipment_list_page.dart';
import 'profile_page.dart';
import '../services/push_token_service.dart';
import '../theme/fitquest_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushTokenService.instance.initAndRegister();
    });
  }

  String get _title {
    switch (_index) {
      case 0:
        return 'Fit Quest';
      case 1:
        return 'Equipment/Routines';
      case 2:
        return 'My Profile';
      default:
        return 'Fit Quest';
    }
  }

  void _onTap(int i) {
    if (i == 0) _homeKey.currentState?.refresh();
    if (i == 1) _equipmentKey.currentState?.refresh();
    if (i == 2) _profileKey.currentState?.refresh();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: FitQuestTheme.dark,
      child: Scaffold(
        backgroundColor: FitQuestTheme.background,
        appBar: AppBar(
          backgroundColor: FitQuestTheme.background,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: FitQuestTheme.outline),
          ),
        ),
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: FitQuestTheme.surface,
            border: Border(top: BorderSide(color: FitQuestTheme.outline)),
          ),
          child: BottomNavigationBar(
            backgroundColor: FitQuestTheme.surface,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            currentIndex: _index,
            onTap: _onTap,
            selectedItemColor: FitQuestTheme.accent,
            unselectedItemColor: FitQuestTheme.muted,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                icon: Icon(Icons.fitness_center),
                label: 'Equipment',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
