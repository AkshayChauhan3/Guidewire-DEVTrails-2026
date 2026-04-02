// ============================================================
// api_service.dart
// ============================================================
// This is the SINGLE FILE for all backend API calls.
// Every screen imports this file to talk to Django.
//
// HOW TO USE:
//   import '../services/api_service.dart';
//   final result = await ApiService.login("9876543210");
//
// TO CONNECT YOUR BACKEND:
//   Just change BASE_URL below to your Django server address.
//   - Android Emulator  → http://10.0.2.2:8000
//   - Linux Desktop     → http://127.0.0.1:8000
//   - Real Device       → http://YOUR_PC_IP:8000
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ApiService {
  // ──────────────────────────────────────────────
  // 🔧 CHANGE THIS to your Django server address
  // ──────────────────────────────────────────────
  // ignore: constant_identifier_names
  static const String BASE_URL = "http://localhost:8000/api";

  // ──────────────────────────────────────────────
  // 🔐 LOGIN
  // Sends phone number → gets back user data
  // Django endpoint: POST /api/login/
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String phone) async {
    try {
      final response = await http.post(
        Uri.parse("$BASE_URL/login/"),
        body: {"phone": phone},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // ✅ Login success — returns partner data
        return {"success": true, "partner": data["partner"]};
      } else {
        // ❌ Phone not found
        return {"success": false, "message": data["message"]};
      }
    } catch (e) {
      // ❌ Network error — Django not running or wrong URL
      return {"success": false, "message": "Connection failed. Is Django running?"};
    }
  }

  // ──────────────────────────────────────────────
  // 👤 GET PROFILE
  // Fetches full user data by phone number
  // Django endpoint: GET /api/profile/<phone>/
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> getProfile(String phone) async {
    try {
      final response = await http.get(
        Uri.parse("$BASE_URL/profile/$phone/"),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "partner": data["partner"]};
      } else {
        return {"success": false, "message": data["message"]};
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed."};
    }
  }

  // ──────────────────────────────────────────────
  // 📸 VERIFY USER
  // Sends phone number and selfie image to verify identity
  // Django endpoint: POST /api/verify-user/
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyUser({
    required String phone,
    required XFile selfieFile,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$BASE_URL/verify-user/"),
      );

      request.fields['phone'] = phone;

      final bytes = await selfieFile.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'selfie_image',
          bytes,
          filename: selfieFile.name,
        ),
      );

      var response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 200) {
        if (data["match"] == true) {
          return {"success": true, "message": "Verification Successful"};
        } else {
          return {"success": false, "message": "Face did not match. Please try again."};
        }
      } else {
        return {"success": false, "message": data["error"] ?? "Verification failed"};
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed."};
    }
  }

  // ──────────────────────────────────────────────
  // 🟢 START WORK SESSION
  // Called when user taps "I'm Working"
  // Django endpoint: POST /api/session/start/
  //
  // BACKEND SETUP NEEDED:
  // Create a WorkSession model with:
  //   partner (FK), start_time, start_lat, start_lng, status
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> startSession({
    required String phone,
    required double latitude,
    required double longitude,
    required String selfiePath,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$BASE_URL/session/start/"),
      );

      // Send location + phone
      request.fields.addAll({
        "phone": phone,
        "latitude": latitude.toString(),
        "longitude": longitude.toString(),
      });

      // Send selfie image
      request.files.add(
        await http.MultipartFile.fromPath('selfie', selfiePath),
      );

      var response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 201) {
        // Returns session_id — save this to end the session later
        return {"success": true, "session_id": data["session_id"]};
      } else {
        return {"success": false, "message": data["message"]};
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed."};
    }
  }

  // ──────────────────────────────────────────────
  // 🔴 END WORK SESSION
  // Called when user taps "End Session"
  // Django endpoint: POST /api/session/end/
  //
  // BACKEND SETUP NEEDED:
  // Update WorkSession: end_time, end_lat, end_lng, end_selfie, status=completed
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> endSession({
    required String sessionId,
    required double latitude,
    required double longitude,
    required String selfiePath,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$BASE_URL/session/end/"),
      );

      request.fields.addAll({
        "session_id": sessionId,
        "latitude": latitude.toString(),
        "longitude": longitude.toString(),
      });

      request.files.add(
        await http.MultipartFile.fromPath('selfie', selfiePath),
      );

      var response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 200) {
        return {"success": true};
      } else {
        return {"success": false, "message": data["message"]};
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed."};
    }
  }

  // ──────────────────────────────────────────────
  // 📸 RANDOM CHECK — Submit selfie + location
  // Called during random popup checks
  // Django endpoint: POST /api/session/check/
  //
  // BACKEND SETUP NEEDED:
  // Create SessionCheck model:
  //   session (FK), timestamp, lat, lng, selfie_image
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> submitRandomCheck({
    required String sessionId,
    required double latitude,
    required double longitude,
    required String selfiePath,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$BASE_URL/session/check/"),
      );

      request.fields.addAll({
        "session_id": sessionId,
        "latitude": latitude.toString(),
        "longitude": longitude.toString(),
      });

      request.files.add(
        await http.MultipartFile.fromPath('selfie', selfiePath),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        return {"success": true};
      } else {
        return {"success": false};
      }
    } catch (e) {
      return {"success": false};
    }
  }

  // ──────────────────────────────────────────────
  // 📋 GET CLAIMS
  // Fetch past claims for the user
  // Django endpoint: GET /api/claims/<phone>/
  //
  // BACKEND SETUP NEEDED:
  // Claim model: partner, date, type, status, payout_amount
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> getClaims(String phone) async {
    try {
      final response = await http.get(
        Uri.parse("$BASE_URL/claims/$phone/"),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "claims": data["claims"]};
      } else {
        return {"success": false, "claims": []};
      }
    } catch (e) {
      return {"success": false, "claims": []};
    }
  }

  // ──────────────────────────────────────────────
  // 💰 GET PREMIUM
  // Fetch calculated premium for user
  // Django endpoint: GET /api/premium/<phone>/
  //
  // FOR HACKATHON DEMO:
  // You can hardcode ₹5000 in Django view for now
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> getPremium(String phone) async {
    try {
      final response = await http.get(
        Uri.parse("$BASE_URL/premium/$phone/"),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "premium": data["premium"]};
      } else {
        // Fallback for demo if endpoint not ready
        return {
          "success": true,
          "premium": {
            "base": 4200,
            "regional": 305,
            "crisis_buffer": 495,
            "total": 5000,
            "worker_type": "Full-time",
            "region": "West",
            "crisis_level": "Mild",
          }
        };
      }
    } catch (e) {
      // ✅ Hardcoded fallback for hackathon demo
      return {
        "success": true,
        "premium": {
          "base": 4200,
          "regional": 305,
          "crisis_buffer": 495,
          "total": 5000,
          "worker_type": "Full-time",
          "region": "West",
          "crisis_level": "Mild",
        }
      };
    }
  }
}