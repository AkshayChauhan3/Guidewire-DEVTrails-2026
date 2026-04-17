// ============================================================
// main_navigation.dart
// ============================================================
// Bottom navigation bar connecting all 4 screens:
//   Home | Premium | Alerts | Protection
//
// This is shown AFTER login.
// The HomeScreen handles its own AppBar with profile icon.
// ============================================================

import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'premium_screen.dart';
import 'data_screen.dart';
import 'claim_screen.dart';

import 'app_state.dart';
import 'ui_kit.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  // ── All 4 screens ──
  final List<Widget> _screens = const [
    HomeScreen(),
    PremiumScreen(),
    DataScreen(),
    ClaimScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        // IndexedStack keeps screens alive when switching tabs
        // So weather data doesn't reload every time you switch back
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.background,
            border: Border(
              top: BorderSide(color: AppUi.border),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
              AppState.mainTabNotifier.value = index;
            },
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppUi.text,
            unselectedItemColor: AppUi.text.withValues(alpha: 0.35),
            selectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: "Home",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.shield_outlined),
                activeIcon: Icon(Icons.shield),
                label: "Premium",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_outlined),
                activeIcon: Icon(Icons.bar_chart),
                label: "Alerts",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined),
                activeIcon: Icon(Icons.receipt_long),
                label: "Protect",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
