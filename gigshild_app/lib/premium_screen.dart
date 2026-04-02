// ============================================================
// premium_screen.dart
// ============================================================
// Shows the calculated insurance premium breakdown.
//
// FOR HACKATHON DEMO:
//   Data is hardcoded to ₹5,000 total as fallback.
//   The interactive Crisis Index slider lets judges see
//   how premium changes — great for demo!
//
// BACKEND CONNECTION:
//   ApiService.getPremium(phone) → GET /api/premium/<phone>/
//
// DJANGO SETUP NEEDED (when ready):
//   Create a view that returns:
//   { "base": 4200, "regional": 305, "crisis_buffer": 495,
//     "total": 5000, "worker_type": "Full-time",
//     "region": "West", "crisis_level": "Mild" }
// ============================================================

import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_state.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  Map<String, dynamic> premium = {};
  bool isLoading = true;

  // ── Crisis Index Slider (for demo) ──
  // 0 = Mild, 1 = Moderate, 2 = Severe, 3 = Emergency
  double crisisLevel = 0;

  // Crisis multipliers (from your README)
  final List<Map<String, dynamic>> crisisData = [
    {"label": "Mild",      "multiplier": 1.0,  "color": Colors.green,   "desc": "Normal Conditions"},
    {"label": "Moderate",  "multiplier": 1.25, "color": Colors.yellow,  "desc": "Rainy Day"},
    {"label": "Severe",    "multiplier": 1.5,  "color": Colors.orange,  "desc": "Heavy Waterlogging"},
    {"label": "Emergency", "multiplier": 2.0,  "color": Colors.red,     "desc": "Natural Disaster"},
  ];

  int get _basePremium => premium["base"]?.toInt() ?? 4200;

  // Calculate total based on crisis slider
  int get _simulatedTotal {
    final multiplier = crisisData[crisisLevel.toInt()]["multiplier"] as double;
    final regional = premium["regional"]?.toInt() ?? 305;
    return ((_basePremium * multiplier) + regional).toInt();
  }

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  // ──────────────────────────────────────────────
  // 🔗 API CALL → GET /api/premium/<phone>/
  // Falls back to hardcoded ₹5000 for demo
  // ──────────────────────────────────────────────
  Future<void> _loadPremium() async {
    final result = await ApiService.getPremium(AppState.phone);
    if (mounted) {
      setState(() {
        premium = result["premium"] ?? {};
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final crisis = crisisData[crisisLevel.toInt()];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Premium", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [

                  // ── Total Premium Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Your Weekly Premium",
                          style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "₹${_simulatedTotal.toString()}",
                          style: TextStyle(
                            color: crisis["color"] as Color,
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Deducted every Monday",
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        // Worker type badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "${premium["worker_type"] ?? "Full-time"} • ${premium["region"] ?? "West"} Region",
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Breakdown Card ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "BREAKDOWN",
                          style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 16),
                        _breakdownRow("Base Premium", "₹${((_basePremium * (crisis['multiplier'] as double)).toInt())}"),
                        _breakdownRow("Regional (${premium["region"] ?? "West"} 6.1%)", "+₹${premium["regional"] ?? 305}"),
                        const Divider(color: Colors.white12, height: 24),
                        _breakdownRow("Total", "₹$_simulatedTotal", isTotal: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Crisis Index Simulator ──
                  // This is the hackathon demo feature!
                  // Drag the slider to show how crisis affects premium
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: (crisis["color"] as Color).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "CRISIS INDEX SIMULATOR",
                              style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5),
                            ),
                            // Demo badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text("DEMO", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Current crisis level display
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: crisis["color"] as Color,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "${crisis["label"]} — ${crisis["desc"]}",
                              style: TextStyle(
                                color: crisis["color"] as Color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              "${crisis["multiplier"]}×",
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: crisis["color"] as Color,
                            thumbColor: crisis["color"] as Color,
                            inactiveTrackColor: Colors.white12,
                            overlayColor: (crisis["color"] as Color).withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: crisisLevel,
                            min: 0,
                            max: 3,
                            divisions: 3,
                            onChanged: (val) => setState(() => crisisLevel = val),
                          ),
                        ),
                        // Labels
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: crisisData
                              .map((c) => Text(c["label"] as String,
                                  style: const TextStyle(color: Colors.white38, fontSize: 10)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Region Premiums Info ──
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "REGIONAL PREMIUMS",
                          style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 16),
                        _regionRow("North", "Snow", "6.8%"),
                        _regionRow("East",  "Rainfall", "6.4%"),
                        _regionRow("West",  "Some Heat", "6.1%", isActive: true),
                        _regionRow("South", "Extreme Heat", "6.5%"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            color: isTotal ? Colors.white : Colors.white60,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            fontSize: isTotal ? 16 : 14,
          )),
          Text(value, style: TextStyle(
            color: isTotal ? Colors.white : Colors.white,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            fontSize: isTotal ? 16 : 14,
          )),
        ],
      ),
    );
  }

  Widget _regionRow(String region, String reason, String premium, {bool isActive = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive ? Border.all(color: Colors.white24) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(region, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(reason, style: const TextStyle(color: Colors.white38, fontSize: 12))),
          Text(premium, style: TextStyle(
            color: isActive ? Colors.white : Colors.white38,
            fontWeight: FontWeight.bold,
          )),
          if (isActive) ...[
            const SizedBox(width: 8),
            const Text("← You", style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}