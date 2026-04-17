import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_state.dart';
import 'ui_kit.dart';

class ClaimScreen extends StatefulWidget {
  const ClaimScreen({super.key});

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  List<dynamic> _claims = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (mounted && AppState.mainTabNotifier.value == 3) {
          _loadDashboard(silent: true);
        }
      },
    );
    AppState.mainTabNotifier.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (AppState.mainTabNotifier.value == 3) {
      // 3 is ClaimScreen
      _loadDashboard();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    AppState.mainTabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  Future<void> _loadDashboard({bool silent = false}) async {
    setState(() {
      if (silent) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
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
        _isLoading = false;
        _isRefreshing = false;
      });
      return;
    }

    setState(() {
      _error =
          result["message"]?.toString() ??
          "Unable to load automatic protection";
      _isLoading = false;
      _isRefreshing = false;
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
    final auditMaps = audits
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final newsAudit = _findAudit(auditMaps, "News API");
    final validationAudit = _findAudit(auditMaps, "Real News Validation");
    showModalBottomSheet(
      context: context,
      backgroundColor: AppUi.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
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
                  color: AppUi.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "${claim["event_type"]} • final ${claim["final_score"]} • AI ${claim["ai_score"]}",
                style: const TextStyle(color: AppUi.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                "The score blends news, weather, location, and activity.",
                style: TextStyle(color: AppUi.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 420;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: narrow ? constraints.maxWidth : (constraints.maxWidth - 10) / 2,
                        child: _miniStat(
                          label: "AI score",
                          value: "${claim["ai_score"] ?? ""}",
                        ),
                      ),
                      SizedBox(
                        width: narrow ? constraints.maxWidth : (constraints.maxWidth - 10) / 2,
                        child: _miniStat(
                          label: "Final score",
                          value: "${claim["final_score"] ?? ""}",
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppUi.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Validation snapshot",
                      style: TextStyle(
                        color: AppUi.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          claim["status"]?.toString() ?? "",
                          background: _statusColor(
                            claim["status"]?.toString() ?? "",
                          ).withValues(alpha: 0.16),
                          foreground: _statusColor(
                            claim["status"]?.toString() ?? "",
                          ),
                        ),
                        _chip(
                          "Weather ${claim["weather_score"] ?? 0}",
                        ),
                        _chip(
                          "News ${claim["news_confidence"] ?? 0}",
                        ),
                        _chip(
                          "Location ${claim["location_match"] ?? 0}",
                        ),
                        _chip(
                          "Activity ${claim["activity_drop"] ?? 0}",
                        ),
                      ],
                    ),
                    if (validationAudit != null) ...[
                      const SizedBox(height: 12),
                      _auditSummaryCard(Map<String, dynamic>.from(
                        validationAudit as Map,
                      )),
                    ],
                    if (newsAudit != null) ...[
                      const SizedBox(height: 12),
                      _newsPreviewCard(Map<String, dynamic>.from(newsAudit as Map)),
                    ],
                  ],
                ),
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
                              style: const TextStyle(color: AppUi.text),
                            ),
                            Text(
                              audit["detail"]?.toString() ?? "",
                              style: const TextStyle(
                                color: AppUi.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "${audit["score"] ?? ""}",
                        style: const TextStyle(color: AppUi.muted, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _auditSummaryCard(Map<String, dynamic> audit) {
    final summary = Map<String, dynamic>.from(
      audit["validation_summary"] as Map? ?? const {},
    );
    final matchedTitle = summary["matched_title"]?.toString();
    final matchedSource = summary["matched_source"]?.toString();
    final matchedSimilarity = summary["matched_similarity"];
    final matchedConfidence = summary["matched_confidence"];
    final requiresValidation = audit["requires_validation"] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            requiresValidation ? "Real news validation" : "Validation context",
            style: const TextStyle(color: AppUi.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            audit["detail"]?.toString() ?? "",
            style: const TextStyle(color: AppUi.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          Text(
            "Threshold ${summary["threshold"] ?? audit["threshold"] ?? ""} | Score ${summary["score"] ?? audit["score"] ?? ""}",
            style: const TextStyle(color: AppUi.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            matchedTitle?.isNotEmpty == true
                ? "Matched article: $matchedTitle"
                : "Matched article: none",
            style: const TextStyle(color: AppUi.text, fontSize: 12),
          ),
          if (matchedSource?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              "Source: $matchedSource",
              style: const TextStyle(color: AppUi.muted, fontSize: 12),
            ),
          ],
          if (matchedSimilarity != null || matchedConfidence != null) ...[
            const SizedBox(height: 4),
            Text(
              "Similarity ${matchedSimilarity ?? "n/a"} | AI confidence ${matchedConfidence ?? "n/a"}",
              style: const TextStyle(color: AppUi.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _findAudit(
    List<Map<String, dynamic>> audits,
    String signal,
  ) {
    for (final audit in audits) {
      if (audit["signal"]?.toString() == signal) {
        return audit;
      }
    }
    return null;
  }

  Widget _newsPreviewCard(Map<String, dynamic> audit) {
    final articles = (audit["articles"] as List?)?.cast<dynamic>() ?? const [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "News API evidence (${articles.length})",
            style: const TextStyle(color: AppUi.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            audit["detail"]?.toString() ?? "",
            style: const TextStyle(color: AppUi.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          ...articles.take(3).map((item) {
            final article = Map<String, dynamic>.from(item as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: AppUi.accent.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article["title"]?.toString() ?? "",
                          style: const TextStyle(
                            color: AppUi.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            article["source"]?.toString() ?? "",
                            article["event_type"]?.toString() ?? "",
                            "score ${article["confidence"] ?? 0}",
                          ].where((value) => value.trim().isNotEmpty).join(" • "),
                          style: const TextStyle(
                            color: AppUi.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Protection",
          style: TextStyle(color: AppUi.text, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: Colors.white38,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, color: AppUi.muted),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppUi.muted))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppUi.muted),
                ),
              ),
            )
          : ListView(
              padding: AppUi.pagePadding,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppUi.panel(borderColor: AppUi.success.withValues(alpha: 0.28)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "AUTOMATIC PROTECTION",
                        style: TextStyle(
                          color: AppUi.success,
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Triggered protection events appear here after automatic review.",
                        style: const TextStyle(
                          color: AppUi.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Tap any event to see the validation trail and payout details.",
                        style: const TextStyle(color: AppUi.muted, height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip("AI classification"),
                          _chip("Weather"),
                          _chip("News"),
                          _chip("Wallet"),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AppUi.panel(),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppUi.muted,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Wallet balance",
                          style: TextStyle(color: AppUi.text),
                        ),
                      ),
                      Text(
                        "₹${AppState.partnerData["wallet_balance"] ?? AppState.walletBalance}",
                        style: const TextStyle(
                          color: AppUi.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AppUi.sectionLabel("Recent protection events"),
                if (_claims.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: AppUi.panel(),
                    child: const Text(
                      "No active protection event yet. New alerts will appear here automatically.",
                      style: TextStyle(color: AppUi.muted),
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
                        color: AppUi.surface,
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
                              Expanded(
                                child: Text(
                                  autoCreated
                                      ? "Auto event #${claim["id"]}"
                                      : "Claim #${claim["id"]}",
                                  style: const TextStyle(
                                    color: AppUi.muted,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "AI ${claim["ai_score"] ?? 0}",
                              style: const TextStyle(
                                color: AppUi.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            claim["trigger_title"]?.toString().isNotEmpty ==
                                    true
                                ? claim["trigger_title"].toString()
                                : "${claim["event_type"]} • ${claim["city"]}",
                            style: const TextStyle(
                              color: AppUi.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            autoCreated
                                ? "Detected by ${claim["trigger_source"] ?? "system"}"
                                : "Manual review",
                            style: const TextStyle(
                              color: AppUi.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                "Final ${claim["final_score"]}",
                                style: const TextStyle(
                                  color: AppUi.muted,
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

  Widget _miniStat({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppUi.muted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppUi.text,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label, {
    Color? background,
    Color? foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground ?? AppUi.text,
          fontSize: 12,
        ),
      ),
    );
  }
}
