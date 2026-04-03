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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ApiService {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }

    if (kIsWeb) {
      return "http://127.0.0.1:8000/api";
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return "http://10.0.2.2:8000/api";
      case TargetPlatform.iOS:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return "http://127.0.0.1:8000/api";
      case TargetPlatform.fuchsia:
        return "http://127.0.0.1:8000/api";
    }
  }

  static Uri _apiUri(String path) => Uri.parse("$baseUrl$path");

  static Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return {};
    }

    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  static Future<http.MultipartFile> _multipartImageFromXFile(
    String fieldName,
    XFile imageFile,
  ) async {
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('Selected image is empty');
    }

    return http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: imageFile.name.isNotEmpty ? imageFile.name : 'selfie.jpg',
    );
  }

  static Future<Map<String, dynamic>> getApproximateLocation() async {
    try {
      final response = await http.get(Uri.parse("https://ipapi.co/json/"));
      final data = _decodeBody(response.body);
      final latitude = _asDouble(data["latitude"]);
      final longitude = _asDouble(data["longitude"]);

      if (response.statusCode == 200 && latitude != null && longitude != null) {
        return {
          "success": true,
          "latitude": latitude,
          "longitude": longitude,
          "source": "network",
          "city": data["city"],
          "region": data["region"],
        };
      }

      return {"success": false, "message": "Approximate location unavailable."};
    } catch (_) {
      return {
        "success": false,
        "message": "Approximate location lookup failed.",
      };
    }
  }

  static Future<Map<String, dynamic>> getCityData({
    required String phone,
    String? city,
  }) async {
    try {
      final queryParameters = <String, String>{};
      if (phone.trim().isNotEmpty) {
        queryParameters["phone"] = phone.trim();
      }
      if ((city ?? "").trim().isNotEmpty) {
        queryParameters["city"] = city!.trim();
      }

      final response = await http.get(
        _apiUri("/city-data/").replace(queryParameters: queryParameters),
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "data": data};
      }

      return {
        "success": false,
        "message": data["message"] ?? "Unable to fetch city data",
        "data": data,
      };
    } catch (e) {
      return {
        "success": false,
        "message": "Connection failed. Backend unreachable at $baseUrl.",
      };
    }
  }

  static Future<Map<String, dynamic>> getPremiumSummary({
    required String phone,
    bool collect = false,
  }) async {
    try {
      final response = await http.get(
        _apiUri("/premium/summary/").replace(
          queryParameters: {
            "phone": phone.trim(),
            "collect": collect.toString(),
          },
        ),
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "data": data};
      }

      return {
        "success": false,
        "message": data["message"] ?? "Unable to load premium summary",
      };
    } catch (_) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
    }
  }

  static Future<Map<String, dynamic>> getClaimsDashboard({
    required String phone,
  }) async {
    try {
      final response = await http.get(
        _apiUri(
          "/claims/dashboard/",
        ).replace(queryParameters: {"phone": phone.trim()}),
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "data": data};
      }

      return {
        "success": false,
        "message": data["message"] ?? "Unable to load claims dashboard",
      };
    } catch (_) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
    }
  }

  // ──────────────────────────────────────────────
  // 🔐 LOGIN
  // Sends phone number → gets back user data
  // Django endpoint: POST /api/login/
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String phone) async {
    try {
      final response = await http.post(
        _apiUri("/login/"),
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
      return {
        "success": false,
        "message": "Connection failed. Backend unreachable at $baseUrl.",
      };
    }
  }

  // ──────────────────────────────────────────────
  // 👤 GET PROFILE
  // Fetches full user data by phone number
  // Django endpoint: GET /api/profile/<phone>/
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> getProfile(String phone) async {
    try {
      final response = await http.get(_apiUri("/profile/$phone/"));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {"success": true, "partner": data["partner"]};
      } else {
        return {"success": false, "message": data["message"]};
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
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
      var request = http.MultipartRequest('POST', _apiUri("/verify-user/"));

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
          return {
            "success": false,
            "message": "Face did not match. Please try again.",
          };
        }
      } else {
        return {
          "success": false,
          "message": data["error"] ?? "Verification failed",
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
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
    required XFile selfieFile,
  }) async {
    try {
      var request = http.MultipartRequest('POST', _apiUri("/session/start/"));

      // Send location + phone
      request.fields.addAll({
        "phone": phone,
        "latitude": latitude.toString(),
        "longitude": longitude.toString(),
      });

      // Send selfie image
      request.files.add(
        await _multipartImageFromXFile('selfie_image', selfieFile),
      );

      var response = await request.send();
      final body = await response.stream.bytesToString();
      final data = _decodeBody(body);

      if (response.statusCode == 201) {
        return {
          "success": true,
          "session_id": data["session_id"],
          "message": data["message"],
          "random_due_at": data["random_due_at"],
          "random_hours": data["random_hours"],
        };
      } else {
        return {
          "success": false,
          "message": data["message"] ?? "Unable to start session",
          "details": data["details"],
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
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
    required XFile selfieFile,
  }) async {
    try {
      var request = http.MultipartRequest('POST', _apiUri("/session/stop/"));

      request.fields.addAll({
        "session_id": sessionId,
        "latitude": latitude.toString(),
        "longitude": longitude.toString(),
      });

      request.files.add(
        await _multipartImageFromXFile('selfie_image', selfieFile),
      );

      var response = await request.send();
      final body = await response.stream.bytesToString();
      final data = _decodeBody(body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "message": data["message"],
          "session_id": data["session_id"],
          "end_time": data["end_time"],
          "is_complete": data["is_complete"],
        };
      } else {
        return {
          "success": false,
          "message": data["message"] ?? "Unable to end session",
          "details": data["details"],
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
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
    required String phone,
    required double latitude,
    required double longitude,
    required XFile selfieFile,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        _apiUri("/session/random-check/"),
      );

      request.fields.addAll({
        "session_id": sessionId,
        "phone": phone,
        "latitude": latitude.toString(),
        "longitude": longitude.toString(),
      });

      request.files.add(
        await _multipartImageFromXFile('selfie_image', selfieFile),
      );

      var response = await request.send();
      final body = await response.stream.bytesToString();
      final data = _decodeBody(body);

      if (response.statusCode == 200) {
        return {
          "success": true,
          "message": data["message"],
          "session_id": data["session_id"],
          "random_time": data["random_time"],
        };
      } else {
        return {
          "success": false,
          "message": data["message"] ?? "Unable to verify random check",
          "random_due_at": data["random_due_at"],
          "details": data["details"],
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
    }
  }

  static Future<Map<String, dynamic>> submitSessionHistory({
    required String phone,
    required String date,
    List<XFile> historyFiles = const [],
  }) async {
    try {
      if (historyFiles.isEmpty) {
        return {
          "success": false,
          "message": "Upload at least one delivery history screenshot",
        };
      }

      final request = http.MultipartRequest(
        'POST',
        _apiUri("/session/history/"),
      );

      request.fields.addAll({
        "phone": phone,
        "date": date,
        "ocr_source": "server", // Backend will do OCR and extract amounts
      });

      for (final historyFile in historyFiles) {
        request.files.add(
          await _multipartImageFromXFile('images', historyFile),
        );
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = _decodeBody(body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          "success": true,
          "message": data["message"] ?? "History uploaded ✅",
          "total_earned_amount": data["total_earned_amount"],
          "extracted_amounts": data["extracted_amounts"],
          "warnings": data["warnings"],
        };
      }

      return {
        "success": false,
        "message": data["message"] ?? "Unable to upload history",
        "details": data["details"],
        "warnings": data["warnings"],
      };
    } on FormatException catch (e) {
      return {"success": false, "message": e.message};
    } catch (e) {
      return {
        "success": false,
        "message": "Connection failed at $baseUrl.",
        "details": e.toString(),
      };
    }
  }

  // ──────────────────────────────────────────────
  // 📰 CREATE DEMO EVENT
  // Publishes a fake news event for testing claims
  // Django endpoint: POST /api/demo-events/
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> createDemoEvent({
    required String phone,
    required String city,
    required String area,
    required String eventType,
    required String severity,
    required String headline,
    required String summary,
  }) async {
    try {
      final response = await http.post(
        _apiUri("/demo-events/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phone.trim(),
          "city": city,
          "area": area,
          "event_type": eventType,
          "severity": severity,
          "headline": headline,
          "summary": summary,
          "source": "flutter-app",
        }),
      );
      final data = _decodeBody(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          "success": true,
          "message": "Demo event created successfully",
          "event_id": data["event_id"],
        };
      }

      return {
        "success": false,
        "message": data["message"] ?? "Unable to create demo event",
      };
    } catch (e) {
      return {"success": false, "message": "Connection failed at $baseUrl."};
    }
  }
}
