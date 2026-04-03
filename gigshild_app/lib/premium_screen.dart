import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_state.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  Map<String, dynamic>? _payload;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  Future<void> _loadPremium({bool collect = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // ✅ Check if user is logged in
    if (AppState.phone.isEmpty) {
      setState(() {
        _error = "Please log in first to view premium details";
        _isLoading = false;
      });
      return;
    }

    final result = await ApiService.getPremiumSummary(
      phone: AppState.phone,
      collect: collect,
    );

    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      final data = Map<String, dynamic>.from(result["data"] ?? {});
      AppState.partnerData = {
        ...AppState.partnerData,
        "wallet_balance": data["wallet_balance"],
      };
      setState(() {
        _payload = data;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _error =
          result["message"]?.toString() ?? "Unable to load protection plan";
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final premium =
        (_payload?["premium"] as Map?)?.cast<String, dynamic>() ?? {};
    final weather =
        (_payload?["weather"] as Map?)?.cast<String, dynamic>() ?? {};
    final ledger =
        (_payload?["recent_ledger"] as List?)?.cast<dynamic>() ?? const [];
    final premiumAmount = (premium["premium_amount"] ?? 0).toString();
    final walletBalance =
        (_payload?["wallet_balance"] ?? AppState.walletBalance).toString();
    final weatherScore =
        (premium["weather_score"] ?? weather["weather_score"] ?? 0).toString();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          "Premium",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _loadPremium(collect: true),
            icon: const Icon(Icons.payments_outlined, color: Colors.white70),
            tooltip: "Run weekly premium debit",
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadPremium,
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
                _heroCard(
                  title: "Weekly protection premium",
                  value: "₹$premiumAmount",
                  subtitle:
                      "${premium["category"] ?? "casual"} • ${premium["region"] ?? AppState.region} region",
                  note:
                      "${_payload?["payment_status"] == "debited" ? "Debited now" : "Estimate view"} • Wallet ₹$walletBalance",
                ),
                const SizedBox(height: 18),
                _card(
                  title: "Breakdown",
                  child: Column(
                    children: [
                      _row(
                        "Weekly income",
                        "₹${premium["weekly_income"] ?? 0}",
                      ),
                      _row("Total hours", "${premium["total_hours"] ?? 0} h"),
                      _row(
                        "Weekend hours",
                        "${premium["weekend_hours"] ?? 0} h",
                      ),
                      _row("Region rate", "${premium["region_rate"] ?? 0}"),
                      _row(
                        "Category multiplier",
                        "${premium["category_multiplier"] ?? 0}x",
                      ),
                      _row("Weather risk", weatherScore),
                      _row(
                        "Weather multiplier",
                        "${premium["weather_multiplier"] ?? 1}x",
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _card(
                  title: "Worker wallet",
                  child: Column(
                    children: [
                      _row(
                        "Wallet balance",
                        "₹$walletBalance",
                        emphasize: true,
                      ),
                      _row(
                        "Starting balance",
                        "₹${_payload?["testing_bonus"] ?? 5000}",
                      ),
                      _row(
                        "Monday deduction",
                        premium["deducted_on"]?.toString() ?? "Pending",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _card(
                  title: "Live weather signal",
                  child: Column(
                    children: [
                      _row("City", "${weather["city"] ?? AppState.city}"),
                      _row("Condition", "${weather["condition"] ?? "unknown"}"),
                      _row("Rainfall", "${weather["rainfall"] ?? 0} mm"),
                      _row("Temperature", "${weather["temperature"] ?? 0}°C"),
                      _row("Humidity", "${weather["humidity"] ?? 0}%"),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _card(
                  title: "Wallet activity",
                  child: Column(
                    children: ledger.take(4).map((entry) {
                      final item = Map<String, dynamic>.from(entry as Map);
                      final sign = item["direction"] == "debit" ? "-" : "+";
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item["description"]?.toString() ??
                                        item["entry_type"].toString(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  Text(
                                    item["created_at"]?.toString() ?? "",
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              "$sign₹${item["amount"]}",
                              style: TextStyle(
                                color: item["direction"] == "debit"
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _heroCard({
    required String title,
    required String value,
    required String subtitle,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF182C61), Color(0xFF0B132B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Text(
            note,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? Colors.white : Colors.white54,
              fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
