import 'dart:async';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_state.dart';
import 'session_history_screen.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  Timer? _pollingTimer;
  Map<String, dynamic>? _payload;
  List<dynamic> _history = [];
  bool _isLoading = true;
  String? _error;

  String _formatDateShort(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      return "${months[date.month - 1]} ${date.day}, ${date.year}";
    } catch (_) {
      return dateStr;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPremium();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadPremium(isPolling: true));
    AppState.mainTabNotifier.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (AppState.mainTabNotifier.value == 1) { // 1 is PremiumScreen
      _loadPremium(isPolling: false);
    }
  }

  @override
  void dispose() {
    AppState.mainTabNotifier.removeListener(_onTabChanged);
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPremium({bool collect = false, bool isPolling = false}) async {
    if (!isPolling) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    // ✅ Check if user is logged in
    if (AppState.phone.isEmpty) {
      setState(() {
        _error = "Please log in first to view premium details";
        _isLoading = false;
      });
      return;
    }

    final summaryFuture = ApiService.getPremiumSummary(
      phone: AppState.phone,
      collect: collect,
    );
    final historyFuture = ApiService.getSessionHistory(
      phone: AppState.phone,
    );

    final results = await Future.wait([summaryFuture, historyFuture]);
    final result = results[0];
    final historyResult = results[1];

    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      final data = Map<String, dynamic>.from(result["data"] ?? {});
      AppState.partnerData = {
        ...AppState.partnerData,
        "wallet_balance": data["wallet_balance"],
      };
      
      List<dynamic> loadedHistory = [];
      if (historyResult["success"] == true) {
        loadedHistory = (historyResult["data"] as List?) ?? [];
      }
      
      setState(() {
        _payload = data;
        _history = loadedHistory;
        _isLoading = false;
      });
      return;
    }

    if (isPolling && _payload != null) {
      // Background poll failed but we already have data, skip showing error
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
    final adaptiveScore = (premium["adaptive_score"] ?? 0).toString();
    final ruleScore = (premium["rule_score"] ?? 0).toString();
    final locationKey = (premium["location_key"] ?? "global").toString();
    final basePremium = (premium["base_premium"] ?? 0).toString();
    final dailyCap = (premium["daily_income_cap"] ?? 0).toString();
    final isDebited = _payload?["payment_status"] == "debited";
    final deductionLabel = isDebited ? "Debited this week" : "Will be debited Monday 7:00 PM IST";

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
            onPressed: _isLoading ? null : () => _loadPremium(),
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
                _card(
                  title: "Recent Work History",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_history.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            "No past sessions found. Start working and upload your earnings screenshots.",
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      ..._history.take(5).map((item) {
                        final date = _formatDateShort(item["date"]?.toString() ?? "");
                        final amount = item["total_earned_amount"]?.toString() ?? "0";
                        return InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SessionHistoryScreen(phone: AppState.phone),
                              ),
                            ).then((_) {
                              if (mounted) _loadPremium();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.history_toggle_off, color: Colors.white54, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      date,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                                Text(
                                  "₹$amount",
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _heroCard(
                  title: "Weekly protection premium",
                  value: "₹$premiumAmount",
                  subtitle:
                      "${premium["category"] ?? "casual"} • ${premium["region"] ?? AppState.city} region",
                  note:
                      "Estimated weekly deduction ₹$premiumAmount • $deductionLabel • Wallet ₹$walletBalance",
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
                      _row("Daily income cap", "₹$dailyCap", emphasize: true),
                      _row("Base premium", "₹$basePremium"),
                      _row("Adaptive score", adaptiveScore),
                      _row("Rule score", ruleScore),
                      _row("Weather risk", weatherScore),
                      _row(
                        "Hybrid multiplier",
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
                        "Estimated weekly deduction",
                        "₹$premiumAmount",
                        emphasize: true,
                      ),
                      _row(
                        "Scheduled debit",
                        deductionLabel,
                      ),
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
                        premium["deducted_on"]?.toString() ??
                            (isDebited ? "Completed" : "Pending"),
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
                      _row("Learning key", locationKey),
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
