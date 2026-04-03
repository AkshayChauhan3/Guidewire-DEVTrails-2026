import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'app_state.dart';

import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool isWorking = AppState.isWorking;
  bool needsHistoryUpload = AppState.needsHistoryUpload;
  bool isLoading = false;
  bool _randomCheckPending = false;

  Timer? _randomCheckTimer;
  Timer? _clockTimer;
  Duration sessionDuration = Duration.zero;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (AppState.isWorking) {
      _startClock();
      _scheduleBackendRandomCheck();
    }

    _ensurePartnerLoaded();
  }

  @override
  void dispose() {
    _randomCheckTimer?.cancel();
    _clockTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<Position?> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final permissionGranted = await _ensureLocationPermission();
        if (permissionGranted) {
          return await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
        }
      } else if (!_supportsApproximateLocationFallback) {
        _showSnack("Please enable location services");
        return null;
      }
    } catch (_) {
      if (!_supportsApproximateLocationFallback) {
        _showSnack("Unable to access GPS on this device");
        return null;
      }
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }
    } catch (_) {}

    if (_supportsApproximateLocationFallback) {
      final approximate = await _getApproximateLocation();
      if (approximate != null) {
        _showSnack("Using approximate laptop location from network");
        return approximate;
      }
    }

    _showSnack("Unable to get location on this device");
    return null;
  }

  bool get _supportsApproximateLocationFallback {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<bool> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showSnack("Location permission denied");
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnack("Location permission is permanently denied");
      return false;
    }

    return true;
  }

  Future<Position?> _getApproximateLocation() async {
    final result = await ApiService.getApproximateLocation();
    if (result["success"] != true) {
      return null;
    }

    final latitude = result["latitude"] as double;
    final longitude = result["longitude"] as double;

    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 5000,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: true,
    );
  }

  String _formatLocation(Position position) {
    final suffix = position.isMocked ? " (approximate network location)" : "";
    return "${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}$suffix";
  }

  Future<XFile?> _pickSelfie({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.front,
  }) async {
    final picker = ImagePicker();
    return await picker.pickImage(
      source: source,
      preferredCameraDevice: preferredCameraDevice,
      imageQuality: 80,
    );
  }

  Future<List<XFile>> _pickHistoryImages() async {
    final picker = ImagePicker();
    return await picker.pickMultiImage(imageQuality: 90);
  }

  Future<void> _ensurePartnerLoaded() async {
    if (AppState.partnerData["full_name"] != null || AppState.phone.isEmpty) {
      return;
    }

    final result = await ApiService.getProfile(AppState.phone);
    if (!mounted || result["success"] != true) {
      return;
    }

    setState(() {
      AppState.partnerData = Map<String, dynamic>.from(result["partner"] ?? {});
    });
  }

  Future<void> _startSession() async {
    if (needsHistoryUpload) {
      _showSnack(
        "Upload your delivery history screenshot before starting the next shift",
      );
      return;
    }

    setState(() => isLoading = true);

    final selfieFile = await _pickSelfie(source: ImageSource.camera);
    if (selfieFile == null) {
      setState(() => isLoading = false);
      _showSnack("Selfie required to start session");
      return;
    }

    final position = await _getLocation();
    if (position == null) {
      setState(() => isLoading = false);
      return;
    }

    final result = await ApiService.startSession(
      phone: AppState.phone,
      latitude: position.latitude,
      longitude: position.longitude,
      selfieFile: selfieFile,
    );

    setState(() => isLoading = false);

    if (!(result["success"] == true)) {
      _showSnack(result["message"] ?? "Selfie verification failed");
      return;
    }

    AppState.sessionId = "${result["session_id"] ?? ""}";
    AppState.isWorking = true;
    AppState.sessionStartTime = DateTime.now();
    AppState.lastSessionLocationLabel = _formatLocation(position);
    AppState.randomCheckDueAt = _parseBackendDate(result["random_due_at"]);

    setState(() {
      isWorking = true;
      sessionDuration = Duration.zero;
    });

    _startClock();
    _scheduleBackendRandomCheck();

    final dueTime = AppState.randomCheckDueAt;
    final dueText = dueTime == null
        ? ""
        : " Random selfie may be requested at ${_formatDateTime(dueTime)}.";
    _showSnack(
      "Your work session is protected. End the shift here when you are done.$dueText",
    );
  }

  Future<void> _endSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text("End session", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Demo flow: pick a selfie from gallery to end the session.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Continue"),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    setState(() => isLoading = true);

    final selfieFile = await _pickSelfie(source: ImageSource.gallery);
    if (selfieFile == null) {
      setState(() => isLoading = false);
      _showSnack("Gallery selfie required to end session");
      return;
    }

    final position = await _getLocation();
    if (position == null) {
      setState(() => isLoading = false);
      return;
    }

    final result = await ApiService.endSession(
      sessionId: AppState.sessionId,
      latitude: position.latitude,
      longitude: position.longitude,
      selfieFile: selfieFile,
    );

    setState(() => isLoading = false);

    if (!(result["success"] == true)) {
      _showSnack(result["message"] ?? "Unable to end session");
      return;
    }

    _randomCheckTimer?.cancel();
    _clockTimer?.cancel();

    AppState.isWorking = false;
    AppState.completedSessionId = AppState.sessionId;
    AppState.sessionId = "";
    AppState.sessionStartTime = null;
    AppState.randomCheckDueAt = null;
    AppState.lastSessionLocationLabel = _formatLocation(position);
    AppState.needsHistoryUpload = true;

    setState(() {
      isWorking = false;
      needsHistoryUpload = true;
      sessionDuration = Duration.zero;
      _randomCheckPending = false;
    });

    await _showSessionMetaDialog(
      title: "Session ended",
      message:
          "Selfie verified. Your work session was saved securely.\n\nUpload your delivery history screenshot so GigShield can update earnings and protection data.",
      position: position,
      timestamp: DateTime.now(),
    );

    if (mounted) {
      await _uploadDeliveryHistory();
    }
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startTime = AppState.sessionStartTime;
      if (startTime == null || !mounted) {
        return;
      }

      setState(() {
        sessionDuration = DateTime.now().difference(startTime);
      });
    });
  }

  void _scheduleBackendRandomCheck() {
    _randomCheckTimer?.cancel();

    final dueAt = AppState.randomCheckDueAt;
    if (!isWorking || dueAt == null) {
      return;
    }

    final wait = dueAt.difference(DateTime.now());
    if (wait.isNegative || wait == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isWorking) {
          _showBackendSelfieNotification();
        }
      });
      return;
    }

    _randomCheckTimer = Timer(wait, _showBackendSelfieNotification);
  }

  void _showBackendSelfieNotification() {
    if (!mounted || !isWorking || _randomCheckPending) {
      return;
    }

    _randomCheckPending = true;
    ScaffoldMessenger.of(context)
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: const Color(0xFF243B2A),
          content: const Text(
            "Backend asked for a selfie check. Please verify now.",
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                _showRandomCheckPopup();
              },
              child: const Text("Verify"),
            ),
          ],
        ),
      );

    _showRandomCheckPopup();
  }

  Future<void> _showRandomCheckPopup() async {
    if (!mounted || !isWorking) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          "Selfie verification required",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "GigShield requested a live safety check for ${_formatDateTime(DateTime.now())}. "
          "Take a selfie now to continue your protected session.",
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Take selfie"),
          ),
        ],
      ),
    );

    await _handleRandomCheck();
  }

  Future<void> _handleRandomCheck() async {
    final selfieFile = await _pickSelfie(source: ImageSource.camera);
    if (selfieFile == null) {
      _randomCheckPending = false;
      _showSnack("Random check cancelled");
      return;
    }

    final position = await _getLocation();
    if (position == null) {
      _randomCheckPending = false;
      return;
    }

    final result = await ApiService.submitRandomCheck(
      sessionId: AppState.sessionId,
      phone: AppState.phone,
      latitude: position.latitude,
      longitude: position.longitude,
      selfieFile: selfieFile,
    );

    _randomCheckPending = false;

    if (!(result["success"] == true)) {
      final nextDue = _parseBackendDate(result["random_due_at"]);
      if (nextDue != null) {
        AppState.randomCheckDueAt = nextDue;
        _scheduleBackendRandomCheck();
      }
      _showSnack(result["message"] ?? "Random check failed");
      return;
    }

    AppState.randomCheckDueAt = null;
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();

    _showSessionMetaDialog(
      title: "Verification complete",
      message:
          "Selfie verified. Date, time and location recorded for worker safety.",
      position: position,
      timestamp: DateTime.now(),
    );
  }

  Future<void> _showSessionMetaDialog({
    required String title,
    required String message,
    required Position position,
    required DateTime timestamp,
  }) {
    if (!mounted) {
      return Future.value();
    }

    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          "$message\n\nDate and time: ${_formatDateTime(timestamp)}"
          "\nLocation: ${_formatLocation(position)}",
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadDeliveryHistory() async {
    if (!needsHistoryUpload) {
      return;
    }

    final historyFiles = await _pickHistoryImages();
    if (historyFiles.isEmpty) {
      _showSnack("Select at least one delivery history screenshot");
      return;
    }

    setState(() => isLoading = true);

    final now = DateTime.now();
    final historyDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // Send directly to backend for OCR processing
    final result = await ApiService.submitSessionHistory(
      phone: AppState.phone,
      date: historyDate,
      historyFiles: historyFiles,
    );

    if (!mounted) {
      return;
    }

    setState(() => isLoading = false);

    if (result["success"] == true) {
      AppState.needsHistoryUpload = false;
      setState(() => needsHistoryUpload = false);

      final totalAmount = result["total_earned_amount"] ?? "0.00";
      final warnings = result["warnings"];
      final warningCount = warnings is List ? warnings.length : 0;

      _showSnack(
        "${result["message"] ?? "History uploaded"} Total: Rs $totalAmount"
        "${warningCount > 0 ? " • $warningCount warning(s)" : ""}",
      );
      return;
    }

    final details = result["details"];
    String? detailMessage;
    if (details is List && details.isNotEmpty) {
      final first = details.first;
      if (first is Map<String, dynamic>) {
        detailMessage = first["reason"]?.toString();
      } else if (first is Map) {
        detailMessage = first["reason"]?.toString();
      }
    } else if (details is String && details.isNotEmpty) {
      detailMessage = details;
    }

    _showSnack(
      detailMessage == null
          ? result["message"] ?? "Failed to process screenshots"
          : "${result["message"] ?? "Failed to process screenshots"}: $detailMessage",
    );
  }

  DateTime? _parseBackendDate(dynamic raw) {
    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _formatDateTime(DateTime value) {
    final date =
        "${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}";
    final time =
        "${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}";
    return "$date $time";
  }

  String get _formattedDuration {
    final h = sessionDuration.inHours.toString().padLeft(2, '0');
    final m = (sessionDuration.inMinutes % 60).toString().padLeft(2, '0');
    final s = (sessionDuration.inSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  void _showSnack(String msg) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1E293B)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF1FA35B);
    final firstName = AppState.fullName.trim().split(RegExp(r"\s+")).first;
    final canStartWorking = !isWorking && !needsHistoryUpload;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "GigShield",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Namaste, $firstName",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          if (needsHistoryUpload)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF5B3A11).withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Upload delivery history",
                    style: TextStyle(
                      color: Color(0xFFFCD34D),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Your shift is complete. Upload one or more screenshots from the delivery app so GigShield can refresh your earnings and readiness for the next shift.",
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: isLoading ? null : _uploadDeliveryHistory,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text("Upload Screenshot"),
                  ),
                ],
              ),
            ),
          if (isWorking)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: activeColor.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield, color: activeColor, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "Protected shift is live",
                            style: TextStyle(
                              color: activeColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formattedDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "GigShield is tracking time, location and safety checks while you work.",
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  if (AppState.randomCheckDueAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Next backend selfie check after ${_formatDateTime(AppState.randomCheckDueAt!)}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : ScaleTransition(
                      scale: isWorking
                          ? const AlwaysStoppedAnimation(1.0)
                          : canStartWorking
                          ? _pulseAnimation
                          : const AlwaysStoppedAnimation(1.0),
                      child: GestureDetector(
                        onTap: isWorking
                            ? _endSession
                            : canStartWorking
                            ? _startSession
                            : _uploadDeliveryHistory,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isWorking
                                ? activeColor.withValues(alpha: 0.22)
                                : canStartWorking
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.03),
                            border: Border.all(
                              color: isWorking
                                  ? activeColor
                                  : canStartWorking
                                  ? Colors.white54
                                  : Colors.white24,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isWorking
                                    ? activeColor.withValues(alpha: 0.35)
                                    : canStartWorking
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                blurRadius: 38,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isWorking
                                    ? Icons.verified_user_outlined
                                    : canStartWorking
                                    ? Icons.play_circle_outline
                                    : Icons.upload_file_outlined,
                                color: isWorking
                                    ? activeColor
                                    : canStartWorking
                                    ? Colors.white
                                    : Colors.white54,
                                size: 60,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isWorking
                                    ? "Session\nOn"
                                    : canStartWorking
                                    ? "Start\nWorking"
                                    : "Upload\nHistory",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isWorking
                                      ? activeColor
                                      : canStartWorking
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 20,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Text(
              isWorking
                  ? "Tap the green button to end the session with a gallery selfie"
                  : needsHistoryUpload
                  ? "Upload your latest delivery history screenshots first. Start Working returns after GigShield processes them."
                  : "Tap to start a verified work session with selfie, location and time protection",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
