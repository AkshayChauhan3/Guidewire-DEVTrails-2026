// ============================================================
// home_screen.dart
// ============================================================
// Main screen with the big "I'm Working" button.
//
// FLOW:
//   1. User taps "I'm Working"
//      → App asks for selfie (camera opens)
//      → App gets current GPS location
//      → Sends to Django → POST /api/session/start/
//      → Button turns red → Session running
//
//   2. During session (random 1–2 times):
//      → Timer fires randomly
//      → Popup appears asking for selfie + location
//      → Sends to Django → POST /api/session/check/
//
//   3. User taps "End Session"
//      → App asks for selfie again
//      → Gets final location
//      → Sends to Django → POST /api/session/end/
//      → Session saved ✅
//
// BACKEND CONNECTIONS (all via ApiService):
//   startSession()       → POST /api/session/start/
//   submitRandomCheck()  → POST /api/session/check/
//   endSession()         → POST /api/session/end/
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'app_state.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool isWorking = false;
  bool isLoading = false;
  Timer? _randomCheckTimer;
  Duration sessionDuration = Duration.zero;
  Timer? _clockTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the big button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _randomCheckTimer?.cancel();
    _clockTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  // 📍 Get GPS location
  // Requires geolocator package in pubspec.yaml
  // Also add permissions in AndroidManifest.xml:
  //   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  // ──────────────────────────────────────────────
  Future<Position?> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack("Please enable location services");
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnack("Location permission denied");
        return null;
      }
    }

    return await Geolocator.getCurrentPosition();
  }

  // ──────────────────────────────────────────────
  // 📸 Open camera for selfie
  // ──────────────────────────────────────────────
  Future<String?> _takeSelfie() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front, // Front camera for selfie
    );
    return photo?.path;
  }

  // ──────────────────────────────────────────────
  // 🟢 START SESSION
  // Called when user taps the big button (not working state)
  // ──────────────────────────────────────────────
  Future<void> _startSession() async {
    setState(() => isLoading = true);

    // Step 1: Take selfie
    final selfiePath = await _takeSelfie();
    if (selfiePath == null) {
      setState(() => isLoading = false);
      _showSnack("Selfie required to start session");
      return;
    }

    // Step 2: Get location
    final position = await _getLocation();
    if (position == null) {
      setState(() => isLoading = false);
      return;
    }

    // Step 3: Send to Django
    // 🔗 API CALL → POST /api/session/start/
    final result = await ApiService.startSession(
      phone: AppState.phone,
      latitude: position.latitude,
      longitude: position.longitude,
      selfiePath: selfiePath,
    );

    setState(() => isLoading = false);

    if (result["success"]) {
      // ✅ Save session ID globally
      AppState.sessionId = result["session_id"]?.toString() ?? "demo_session";
      AppState.isWorking = true;
      AppState.sessionStartTime = DateTime.now();

      setState(() => isWorking = true);

      // Start the session clock
      _startClock();

      // Schedule random checks (1–2 times during session)
      _scheduleRandomChecks();

      _showSnack("Session started! Stay safe 🚀");
    } else {
      // For demo: start anyway even if backend not ready
      AppState.isWorking = true;
      AppState.sessionId = "demo_session_${DateTime.now().millisecondsSinceEpoch}";
      AppState.sessionStartTime = DateTime.now();
      setState(() => isWorking = true);
      _startClock();
      _scheduleRandomChecks();
      _showSnack("Session started! (Demo mode)");
    }
  }

  // ──────────────────────────────────────────────
  // 🔴 END SESSION
  // Called when user taps the big button (working state)
  // ──────────────────────────────────────────────
  Future<void> _endSession() async {
    // Confirm first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("End Session?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This will end your work session.\nMake sure you're at your last delivery location.",
          style: TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("End Session", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => isLoading = true);

    // Step 1: Take end selfie
    final selfiePath = await _takeSelfie();
    if (selfiePath == null) {
      setState(() => isLoading = false);
      _showSnack("Selfie required to end session");
      return;
    }

    // Step 2: Get final location
    final position = await _getLocation();
    if (position == null) {
      setState(() => isLoading = false);
      return;
    }

    // Step 3: Send to Django
    // 🔗 API CALL → POST /api/session/end/
    await ApiService.endSession(
      sessionId: AppState.sessionId,
      latitude: position.latitude,
      longitude: position.longitude,
      selfiePath: selfiePath,
    );

    // Cancel all timers
    _randomCheckTimer?.cancel();
    _clockTimer?.cancel();

    AppState.isWorking = false;
    AppState.sessionId = "";

    setState(() {
      isWorking = false;
      isLoading = false;
      sessionDuration = Duration.zero;
    });

    _showSnack("Great work today! Session saved ✅");
  }

  // ──────────────────────────────────────────────
  // ⏱️ Session Clock
  // ──────────────────────────────────────────────
  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (AppState.sessionStartTime != null) {
        setState(() {
          sessionDuration = DateTime.now().difference(AppState.sessionStartTime!);
        });
      }
    });
  }

  // ──────────────────────────────────────────────
  // 🎲 Schedule random checks during session
  // Fires 1–2 random popups during working hours
  // ──────────────────────────────────────────────
  void _scheduleRandomChecks() {
    final random = Random();
    // Random delay between 10–30 minutes (in seconds)
    // For demo: use 30–60 seconds so you can test quickly
    final delaySeconds = random.nextInt(30) + 30; // Change to 600+1800 for production

    _randomCheckTimer = Timer(Duration(seconds: delaySeconds), () {
      if (isWorking && mounted) {
        _showRandomCheckPopup();
      }
    });
  }

  // ──────────────────────────────────────────────
  // 📸 Random Check Popup
  // Shows during session at random intervals
  // ──────────────────────────────────────────────
  Future<void> _showRandomCheckPopup() async {
    showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss — must complete check
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text("📸 ", style: TextStyle(fontSize: 24)),
            Text("Quick Check!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "GigShield needs to verify you're working.\nTake a selfie to continue your session.",
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // Close dialog first
                await _handleRandomCheck();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Take Selfie Now", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Handle the actual random check submission
  // ──────────────────────────────────────────────
  Future<void> _handleRandomCheck() async {
    final selfiePath = await _takeSelfie();
    if (selfiePath == null) return;

    final position = await _getLocation();
    if (position == null) return;

    // 🔗 API CALL → POST /api/session/check/
    await ApiService.submitRandomCheck(
      sessionId: AppState.sessionId,
      latitude: position.latitude,
      longitude: position.longitude,
      selfiePath: selfiePath,
    );

    if (mounted) _showSnack("Check complete ✅ Keep delivering!");

    // Schedule next random check
    _scheduleRandomChecks();
  }

  // ──────────────────────────────────────────────
  // Format session duration as HH:MM:SS
  // ──────────────────────────────────────────────
  String get _formattedDuration {
    final h = sessionDuration.inHours.toString().padLeft(2, '0');
    final m = (sessionDuration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (sessionDuration.inSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2A2A2A)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "GigShield",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          // ── Profile Button ──
          // Tapping opens ProfileScreen (full page)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.person, color: Colors.white70, size: 20),
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          // ── Greeting ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Row(
              children: [
                Text(
                  "Hey, ${AppState.fullName.split(' ').first} 👋",
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),

          // ── Session Timer (visible only when working) ──
          if (isWorking)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 10),
                      SizedBox(width: 8),
                      Text("Session Active", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(
                    _formattedDuration,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // ── Big Working Button (CENTER) ──
          Expanded(
            child: Center(
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : ScaleTransition(
                      scale: isWorking ? const AlwaysStoppedAnimation(1.0) : _pulseAnimation,
                      child: GestureDetector(
                        onTap: isWorking ? _endSession : _startSession,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isWorking
                                ? Colors.red.shade900.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                            border: Border.all(
                              color: isWorking ? Colors.redAccent : Colors.white54,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isWorking
                                    ? Colors.red.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.15),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isWorking ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                                color: isWorking ? Colors.redAccent : Colors.white,
                                size: 60,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isWorking ? "End\nSession" : "I'm Working\nNow",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isWorking ? Colors.redAccent : Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // ── Status Text ──
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Text(
              isWorking
                  ? "Tap to end your session"
                  : "Tap to start your work session",
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}