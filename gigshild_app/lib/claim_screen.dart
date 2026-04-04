import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_state.dart';

class ClaimScreen extends StatefulWidget {
  const ClaimScreen({super.key});

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  List<dynamic> _claims = [];
  List<dynamic> _activeEvents = [];
  List<dynamic> _newAutoClaims = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getClaimsDashboard(phone: AppState.phone);
    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      final data = Map<String, dynamic>.from(result["data"] ?? {});
      final autoClaims =
          (data["auto_generated_claims"] as List?)?.cast<dynamic>() ?? [];
      AppState.partnerData = {
        ...AppState.partnerData,
        "wallet_balance": data["wallet_balance"],
      };

      // ✅ Combine auto-generated claims with regular claims
      final allClaims = <dynamic>[
        ...autoClaims,
        ...(data["claims"] as List?)?.cast<dynamic>() ?? [],
      ];

      // ✅ Remove duplicates by claim ID and sort newest first
      final Map<int, dynamic> claimMap = {};
      for (final claim in allClaims) {
        final claimmapItem = Map<String, dynamic>.from(claim as Map);
        final id = claimmapItem["id"] as int?;
        if (id != null) {
          claimMap[id] = claim;
        }
      }
      final consolidatedClaims = claimMap.values.toList();
      // Sort by created_at descending (newest first)
      consolidatedClaims.sort((a, b) {
        final aTime =
            DateTime.tryParse((a["created_at"] ?? "") as String) ??
            DateTime(2000);
        final bTime =
            DateTime.tryParse((b["created_at"] ?? "") as String) ??
            DateTime(2000);
        return bTime.compareTo(aTime);
      });

      setState(() {
        _claims = consolidatedClaims;
        _activeEvents = (data["active_events"] as List?)?.cast<dynamic>() ?? [];
        _newAutoClaims = autoClaims;
        _isLoading = false;
      });

      if (autoClaims.isNotEmpty) {
        final latest = Map<String, dynamic>.from(autoClaims.first as Map);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Protection updated automatically for ${latest["event_type"]} • payout ₹${latest["payout_amount"]}",
            ),
            backgroundColor: const Color(0xFF202020),
          ),
        );
      }
      return;
    }

    setState(() {
      _error =
          result["message"]?.toString() ??
          "Unable to load automatic protection";
      _isLoading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case "APPROVED":
        return Colors.green;
      case "REJECTED_FRAUD":
        return Colors.deepOrange;
      case "REJECTED":
        return Colors.redAccent;
      default:
        return Colors.amber;
    }
  }

  void _showAuditTrail(Map<String, dynamic> claim) {
    final audits = (claim["audit"] as List?)?.cast<dynamic>() ?? const [];
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Protection Event #${claim["id"]}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "${claim["event_type"]} • score ${claim["final_score"]}",
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 18),
            ...audits.map((item) {
              final audit = Map<String, dynamic>.from(item as Map);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      audit["passed"] == true
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: audit["passed"] == true
                          ? Colors.green
                          : Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            audit["signal"]?.toString() ?? "",
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text(
                            audit["detail"]?.toString() ?? "",
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "${audit["score"] ?? ""}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeEvent = _activeEvents.isNotEmpty
        ? Map<String, dynamic>.from(_activeEvents.first as Map)
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "Protection",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, color: Colors.white54),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2E22),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF1FA35B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "AUTOMATIC PROTECTION IS ACTIVE",
                        style: TextStyle(
                          color: Color(0xFF6EE7B7),
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _newAutoClaims.isNotEmpty
                            ? "GigShield detected a disruption and created support automatically."
                            : "You do not need to file a claim manually. GigShield monitors city alerts and weather for you.",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        activeEvent != null
                            ? activeEvent["headline"]?.toString() ??
                                  "Live city risk signal detected"
                            : "If a fake demo event, city alert, or severe weather is detected, payout review starts automatically.",
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip("Weather monitoring"),
                          _chip("News monitoring"),
                          _chip("Wallet auto credit"),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_newAutoClaims.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      "${_newAutoClaims.length} new protection event(s) were created during this refresh.",
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Emergency support wallet",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      Text(
                        "₹${AppState.partnerData["wallet_balance"] ?? AppState.walletBalance}",
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "RECENT PROTECTION EVENTS",
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (_claims.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      "No disruption has been detected for your area yet. Your protection stays on in the background.",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ..._claims.map((item) {
                  final claim = Map<String, dynamic>.from(item as Map);
                  final statusColor = _statusColor(
                    claim["status"]?.toString() ?? "",
                  );
                  final autoCreated = claim["auto_created"] == true;
                  return GestureDetector(
                    onTap: () => _showAuditTrail(claim),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                autoCreated
                                    ? "Auto event #${claim["id"]}"
                                    : "Claim #${claim["id"]}",
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  claim["status"]?.toString() ?? "",
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            claim["trigger_title"]?.toString().isNotEmpty ==
                                    true
                                ? claim["trigger_title"].toString()
                                : "${claim["event_type"]} • ${claim["city"]}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            autoCreated
                                ? "Detected by ${claim["trigger_source"] ?? "system"}"
                                : "Manual review",
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                "Score ${claim["final_score"]}",
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                "₹${claim["payout_amount"]} payout",
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}
