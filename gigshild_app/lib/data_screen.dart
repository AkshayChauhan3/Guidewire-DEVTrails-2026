// ============================================================
// data_screen.dart
// ============================================================
// Shows 4 data cards:
//   1. Weather  → OpenWeatherMap free API
//   2. News     → NewsAPI free tier
//   3. Reddit   → Reddit API (public JSON)
//   4. Activity → User's session activity drop
//
// HOW TO GET FREE API KEYS:
//   Weather: https://openweathermap.org/api (free tier)
//   News:    https://newsapi.org (free tier, 100 req/day)
//   Reddit:  No key needed! Uses public JSON API
//
// 🔧 ADD YOUR API KEYS BELOW
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_state.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {

  // ──────────────────────────────────────────────
  // 🔧 ADD YOUR API KEYS HERE
  // ──────────────────────────────────────────────
  // ignore: constant_identifier_names
  static const String WEATHER_API_KEY = "YOUR_OPENWEATHERMAP_KEY"; // openweathermap.org
  // ignore: constant_identifier_names
  static const String NEWS_API_KEY    = "YOUR_NEWSAPI_KEY";         // newsapi.org

  // ──────────────────────────────────────────────
  // State for each data card
  // ──────────────────────────────────────────────
  Map<String, dynamic>? weatherData;
  List<dynamic> newsItems = [];
  List<dynamic> redditPosts = [];
  bool weatherLoading = true;
  bool newsLoading = true;
  bool redditLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchWeather(),
      _fetchNews(),
      _fetchReddit(),
    ]);
  }

  // ──────────────────────────────────────────────
  // 🌤️ WEATHER
  // GET https://api.openweathermap.org/data/2.5/weather
  // Uses user's city from their profile
  // ──────────────────────────────────────────────
  Future<void> _fetchWeather() async {
    final city = AppState.city.isNotEmpty ? AppState.city : "Mumbai";

    try {
      final response = await http.get(Uri.parse(
        "https://api.openweathermap.org/data/2.5/weather"
        "?q=$city&appid=$WEATHER_API_KEY&units=metric"
      ));

      if (response.statusCode == 200) {
        setState(() {
          weatherData = jsonDecode(response.body);
          weatherLoading = false;
        });
      } else {
        setState(() => weatherLoading = false);
      }
    } catch (e) {
      setState(() => weatherLoading = false);
    }
  }

  // ──────────────────────────────────────────────
  // 📰 NEWS
  // GET https://newsapi.org/v2/everything
  // Searches for news related to user's city
  // ──────────────────────────────────────────────
  Future<void> _fetchNews() async {
    final city = AppState.city.isNotEmpty ? AppState.city : "India";

    try {
      final response = await http.get(Uri.parse(
        "https://newsapi.org/v2/everything"
        "?q=$city+gig+workers+flood+disaster"
        "&sortBy=publishedAt&pageSize=5"
        "&apiKey=$NEWS_API_KEY"
      ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          newsItems = data["articles"] ?? [];
          newsLoading = false;
        });
      } else {
        setState(() => newsLoading = false);
      }
    } catch (e) {
      setState(() => newsLoading = false);
    }
  }

  // ──────────────────────────────────────────────
  // 💬 REDDIT
  // No API key needed! Reddit has a public JSON API
  // GET https://www.reddit.com/r/india/search.json
  // ──────────────────────────────────────────────
  Future<void> _fetchReddit() async {
    final city = AppState.city.isNotEmpty ? AppState.city : "India";

    try {
      final response = await http.get(
        Uri.parse(
          "https://www.reddit.com/r/india/search.json"
          "?q=$city+flood+protest+curfew&sort=new&limit=5"
        ),
        headers: {"User-Agent": "GigShieldApp/1.0"}, // Reddit requires User-Agent
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final posts = data["data"]["children"] as List;
        setState(() {
          redditPosts = posts.map((p) => p["data"]).toList();
          redditLoading = false;
        });
      } else {
        setState(() => redditLoading = false);
      }
    } catch (e) {
      setState(() => redditLoading = false);
    }
  }

  // ──────────────────────────────────────────────
  // Crisis level from weather
  // Based on your README's Crisis Index table
  // ──────────────────────────────────────────────
  Map<String, dynamic> _getCrisisLevel() {
    if (weatherData == null) return {"label": "Unknown", "color": Colors.grey};

    final condition = weatherData!["weather"][0]["main"]?.toLowerCase() ?? "";
    final rain = weatherData!["rain"]?["1h"] ?? 0;

    if (condition.contains("thunderstorm") || rain > 50) {
      return {"label": "EMERGENCY (2×)", "color": Colors.red};
    } else if (condition.contains("rain") || rain > 10) {
      return {"label": "SEVERE (1.5×)", "color": Colors.orange};
    } else if (condition.contains("drizzle") || condition.contains("cloud")) {
      return {"label": "MODERATE (1.25×)", "color": Colors.yellow};
    }
    return {"label": "MILD (1×)", "color": Colors.green};
  }

  @override
  Widget build(BuildContext context) {
    final crisis = _getCrisisLevel();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text("Data", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () {
              setState(() {
                weatherLoading = true;
                newsLoading = true;
                redditLoading = true;
              });
              _fetchAll();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            // ──────────────────────────────────
            // 🌤️ WEATHER CARD
            // ──────────────────────────────────
            _sectionLabel("WEATHER · ${AppState.city.isNotEmpty ? AppState.city : 'Your City'}"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: weatherLoading
                  ? _loadingWidget()
                  : weatherData == null
                      ? _errorWidget("Add your OpenWeatherMap API key in data_screen.dart")
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Temperature
                                Text(
                                  "${weatherData!["main"]["temp"].toInt()}°C",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 44,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                // Weather icon code from OpenWeatherMap
                                Image.network(
                                  "https://openweathermap.org/img/wn/${weatherData!["weather"][0]["icon"]}@2x.png",
                                  width: 64,
                                  errorBuilder: (_, _, _) => const Icon(Icons.cloud, color: Colors.white38, size: 40),
                                ),
                              ],
                            ),
                            Text(
                              weatherData!["weather"][0]["description"].toString().toUpperCase(),
                              style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _weatherChip("Humidity", "${weatherData!["main"]["humidity"]}%"),
                                const SizedBox(width: 8),
                                _weatherChip("Wind", "${weatherData!["wind"]["speed"]} m/s"),
                                const SizedBox(width: 8),
                                _weatherChip("Feels", "${weatherData!["main"]["feels_like"].toInt()}°C"),
                              ],
                            ),
                            const SizedBox(height: 14),
                            // Crisis Index indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: (crisis["color"] as Color).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: (crisis["color"] as Color).withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.flash_on, color: crisis["color"] as Color, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Crisis Index: ${crisis["label"]}",
                                    style: TextStyle(color: crisis["color"] as Color, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),

            const SizedBox(height: 16),

            // ──────────────────────────────────
            // 📰 NEWS CARD
            // ──────────────────────────────────
            _sectionLabel("NEWS"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: newsLoading
                  ? _loadingWidget()
                  : newsItems.isEmpty
                      ? _errorWidget("Add your NewsAPI key in data_screen.dart")
                      : Column(
                          children: newsItems.take(4).map((article) {
                            return _newsItem(
                              article["title"] ?? "No title",
                              article["source"]["name"] ?? "",
                            );
                          }).toList(),
                        ),
            ),

            const SizedBox(height: 16),

            // ──────────────────────────────────
            // 💬 REDDIT SOCIAL DISTRESS CARD
            // ──────────────────────────────────
            _sectionLabel("SOCIAL DISTRESS · REDDIT"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: redditLoading
                  ? _loadingWidget()
                  : redditPosts.isEmpty
                      ? _errorWidget("No Reddit data found for your area")
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Distress score (simplified for demo)
                            Row(
                              children: [
                                const Text("Distress Score", style: TextStyle(color: Colors.white54)),
                                const Spacer(),
                                Text(
                                  redditPosts.length > 3 ? "HIGH" : "LOW",
                                  style: TextStyle(
                                    color: redditPosts.length > 3 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...redditPosts.take(3).map((post) => _redditItem(
                              post["title"] ?? "",
                              post["subreddit_name_prefixed"] ?? "",
                              post["score"]?.toString() ?? "0",
                            )),
                          ],
                        ),
            ),

            const SizedBox(height: 16),

            // ──────────────────────────────────
            // 📉 ACTIVITY DROP CARD
            // This will come from Django session data
            // For now shows demo bars
            // ──────────────────────────────────
            _sectionLabel("ACTIVITY DROP"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Last 7 Days Activity",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  // Simple bar chart — replace with fl_chart for production
                  // 🔗 BACKEND: fetch from GET /api/activity/<phone>/
                  // Each value = hours worked that day
                  _activityBars([6.5, 7.2, 5.8, 8.1, 3.2, 0.5, 0.0]),
                  const SizedBox(height: 12),
                  // Drop indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "⚠️ Activity dropped 90% in last 2 days",
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── Widget helpers ──

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white.withValues(alpha: 0.05),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
  );

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
  );

  Widget _loadingWidget() => const Padding(
    padding: EdgeInsets.all(20),
    child: Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2)),
  );

  Widget _errorWidget(String msg) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(msg, style: const TextStyle(color: Colors.white24, fontSize: 12)),
  );

  Widget _weatherChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text("$label: $value", style: const TextStyle(color: Colors.white60, fontSize: 11)),
  );

  Widget _newsItem(String title, String source) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4, height: 40,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(source, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _redditItem(String title, String sub, String score) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.arrow_upward, color: Colors.orange, size: 14),
        const SizedBox(width: 4),
        Text(score, style: const TextStyle(color: Colors.orange, fontSize: 12)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      ],
    ),
  );

  // Simple activity bar chart
  Widget _activityBars(List<double> hours) {
    final days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final maxH = hours.reduce((a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(hours.length, (i) {
        final h = hours[i];
        final isLow = h < 2;
        return Column(
          children: [
            Text(
              "${h.toStringAsFixed(1)}h",
              style: TextStyle(color: isLow ? Colors.red : Colors.white38, fontSize: 9),
            ),
            const SizedBox(height: 4),
            Container(
              width: 32,
              height: maxH > 0 ? (h / maxH) * 80 + 4 : 4,
              decoration: BoxDecoration(
                color: isLow ? Colors.red.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(days[i], style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        );
      }),
    );
  }
}