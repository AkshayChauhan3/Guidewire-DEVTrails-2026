import 'package:flutter/material.dart';
import 'app_state.dart';
import 'data.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  final DataRepository _repository = const DataRepository();
  CityDataBundle? _cityData;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final cityData = await _repository.fetchCurrentCityData();
      if (!mounted) {
        return;
      }
      setState(() {
        _cityData = cityData;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = e.toString().replaceFirst("Exception: ", "");
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _getCrisisLevel() {
    final weather = _cityData?.weather;
    if (weather == null) {
      return {"label": "Unknown", "color": Colors.grey};
    }

    final condition = weather.condition.toLowerCase();
    final temp = weather.tempC ?? 0;

    if (condition.contains("thunder") || condition.contains("storm")) {
      return {"label": "EMERGENCY (2×)", "color": Colors.red};
    } else if (condition.contains("rain") ||
        condition.contains("flood") ||
        temp >= 40) {
      return {"label": "SEVERE (1.5×)", "color": Colors.orange};
    } else if (condition.contains("drizzle") ||
        condition.contains("cloud") ||
        temp >= 34) {
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
        title: const Text(
          "City Alerts",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel(
              "LIVE RISK SIGNALS · ${_cityData?.city.isNotEmpty == true ? _cityData!.city : (AppState.city.isNotEmpty ? AppState.city : 'Your City')}",
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: _isLoading
                  ? _loadingWidget()
                  : _cityData?.weather == null
                  ? _errorWidget(
                      _loadError ??
                          _cityData?.errors["weather"]?.toString() ??
                          "Weather data unavailable",
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "${(_cityData!.weather!.tempC ?? 0).round()}°C",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_cityData!.weather!.iconUrl.isNotEmpty)
                              Image.network(
                                _cityData!.weather!.iconUrl,
                                width: 64,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.cloud,
                                  color: Colors.white38,
                                  size: 40,
                                ),
                              )
                            else
                              const Icon(
                                Icons.cloud,
                                color: Colors.white38,
                                size: 40,
                              ),
                          ],
                        ),
                        Text(
                          _cityData!.weather!.condition.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _weatherChip(
                              "Humidity",
                              "${_cityData!.weather!.humidity ?? '--'}%",
                            ),
                            const SizedBox(width: 8),
                            _weatherChip(
                              "Wind",
                              "${_cityData!.weather!.windKph?.round() ?? '--'} km/h",
                            ),
                            const SizedBox(width: 8),
                            _weatherChip(
                              "Feels",
                              "${(_cityData!.weather!.feelsLikeC ?? 0).round()}°C",
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          "GigShield uses local weather risk to prepare automatic protection for workers on the road.",
                          style: TextStyle(color: Colors.white60, height: 1.45),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: (crisis["color"] as Color).withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (crisis["color"] as Color).withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flash_on,
                                color: crisis["color"] as Color,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "Crisis Index: ${crisis["label"]}",
                                style: TextStyle(
                                  color: crisis["color"] as Color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_cityData!.weather!.lastUpdated.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            "Updated ${_cityData!.weather!.lastUpdated}",
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),

            const SizedBox(height: 16),

            _sectionLabel("NEWS AND DISRUPTION FEED"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: _isLoading
                  ? _loadingWidget()
                  : _cityData == null
                  ? _errorWidget(_loadError ?? "Unable to load city data")
                  : _cityData!.news.isEmpty
                  ? _errorWidget(
                      _cityData!.errors["news"]?.toString() ??
                          "No current city news found",
                    )
                  : Column(
                      children: _cityData!.news.take(6).map((article) {
                        return _newsItem(article);
                      }).toList(),
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
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _loadingWidget() => const Padding(
    padding: EdgeInsets.all(20),
    child: Center(
      child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
    ),
  );

  Widget _errorWidget(String msg) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(
      msg,
      style: const TextStyle(color: Colors.white24, fontSize: 12),
    ),
  );

  Widget _weatherChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      "$label: $value",
      style: const TextStyle(color: Colors.white60, fontSize: 11),
    ),
  );

  Widget _newsItem(CityNewsItem article) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 64,
          decoration: BoxDecoration(
            color: _severityColor(article.severity),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.title,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (article.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  article.description,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Text(
                article.publishedAt.isEmpty
                    ? article.source
                    : "${article.source}  •  ${article.publishedAt}",
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _newsTag(
                    article.eventType.isEmpty ? "alert" : article.eventType,
                  ),
                  _newsTag(
                    article.severity.isEmpty ? "monitor" : article.severity,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _newsTag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(color: Colors.white60, fontSize: 10),
    ),
  );

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case "emergency":
        return Colors.redAccent;
      case "severe":
        return Colors.orangeAccent;
      case "moderate":
        return Colors.amber;
      default:
        return Colors.white24;
    }
  }
}
