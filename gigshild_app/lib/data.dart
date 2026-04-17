import 'api_service.dart';
import 'app_state.dart';

class CityWeatherData {
  const CityWeatherData({
    required this.city,
    required this.region,
    required this.country,
    required this.tempC,
    required this.feelsLikeC,
    required this.humidity,
    required this.windKph,
    required this.condition,
    required this.iconUrl,
    required this.lastUpdated,
  });

  final String city;
  final String region;
  final String country;
  final double? tempC;
  final double? feelsLikeC;
  final int? humidity;
  final double? windKph;
  final String condition;
  final String iconUrl;
  final String lastUpdated;

  factory CityWeatherData.fromMap(Map<String, dynamic> map) {
    final rawIcon = (map["icon"] ?? "").toString();
    final iconUrl = rawIcon.startsWith("//")
        ? "https:$rawIcon"
        : rawIcon.startsWith("http")
        ? rawIcon
        : "";

    return CityWeatherData(
      city: (map["city"] ?? "").toString(),
      region: (map["region"] ?? "").toString(),
      country: (map["country"] ?? "").toString(),
      tempC: _toDouble(map["temp_c"]),
      feelsLikeC: _toDouble(map["feelslike_c"]),
      humidity: _toInt(map["humidity"]),
      windKph: _toDouble(map["wind_kph"]),
      condition: (map["condition"] ?? "").toString(),
      iconUrl: iconUrl,
      lastUpdated: (map["last_updated"] ?? "").toString(),
    );
  }
}

class CityNewsItem {
  const CityNewsItem({
    required this.title,
    required this.source,
    required this.description,
    required this.url,
    required this.publishedAt,
    required this.eventType,
    required this.severity,
  });

  final String title;
  final String source;
  final String description;
  final String url;
  final String publishedAt;
  final String eventType;
  final String severity;

  factory CityNewsItem.fromMap(Map<String, dynamic> map) {
    return CityNewsItem(
      title: (map["title"] ?? "No title").toString(),
      source: (map["source"] ?? "").toString(),
      description: (map["description"] ?? "").toString(),
      url: (map["url"] ?? "").toString(),
      publishedAt: (map["published_at"] ?? "").toString(),
      eventType: (map["event_type"] ?? "").toString(),
      severity: (map["severity"] ?? "").toString(),
    );
  }
}

class CityAlertItem {
  const CityAlertItem({
    required this.id,
    required this.city,
    required this.area,
    required this.eventType,
    required this.severity,
    required this.headline,
    required this.summary,
    required this.source,
    required this.effectiveDate,
    required this.createdAt,
    required this.isActive,
  });

  final int id;
  final String city;
  final String area;
  final String eventType;
  final String severity;
  final String headline;
  final String summary;
  final String source;
  final String effectiveDate;
  final String createdAt;
  final bool isActive;

  factory CityAlertItem.fromMap(Map<String, dynamic> map) {
    return CityAlertItem(
      id: int.tryParse("${map["id"] ?? 0}") ?? 0,
      city: (map["city"] ?? "").toString(),
      area: (map["area"] ?? "").toString(),
      eventType: (map["event_type"] ?? "").toString(),
      severity: (map["severity"] ?? "").toString(),
      headline: (map["headline"] ?? "").toString(),
      summary: (map["summary"] ?? "").toString(),
      source: (map["source"] ?? "").toString(),
      effectiveDate: (map["effective_date"] ?? "").toString(),
      createdAt: (map["created_at"] ?? "").toString(),
      isActive: map["is_active"] == true,
    );
  }
}

class CityDataBundle {
  const CityDataBundle({
    required this.city,
    required this.weather,
    required this.news,
    required this.activeEvents,
    required this.errors,
  });

  final String city;
  final CityWeatherData? weather;
  final List<CityNewsItem> news;
  final List<CityAlertItem> activeEvents;
  final Map<String, dynamic> errors;

  bool get hasAnyContent =>
      weather != null || news.isNotEmpty || activeEvents.isNotEmpty;

  factory CityDataBundle.fromMap(Map<String, dynamic> map) {
    final weatherMap = map["weather"];
    final rawNews = map["news"] is List ? map["news"] as List : const [];
    final rawEvents = map["active_events"] is List
        ? map["active_events"] as List
        : const [];

    return CityDataBundle(
      city: (map["city"] ?? AppState.city).toString(),
      weather: weatherMap is Map<String, dynamic>
          ? CityWeatherData.fromMap(weatherMap)
          : null,
      news: rawNews
          .whereType<Map<String, dynamic>>()
          .map(CityNewsItem.fromMap)
          .toList(),
      activeEvents: rawEvents
          .whereType<Map<String, dynamic>>()
          .map(CityAlertItem.fromMap)
          .toList(),
      errors: map["errors"] is Map<String, dynamic>
          ? Map<String, dynamic>.from(map["errors"])
          : {},
    );
  }
}

class DataRepository {
  const DataRepository();

  Future<CityDataBundle> fetchCurrentCityData() async {
    final result = await ApiService.getCityData(
      phone: AppState.phone,
      city: AppState.city,
    );

    if (result["success"] != true) {
      throw Exception(result["message"] ?? "Unable to fetch city data");
    }

    final data = result["data"];
    if (data is! Map<String, dynamic>) {
      throw Exception("Invalid city data response");
    }

    return CityDataBundle.fromMap(data);
  }
}

double? _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse("$value");
}

int? _toInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse("$value");
}
