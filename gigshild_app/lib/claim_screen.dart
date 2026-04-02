// ============================================================
// claim_screen.dart
// ============================================================
// Shows:
//   1. Auto-detected disaster alert (from weather/news data)
//   2. History of past claims with status + audit trail
//
// BACKEND CONNECTION:
//   ApiService.getClaims(phone) → GET /api/claims/<phone>/
//
// FOR HACKATHON DEMO:
//   Pre-seeded dummy claims are shown if backend returns empty.
//   Auto-detection alert is simulated with a demo trigger.
//
// DJANGO SETUP NEEDED:
//   Claim model: partner, date, crisis_type, status,
//                payout_amount, audit_log (JSON)
// ============================================================

import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_state.dart';

class ClaimScreen extends StatefulWidget {
  const ClaimScreen({super.key});

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  List<dynamic> claims = [];
  bool isLoading = true;
  bool hasAutoDetectedEvent = true; // Set true for hackathon demo

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  // ──────────────────────────────────────────────
  // 🔗 API CALL → GET /api/claims/<phone>/
  // Falls back to demo data if backend not ready
  // ──────────────────────────────────────────────
  Future<void> _loadClaims() async {
    final result = await ApiService.getClaims(AppState.phone);

    if (mounted) {
      setState(() {
        if (result["success"] && (result["claims"] as List).isNotEmpty) {
          claims = result["claims"];
        } else {
          // ✅ Demo data for hackathon — pre-seeded claims
          // Replace with real Django data when backend ready
          claims = _demoClaimsData;
        }
        isLoading = false;
      });
    }
  }

  // ──────────────────────────────────────────────
  // Demo claims data (for hackathon presentation)
  // 🔗 BACKEND: This will come from GET /api/claims/<phone>/
  // Django Claim model fields:
  //   id, crisis_type, date, status, payout, audit
  // ──────────────────────────────────────────────
  final List<Map<String, dynamic>> _demoClaimsData = [
    {
      "id": "1042",
      "crisis_type": "Mumbai Floods",
      "date": "15 Mar 2026",
      "status": "APPROVED",
      "payout": 840,
      "audit": [
        {"signal": "Weather API",    "detail": "Rainfall 130mm",          "passed": true,  "score": "0.87"},
        {"signal": "News BERT",      "detail": "Mumbai floods detected",  "passed": true,  "score": "0.92"},
        {"signal": "Location Match", "detail": "2.3km from flood zone",   "passed": true,  "score": "—"},
        {"signal": "Activity Drop",  "detail": "90% drop detected",       "passed": true,  "score": "—"},
      ],
      "confidence": "0.91",
    },
    {
      "id": "1031",
      "crisis_type": "Road Block — Protest",
      "date": "02 Feb 2026",
      "status": "PENDING",
      "payout": 0,
      "audit": [
        {"signal": "Weather API",    "detail": "Clear skies",             "passed": false, "score": "0.12"},
        {"signal": "News BERT",      "detail": "Protest reported nearby", "passed": true,  "score": "0.71"},
        {"signal": "Location Match", "detail": "Within protest zone",     "passed": true,  "score": "—"},
        {"signal": "Activity Drop",  "detail": "65% drop detected",       "passed": true,  "score": "—"},
      ],
      "confidence": "0.68",
    },
    {
      "id": "1018",
      "crisis_type": "Heatwave",
      "date": "10 Jan 2026",
      "status": "REJECTED",
      "payout": 0,
      "audit": [
        {"signal": "Weather API",    "detail": "Temp 38°C, no extreme",   "passed": false, "score": "0.31"},
        {"signal": "News BERT",      "detail": "No crisis news found",    "passed": false, "score": "0.22"},
        {"signal": "Location Match", "detail": "Outside affected zone",   "passed": false, "score": "—"},
        {"signal": "Activity Drop",  "detail": "Only 20% drop",           "passed": false, "score": "—"},
      ],
      "confidence": "0.28",
    },
  ];

  // ──────────────────────────────────────────────
  // Show the full audit trail for a claim
  // This is the "explainability" feature from README
  // ──────────────────────────────────────────────
  void _showAuditTrail(Map<String, dynamic> claim) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Claim #${claim["id"]} Audit Trail",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Confidence: ${claim["confidence"]}  •  ${claim["crisis_type"]}",
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            // Audit signals
            ...(claim["audit"] as List).map((a) => _auditRow(
              a["signal"],
              a["detail"],
              a["passed"],
              a["score"],
            )),
            const SizedBox(height: 16),
            // Final decision
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor(claim["status"]).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _statusColor(claim["status"]).withValues(alpha: 0.4)),
              ),
              child: Text(
                "DECISION: ${claim["status"]}  (confidence: ${claim["confidence"]})",
                style: TextStyle(
                  color: _statusColor(claim["status"]),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case "APPROVED": return Colors.green;
      case "PENDING":  return Colors.amber;
      case "REJECTED": return Colors.red;
      default:         return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Claims", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [

                // ── Auto-Detected Event Alert ──
                // For demo: always shown
                // In production: show when ML detects a crisis in user's area
                // 🔗 BACKEND: GET /api/disaster-check/<phone>/ returns active events
                if (hasAutoDetectedEvent) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text("🚨", style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                "AUTO-DETECTED EVENT",
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            // Dismiss button
                            GestureDetector(
                              onTap: () => setState(() => hasAutoDetectedEvent = false),
                              child: const Icon(Icons.close, color: Colors.white38, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "🌊 Flooding detected in your area",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Based on weather data, news reports, and your location, "
                          "you may be eligible for an emergency claim.",
                          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            // Eligibility badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "Eligibility: HIGH",
                                style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // File claim button
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _showFileClaimDialog(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text("File Claim Now", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Claims History ──
                const Text(
                  "CLAIM HISTORY",
                  style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5),
                ),
                const SizedBox(height: 12),

                ...claims.map((claim) => _claimCard(claim)),

                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _claimCard(Map<String, dynamic> claim) {
    final statusColor = _statusColor(claim["status"]);

    return GestureDetector(
      onTap: () => _showAuditTrail(claim), // Tap to see audit trail
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Claim number
                Text(
                  "Claim #${claim["id"]}",
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    claim["status"],
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              claim["crisis_type"],
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.white38, size: 12),
                const SizedBox(width: 4),
                Text(claim["date"], style: const TextStyle(color: Colors.white38, fontSize: 12)),
                if (claim["payout"] > 0) ...[
                  const Spacer(),
                  Text(
                    "₹${claim["payout"]} paid",
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Tap hint
            Row(
              children: [
                const Spacer(),
                const Text("Tap to view audit trail", style: TextStyle(color: Colors.white24, fontSize: 11)),
                const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _auditRow(String signal, String detail, bool passed, String score) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            color: passed ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(signal, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(detail, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          if (score != "—")
            Text(score, style: TextStyle(color: passed ? Colors.green : Colors.red, fontSize: 12)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // File Claim dialog
  // 🔗 BACKEND: POST /api/claims/file/
  //   body: { phone, crisis_type, latitude, longitude }
  // ──────────────────────────────────────────────
  void _showFileClaimDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("File Claim", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Your location and activity data will be used to verify this claim automatically.\n\nML pipeline will process it within minutes.",
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Claim submitted! ML pipeline running... ⚡"),
                  backgroundColor: Color(0xFF2A2A2A),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            child: const Text("Submit Claim", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}