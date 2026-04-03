// ============================================================
// app_state.dart
// ============================================================
// Global state holder — stores logged-in user data in memory.
// Import this anywhere you need the current user's info.
//
// HOW TO USE:
//   import '../services/app_state.dart';
//   AppState.phone          → "9876543210"
//   AppState.partnerData    → full user map from Django
//   AppState.isWorking      → true/false
//   AppState.sessionId      → current session ID from Django
// ============================================================

class AppState {
  // ──────────────────────────────────────────────
  // 👤 Logged-in user info
  // Set these after successful login
  // ──────────────────────────────────────────────
  static String phone = "";
  static Map<String, dynamic> partnerData = {};

  // ──────────────────────────────────────────────
  // 🟢 Work session state
  // ──────────────────────────────────────────────
  static bool isWorking = false;
  static String sessionId = ""; // Returned by /api/session/start/
  static DateTime? sessionStartTime;
  static DateTime? randomCheckDueAt;
  static String? lastSessionLocationLabel;
  static bool needsHistoryUpload = false;
  static String completedSessionId = "";

  // ──────────────────────────────────────────────
  // Helper getters — use these in UI
  // ──────────────────────────────────────────────
  static String get fullName => partnerData["full_name"] ?? "Partner";
  static String get city => partnerData["city"] ?? "";
  static String get platform => partnerData["platform"] ?? "Zomato";
  static String get email => partnerData["email"] ?? "";
  static double get walletBalance =>
      double.tryParse("${partnerData["wallet_balance"] ?? 0}") ?? 0;
  static String get region => partnerData["region"] ?? "west";

  // ──────────────────────────────────────────────
  // Clear everything on logout
  // ──────────────────────────────────────────────
  static void clear() {
    phone = "";
    partnerData = {};
    isWorking = false;
    sessionId = "";
    sessionStartTime = null;
    randomCheckDueAt = null;
    lastSessionLocationLabel = null;
    needsHistoryUpload = false;
    completedSessionId = "";
  }
}
