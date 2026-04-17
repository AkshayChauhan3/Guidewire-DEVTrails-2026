import 'dart:async';

import 'package:flutter/material.dart';
import 'app_state.dart';
import 'data.dart';
import 'ui_kit.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  final DataRepository _repository = const DataRepository();
  CityDataBundle? _cityData;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _loadData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) {
      return;
    }

    setState(() {
      if (silent) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
        _loadError = null;
      }
    });

    try {
      final cityData = await _repository.fetchCurrentCityData();
      if (!mounted) {
        return;
      }
      setState(() {
        _cityData = cityData;
        _isLoading = false;
        _isRefreshing = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = e.toString().replaceFirst("Exception: ", "");
        _isLoading = false;
        _isRefreshing = false;
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
      appBar: AppBar(
        title: const Text(
          "Alerts",
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
            icon: const Icon(Icons.refresh, color: AppUi.muted),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: AppUi.pagePadding,
          children: [
            AppUi.sectionLabel(
              "Live risk signals · ${_cityData?.city.isNotEmpty == true ? _cityData!.city : (AppState.city.isNotEmpty ? AppState.city : 'your city')}",
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppUi.panel(),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "${(_cityData!.weather!.tempC ?? 0).round()}°C",
                                  style: const TextStyle(
                                    color: AppUi.text,
                                    fontSize: 44,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (_cityData!.weather!.iconUrl.isNotEmpty)
                              Image.network(
                                _cityData!.weather!.iconUrl,
                                width: 56,
                                height: 56,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.cloud,
                                  color: AppUi.muted,
                                  size: 40,
                                ),
                              )
                            else
                              const Icon(
                                Icons.cloud,
                                color: AppUi.muted,
                                size: 40,
                              ),
                          ],
                        ),
                        Text(
                          _cityData!.weather!.condition.toUpperCase(),
                          style: const TextStyle(
                            color: AppUi.muted,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _weatherChip(
                              "Humidity",
                              "${_cityData!.weather!.humidity ?? '--'}%",
                            ),
                            _weatherChip(
                              "Wind",
                              "${_cityData!.weather!.windKph?.round() ?? '--'} km/h",
                            ),
                            _weatherChip(
                              "Feels",
                              "${(_cityData!.weather!.feelsLikeC ?? 0).round()}°C",
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          "Local weather, news, and area signals are combined here so you can see what is affecting work today.",
                          style: TextStyle(color: AppUi.muted, height: 1.45),
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
                              color: AppUi.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),

            const SizedBox(height: 16),

            AppUi.sectionLabel("Active demo alerts"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppUi.panel(),
              child: _isLoading
                  ? _loadingWidget()
                  : _cityData == null
                  ? _errorWidget(_loadError ?? "Unable to load city alerts")
                  : _cityData!.activeEvents.isEmpty
                  ? _errorWidget(
                      "No active demo alerts for ${_cityData!.city.isNotEmpty ? _cityData!.city : (AppState.city.isNotEmpty ? AppState.city : 'your city')}",
                    )
                  : Column(
                      children: _cityData!.activeEvents
                          .take(4)
                          .map((alert) => _alertItem(alert))
                          .toList(),
                    ),
            ),

            const SizedBox(height: 16),

            AppUi.sectionLabel("News and disruption feed"),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppUi.panel(),
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

  Widget _loadingWidget() => const Padding(
    padding: EdgeInsets.all(20),
    child: Center(
      child: CircularProgressIndicator(color: AppUi.muted, strokeWidth: 2),
    ),
  );

  Widget _errorWidget(String msg) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(
      msg,
      style: const TextStyle(color: AppUi.muted, fontSize: 12),
    ),
  );

  Widget _weatherChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      "$label: $value",
      style: const TextStyle(color: AppUi.text, fontSize: 11),
    ),
  );

  Widget _alertItem(CityAlertItem alert) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppUi.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                alert.severity.isEmpty ? "ALERT" : alert.severity.toUpperCase(),
                style: const TextStyle(
                  color: AppUi.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            Text(
              alert.createdAt.isNotEmpty
                  ? alert.createdAt
                  : (alert.effectiveDate.isEmpty
                        ? alert.source
                        : alert.effectiveDate),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          alert.headline,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        if (alert.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            alert.summary,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _newsTag(alert.city.isEmpty ? "city" : alert.city),
            _newsTag(alert.area.isEmpty ? "area" : alert.area),
            _newsTag(alert.eventType.isEmpty ? "demo" : alert.eventType),
          ],
        ),
      ],
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
