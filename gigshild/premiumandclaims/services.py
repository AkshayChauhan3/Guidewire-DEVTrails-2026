from __future__ import annotations

import json
import math
from collections import Counter
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP
from hashlib import sha1
from urllib import error, parse, request

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from registor_and_login.models import DeliveryPartner
from sessions.models import SessionHistory

from .models import ClaimRecord, DemoNewsEvent, PremiumAccount, PremiumLedger, WeeklyPremiumSnapshot


TWOPLACES = Decimal("0.01")
TESTING_BONUS = Decimal("5000.00")
REGION_PREMIUM = {
    "north": Decimal("0.068"),
    "east": Decimal("0.064"),
    "west": Decimal("0.061"),
    "south": Decimal("0.065"),
}
CATEGORY_MULTIPLIER = {
    "full_time": Decimal("1.0"),
    "part_time": Decimal("0.8"),
    "weekend": Decimal("0.7"),
    "casual": Decimal("0.5"),
}
CRISIS_INDEX = {
    "mild": Decimal("1.0"),
    "moderate": Decimal("1.25"),
    "severe": Decimal("1.5"),
    "emergency": Decimal("2.0"),
}
NORTH_CITIES = {"delhi", "chandigarh", "jaipur", "lucknow", "dehradun", "shimla"}
SOUTH_CITIES = {"bengaluru", "bangalore", "chennai", "hyderabad", "kochi", "coimbatore"}
EAST_CITIES = {"kolkata", "bhubaneswar", "patna", "ranchi", "guwahati"}

# City to coordinates mapping for fallback when API is unavailable
CITY_COORDINATES = {
    "delhi": (28.7041, 77.1025),
    "chandigarh": (30.7333, 76.7794),
    "jaipur": (26.9124, 75.7873),
    "lucknow": (26.8467, 80.9462),
    "dehradun": (30.3165, 78.0322),
    "shimla": (31.7771, 77.1838),
    "bengaluru": (12.9716, 77.5946),
    "bangalore": (12.9716, 77.5946),
    "chennai": (13.0827, 80.2707),
    "hyderabad": (17.3850, 78.4867),
    "kochi": (9.9312, 76.2673),
    "coimbatore": (11.0081, 76.9877),
    "kolkata": (22.5726, 88.3639),
    "bhubaneswar": (20.2961, 85.8245),
    "patna": (25.5941, 85.1376),
    "ranchi": (23.3441, 85.3096),
    "guwahati": (26.1445, 91.7362),
    "mumbai": (19.0760, 72.8777),
    "pune": (18.5204, 73.8567),
    "ahmedabad": (23.0225, 72.5714),
    "vadodara": (22.3072, 73.1812),
    "surat": (21.1458, 72.8336),
    "indore": (22.7196, 75.8577),
    "nagpur": (21.1458, 79.0882),
    "ludhiana": (30.9010, 75.8573),
    "kanpur": (26.4499, 80.3319),
}

WEATHER_API_KEY = "a8732e24e79b406fa46135338260304"
NEWS_API_KEY = "a46c74aa3af14d13bdb56789d2c56bfb"
AUTO_CLAIM_WEATHER_THRESHOLD = 0.58
MAX_NEWS_SIGNALS = 8


def _quantize(value: Decimal | int | float | str) -> Decimal:
    return Decimal(str(value)).quantize(TWOPLACES, rounding=ROUND_HALF_UP)


def _safe_json(url: str) -> dict:
    req = request.Request(url)
    with request.urlopen(req, timeout=10) as response:
        payload = response.read().decode("utf-8")
        return json.loads(payload) if payload else {}


def _slugify_text(value: str) -> str:
    cleaned = "".join(ch.lower() if ch.isalnum() else "-" for ch in (value or "").strip())
    collapsed = "-".join(part for part in cleaned.split("-") if part)
    return collapsed[:80]


def _build_event_signature(*parts: object) -> str:
    joined = "|".join(str(part or "").strip().lower() for part in parts)
    digest = sha1(joined.encode("utf-8")).hexdigest()[:16]
    return f"{_slugify_text(joined)[:72]}-{digest}"


def map_city_to_region(city: str) -> str:
    normalized = (city or "").strip().lower()
    if normalized in NORTH_CITIES:
        return "north"
    if normalized in SOUTH_CITIES:
        return "south"
    if normalized in EAST_CITIES:
        return "east"
    return "west"


def get_city_coordinates(city: str) -> tuple[float, float] | None:
    """Get latitude and longitude for a city from predefined mapping."""
    normalized = (city or "").strip().lower()
    return CITY_COORDINATES.get(normalized)


def ensure_premium_account(partner: DeliveryPartner) -> PremiumAccount:
    # Get coordinates for partner's city
    partner_city = (partner.city or "Mumbai").strip()
    coords = get_city_coordinates(partner_city)
    
    account, created = PremiumAccount.objects.get_or_create(
        partner=partner,
        defaults={
            "wallet_balance": TESTING_BONUS,
            "testing_bonus": TESTING_BONUS,
            "city": partner.city,
            "area": partner.area,
            "pincode": partner.pincode,
            "region": map_city_to_region(partner.city),
            "latitude": coords[0] if coords else None,
            "longitude": coords[1] if coords else None,
        },
    )

    dirty_fields: list[str] = []
    if not created:
        if account.wallet_balance is None:
            account.wallet_balance = Decimal("0.00")
            dirty_fields.append("wallet_balance")
        if account.testing_bonus < TESTING_BONUS:
            delta = TESTING_BONUS - account.testing_bonus
            account.testing_bonus = TESTING_BONUS
            account.wallet_balance = _quantize(account.wallet_balance + delta)
            dirty_fields.extend(["testing_bonus", "wallet_balance"])
        if not account.city and partner.city:
            account.city = partner.city
            dirty_fields.append("city")
        if not account.area and partner.area:
            account.area = partner.area
            dirty_fields.append("area")
        if not account.pincode and partner.pincode:
            account.pincode = partner.pincode
            dirty_fields.append("pincode")
        region = map_city_to_region(account.city or partner.city)
        if account.region != region:
            account.region = region
            dirty_fields.append("region")
        # Auto-set coordinates if missing and city is available
        city_for_coords = account.city or partner.city or "Mumbai"
        if (account.latitude is None or account.longitude is None) and city_for_coords:
            coords = get_city_coordinates(city_for_coords)
            if coords:
                if account.latitude is None:
                    account.latitude = coords[0]
                    dirty_fields.append("latitude")
                if account.longitude is None:
                    account.longitude = coords[1]
                    dirty_fields.append("longitude")
        if dirty_fields:
            account.save(update_fields=[*sorted(set(dirty_fields)), "updated_at"])

    if not account.ledger_entries.filter(entry_type="testing_bonus").exists():
        PremiumLedger.objects.create(
            account=account,
            entry_type="testing_bonus",
            amount=TESTING_BONUS,
            direction="credit",
            status="success",
            reference=f"bonus-{partner.id}",
            description="Testing phase wallet credit",
            metadata={"phase": "demo", "auto_created": True},
        )

    seed_default_demo_event(account.city or partner.city)
    return account


def seed_default_demo_event(city: str):
    city = (city or "Mumbai").strip() or "Mumbai"
    headline = f"{city} flood watch impacts delivery routes"
    exists = DemoNewsEvent.objects.filter(city__iexact=city, headline__iexact=headline).exists()
    if exists:
        return

    DemoNewsEvent.objects.create(
        city=city,
        area="Central Zone",
        event_type="flood",
        severity="severe",
        headline=headline,
        summary="Demo starter event so every new user can see automatic protection trigger during the testing phase.",
        effective_date=timezone.localdate(),
        is_active=True,
        source="system-demo-seed",
    )


def sync_account_location(
    account: PremiumAccount,
    *,
    city: str | None = None,
    area: str | None = None,
    pincode: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
) -> PremiumAccount:
    dirty_fields: list[str] = []
    if city:
        account.city = city
        account.region = map_city_to_region(city)
        dirty_fields.extend(["city", "region"])
        # Auto-populate coordinates from city if not explicitly provided
        if latitude is None and longitude is None:
            coords = get_city_coordinates(city)
            if coords:
                latitude, longitude = coords
    if area:
        account.area = area
        dirty_fields.append("area")
    if pincode:
        account.pincode = pincode
        dirty_fields.append("pincode")
    if latitude is not None:
        account.latitude = latitude
        dirty_fields.append("latitude")
    if longitude is not None:
        account.longitude = longitude
        dirty_fields.append("longitude")
    if dirty_fields:
        account.save(update_fields=[*sorted(set(dirty_fields)), "updated_at"])
    return account


def fetch_weather_snapshot(city: str) -> dict:
    city = (city or "Mumbai").strip() or "Mumbai"
    try:
        query = parse.urlencode({"key": WEATHER_API_KEY, "q": city, "aqi": "no"})
        data = _safe_json(f"http://api.weatherapi.com/v1/current.json?{query}")
        current = data.get("current") or {}
        location = data.get("location") or {}
        rainfall = current.get("precip_mm") or 0
        weather = {
            "city": location.get("name") or city,
            "region_label": location.get("region") or "",
            "country": location.get("country") or "",
            "temperature": float(current.get("temp_c") or 0),
            "humidity": int(current.get("humidity") or 0),
            "wind_speed": float(current.get("wind_kph") or 0),
            "rainfall": float(rainfall),
            "condition": ((current.get("condition") or {}).get("text") or "").lower(),
            "last_updated": current.get("last_updated") or "",
            "source": "weatherapi",
        }
    except (error.URLError, error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError):
        weather = {
            "city": city,
            "region_label": "",
            "country": "India",
            "temperature": 31.0,
            "humidity": 72,
            "wind_speed": 16.0,
            "rainfall": 18.0,
            "condition": "demo-weather",
            "last_updated": timezone.now().isoformat(),
            "source": "demo-fallback",
        }

    weather["weather_score"] = calculate_weather_score(weather)
    return weather


def calculate_weather_score(weather: dict) -> float:
    rainfall_score = min(float(weather.get("rainfall", 0)) / 120.0, 1.0)
    temperature = float(weather.get("temperature", 0))
    humidity = float(weather.get("humidity", 0))
    wind_speed = float(weather.get("wind_speed", 0))

    heat_score = 0.0
    if temperature >= 32:
        heat_score = min((temperature - 32) / 12.0, 1.0)
    humidity_score = min(max(humidity - 60, 0) / 40.0, 1.0)
    wind_score = min(wind_speed / 60.0, 1.0)

    condition = (weather.get("condition") or "").lower()
    keyword_boost = 0.0
    for keyword, boost in (
        ("flood", 0.35),
        ("storm", 0.30),
        ("thunder", 0.25),
        ("rain", 0.18),
        ("heat", 0.20),
    ):
        if keyword in condition:
            keyword_boost = max(keyword_boost, boost)

    score = (
        0.42 * rainfall_score
        + 0.24 * heat_score
        + 0.14 * humidity_score
        + 0.10 * wind_score
        + keyword_boost
    )
    return round(min(score, 1.0), 4)


def fetch_news_signals(city: str) -> list[dict]:
    city = (city or "Mumbai").strip() or "Mumbai"
    signals: list[dict] = []
    seen_keys: set[tuple[str, str]] = set()

    demo_events = DemoNewsEvent.objects.filter(
        city__iexact=city,
        is_active=True,
        effective_date__lte=timezone.localdate(),
    ).order_by("-effective_date", "-id")
    for event in demo_events[:5]:
        key = (event.headline.strip().lower(), event.source.strip().lower())
        if key in seen_keys:
            continue
        seen_keys.add(key)
        signals.append(
            {
                "title": event.headline,
                "source": event.source,
                "description": event.summary,
                "event_type": event.event_type,
                "severity": event.severity,
                "published_at": event.effective_date.isoformat(),
                "event_location": {
                    "latitude": event.event_latitude,
                    "longitude": event.event_longitude,
                },
                "url": "",
                "signature": _build_event_signature(
                    city,
                    event.event_type,
                    event.source,
                    event.headline,
                    event.effective_date,
                ),
            }
        )

    try:
        query_text = f"{city} flood OR heavy rain OR strike OR protest OR heatwave OR disaster"
        query = parse.urlencode(
            {
                "q": query_text,
                "sortBy": "publishedAt",
                "pageSize": MAX_NEWS_SIGNALS,
                "language": "en",
                "apiKey": NEWS_API_KEY,
            }
        )
        data = _safe_json(f"https://newsapi.org/v2/everything?{query}")
        for article in (data.get("articles") or [])[:MAX_NEWS_SIGNALS]:
            title = article.get("title") or ""
            description = article.get("description") or ""
            source = (article.get("source") or {}).get("name") or "newsapi"
            key = (title.strip().lower(), source.strip().lower())
            if not title or key in seen_keys:
                continue
            seen_keys.add(key)
            signals.append(
                {
                    "title": title,
                    "source": source,
                    "description": description,
                    "event_type": infer_event_type(f"{title} {description}"),
                    "severity": infer_severity(f"{title} {description}"),
                    "published_at": article.get("publishedAt"),
                    "event_location": {"latitude": None, "longitude": None},
                    "url": article.get("url") or "",
                    "signature": _build_event_signature(
                        city,
                        infer_event_type(f"{title} {description}"),
                        source,
                        title,
                        article.get("publishedAt"),
                    ),
                }
            )
    except (error.URLError, error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError):
        pass

    if signals:
        return signals[:MAX_NEWS_SIGNALS]

    return [
        {
            "title": f"{city} sees high rainfall warning for delivery workers",
            "source": "demo-fallback",
            "description": "Fallback demo news generated for claim scoring.",
            "event_type": "high_rain",
            "severity": "moderate",
            "published_at": timezone.now().isoformat(),
            "event_location": {"latitude": None, "longitude": None},
            "url": "",
            "signature": _build_event_signature(
                city,
                "high_rain",
                "demo-fallback",
                "high rainfall warning for delivery workers",
                timezone.localdate(),
            ),
        }
    ]


def infer_event_type(text: str) -> str:
    normalized = (text or "").lower()
    mapping = [
        ("flood", "flood"),
        ("rain", "high_rain"),
        ("heat", "high_temperature"),
        ("temperature", "high_temperature"),
        ("strike", "strike"),
        ("protest", "protest"),
        ("curfew", "curfew"),
        ("disaster", "disaster"),
    ]
    for keyword, event_type in mapping:
        if keyword in normalized:
            return event_type
    return "disaster"


def infer_severity(text: str) -> str:
    normalized = (text or "").lower()
    if any(word in normalized for word in ["emergency", "evacuation", "shutdown"]):
        return "emergency"
    if any(word in normalized for word in ["severe", "extreme", "flood", "curfew"]):
        return "severe"
    if any(word in normalized for word in ["heavy", "high", "warning", "strike", "protest"]):
        return "moderate"
    return "mild"


def calculate_news_confidence(news_items: list[dict]) -> tuple[float, str, str]:
    if not news_items:
        return 0.0, "disaster", "mild"

    severity_weights = {"mild": 0.40, "moderate": 0.65, "severe": 0.82, "emergency": 0.95}
    event_counter = Counter(item.get("event_type") or "disaster" for item in news_items)
    event_type = event_counter.most_common(1)[0][0]
    severity = max(
        (item.get("severity") or "mild" for item in news_items),
        key=lambda value: severity_weights.get(value, 0.40),
    )
    confidence = max(severity_weights.get(item.get("severity") or "mild", 0.40) for item in news_items[:3])
    if len(news_items) > 1:
        confidence = min(confidence + 0.05, 1.0)
    return round(confidence, 4), event_type, severity


def haversine_distance_km(lat1: float | None, lon1: float | None, lat2: float | None, lon2: float | None) -> float:
    if None in (lat1, lon1, lat2, lon2):
        return 9999.0
    radius = 6371.0
    phi1 = math.radians(float(lat1))
    phi2 = math.radians(float(lat2))
    delta_phi = math.radians(float(lat2) - float(lat1))
    delta_lambda = math.radians(float(lon2) - float(lon1))

    a = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    return 2 * radius * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def calculate_location_match(account: PremiumAccount, news_items: list[dict]) -> tuple[float, float | None]:
    distances = []
    for item in news_items:
        location = item.get("event_location") or {}
        distance = haversine_distance_km(
            account.latitude,
            account.longitude,
            location.get("latitude"),
            location.get("longitude"),
        )
        if distance < 9999:
            distances.append(distance)

    if distances:
        best_distance = min(distances)
        
        # ✅ Optimized gradual location scoring - NEVER reject based on distance
        # - Perfect: 0-5km = 1.0
        # - Good: 5-15km = 0.8-0.4
        # - Acceptable: 15-30km = 0.4-0.2
        # - Far: 30km+ = 0.2 (always credit for events with coordinates)
        if best_distance <= 5:
            location_match = 1.0
        elif best_distance <= 15:
            location_match = 1.0 - ((best_distance - 5) / 25.0)
        elif best_distance <= 30:
            location_match = 0.4 - ((best_distance - 15) / 75.0)
        else:
            location_match = 0.2
        
        return round(max(0.2, location_match), 4), round(best_distance, 2)

    if news_items and account.city:
        # City-level match gets 0.6 (reasonable credit)
        return 0.6, None
    return 0.0, None


def _history_range(partner: DeliveryPartner, days: int, until_date=None):
    until_date = until_date or timezone.localdate()
    start_date = until_date - timedelta(days=days - 1)
    return SessionHistory.objects.filter(
        partner=partner,
        history_date__range=(start_date, until_date),
    ).order_by("history_date")


def calculate_weekly_metrics(partner: DeliveryPartner, until_date=None) -> dict:
    until_date = until_date or timezone.localdate()
    histories = list(_history_range(partner, 7, until_date))

    weekly_income = sum((history.total_earned_amount for history in histories), Decimal("0.00"))
    total_hours = sum((history.total_working_hours for history in histories), Decimal("0.00"))
    weekend_hours = sum(
        (history.total_working_hours for history in histories if history.history_date.weekday() >= 5),
        Decimal("0.00"),
    )

    category = "casual"
    if total_hours >= Decimal("35.00"):
        category = "full_time"
    elif total_hours >= Decimal("15.00"):
        category = "part_time"
    elif total_hours > 0 and (weekend_hours / total_hours) > Decimal("0.60"):
        category = "weekend"

    return {
        "weekly_income": _quantize(weekly_income),
        "total_hours": _quantize(total_hours),
        "weekend_hours": _quantize(weekend_hours),
        "category": category,
        "week_start": until_date - timedelta(days=6),
        "week_end": until_date,
    }


def calculate_activity_drop(partner: DeliveryPartner, today=None) -> tuple[float, Decimal, Decimal]:
    today = today or timezone.localdate()
    month_histories = list(_history_range(partner, 30, today))
    if not month_histories:
        return 0.0, Decimal("0.00"), Decimal("0.00")

    total_income = sum((history.total_earned_amount for history in month_histories), Decimal("0.00"))
    avg_orders = (total_income / Decimal(max(len(month_histories), 1))).quantize(TWOPLACES)
    today_history = next((history for history in month_histories if history.history_date == today), None)
    today_orders = today_history.total_earned_amount if today_history else Decimal("0.00")

    if avg_orders <= 0:
        return 0.0, avg_orders, today_orders

    activity_drop = 1 - float(today_orders / avg_orders)
    return round(max(0.0, min(activity_drop, 1.0)), 4), avg_orders, today_orders


def calculate_average_income_per_hour(partner: DeliveryPartner, today=None) -> Decimal:
    today = today or timezone.localdate()
    histories = list(_history_range(partner, 30, today))
    monthly_income = sum((history.total_earned_amount for history in histories), Decimal("0.00"))
    total_hours = sum((history.total_working_hours for history in histories), Decimal("0.00"))
    if total_hours <= 0:
        return Decimal("120.00")
    return _quantize(monthly_income / total_hours)


def build_weather_alert(weather: dict) -> dict | None:
    score = float(weather.get("weather_score") or 0.0)
    rainfall = float(weather.get("rainfall") or 0.0)
    temperature = float(weather.get("temperature") or 0.0)
    condition = (weather.get("condition") or "").lower()
    if score < AUTO_CLAIM_WEATHER_THRESHOLD and rainfall < 25 and temperature < 40:
        return None

    if "storm" in condition or "thunder" in condition:
        event_type = "disaster"
        severity = "emergency"
        headline = f"{weather.get('city') or 'City'} storm alert may disrupt worker safety"
    elif rainfall >= 25 or "flood" in condition or "rain" in condition:
        event_type = "flood" if rainfall >= 40 or "flood" in condition else "high_rain"
        severity = "severe" if rainfall >= 40 or "flood" in condition else "moderate"
        headline = f"{weather.get('city') or 'City'} rain alert flagged for delivery partners"
    else:
        event_type = "high_temperature"
        severity = "severe" if temperature >= 43 else "moderate"
        headline = f"{weather.get('city') or 'City'} heat alert flagged for gig workers"

    return {
        "title": headline,
        "source": weather.get("source") or "weatherapi",
        "description": (
            f"Weather API detected risk conditions: {condition or 'weather alert'}, "
            f"{rainfall} mm rain, {temperature}°C, score {score}."
        ),
        "event_type": event_type,
        "severity": severity,
        "published_at": weather.get("last_updated") or timezone.now().isoformat(),
        "event_location": {"latitude": None, "longitude": None},
        "url": "",
        "signature": _build_event_signature(
            weather.get("city"),
            event_type,
            weather.get("source"),
            headline,
            weather.get("last_updated") or timezone.localdate(),
        ),
    }


def _should_auto_create_claim(signal: dict, weather: dict) -> bool:
    severity = signal.get("severity") or "mild"
    source = (signal.get("source") or "").lower()
    if source in {"demo-generator", "system-demo-seed", "weatherapi", "demo-fallback"}:
        return True
    if severity in {"severe", "emergency"}:
        return True
    return float(weather.get("weather_score") or 0.0) >= AUTO_CLAIM_WEATHER_THRESHOLD


def auto_generate_claims_for_partner(
    partner: DeliveryPartner,
    *,
    latitude: float | None = None,
    longitude: float | None = None,
    city: str | None = None,
) -> list[ClaimRecord]:
    account = ensure_premium_account(partner)
    sync_account_location(account, city=city, latitude=latitude, longitude=longitude)

    weather = fetch_weather_snapshot(account.city or partner.city)
    news_items = fetch_news_signals(account.city or partner.city)
    candidates = [item for item in news_items if _should_auto_create_claim(item, weather)]

    weather_alert = build_weather_alert(weather)
    if weather_alert is not None:
        candidates.insert(0, weather_alert)

    created_claims: list[ClaimRecord] = []
    for signal in candidates[:3]:
        signature = (signal.get("signature") or "").strip()
        if not signature:
            continue
        exists = ClaimRecord.objects.filter(
            partner=partner,
            auto_created=True,
            event_signature=signature,
        ).exists()
        if exists:
            continue
        created_claims.append(
            evaluate_claim(
                partner,
                latitude=latitude,
                longitude=longitude,
                city=city,
                trigger_signal=signal,
                auto_created=True,
                event_signature=signature,
                trigger_source=(signal.get("source") or "system")[:32],
                trigger_title=(signal.get("title") or "")[:255],
            )
        )

    return created_claims


@transaction.atomic
def calculate_or_collect_weekly_premium(
    partner: DeliveryPartner,
    *,
    collect: bool = False,
    today=None,
) -> dict:
    account = ensure_premium_account(partner)
    today = today or timezone.localdate()
    metrics = calculate_weekly_metrics(partner, today)
    weather = fetch_weather_snapshot(account.city or partner.city)

    region = account.region or map_city_to_region(account.city or partner.city)
    region_rate = REGION_PREMIUM[region]
    category_multiplier = CATEGORY_MULTIPLIER[metrics["category"]]
    weather_multiplier = 1 + (Decimal(str(weather["weather_score"])) * Decimal("0.5"))
    premium_amount = _quantize(
        metrics["weekly_income"] * region_rate * category_multiplier * weather_multiplier
    )

    snapshot, _ = WeeklyPremiumSnapshot.objects.update_or_create(
        partner=partner,
        week_start=metrics["week_start"],
        defaults={
            "week_end": metrics["week_end"],
            "weekly_income": metrics["weekly_income"],
            "total_hours": metrics["total_hours"],
            "weekend_hours": metrics["weekend_hours"],
            "category": metrics["category"],
            "region": region,
            "weather_score": weather["weather_score"],
            "weather_multiplier": float(weather_multiplier),
            "premium_amount": premium_amount,
            "deducted_on": today if collect else None,
        },
    )

    payment_status = "preview"
    if collect and premium_amount > 0:
        account.wallet_balance = _quantize(account.wallet_balance - premium_amount)
        account.total_premium_paid = _quantize(account.total_premium_paid + premium_amount)
        account.save(update_fields=["wallet_balance", "total_premium_paid", "updated_at"])
        PremiumLedger.objects.create(
            account=account,
            entry_type="premium_debit",
            amount=premium_amount,
            direction="debit",
            status="success",
            reference=f"premium-{snapshot.id}",
            description=f"Weekly premium deducted for week of {metrics['week_start']}",
            metadata={"week_start": metrics["week_start"].isoformat()},
        )
        payment_status = "debited"

    return {
        "account": account,
        "snapshot": snapshot,
        "weather": weather,
        "payment_status": payment_status,
        "region_rate": float(region_rate),
        "category_multiplier": float(category_multiplier),
    }


@transaction.atomic
def evaluate_claim(
    partner: DeliveryPartner,
    *,
    latitude: float | None = None,
    longitude: float | None = None,
    city: str | None = None,
    notification_match: bool = True,
    cell_tower_verified: bool = True,
    motion_pattern_valid: bool = True,
    trigger_signal: dict | None = None,
    auto_created: bool = False,
    event_signature: str = "",
    trigger_source: str = "",
    trigger_title: str = "",
) -> ClaimRecord:
    account = ensure_premium_account(partner)
    sync_account_location(account, city=city, latitude=latitude, longitude=longitude)

    weather = fetch_weather_snapshot(account.city or partner.city)
    news_items = fetch_news_signals(account.city or partner.city)
    scoring_items = [trigger_signal] if trigger_signal else news_items
    news_confidence, event_type, severity = calculate_news_confidence(scoring_items)
    location_match, distance = calculate_location_match(account, scoring_items)
    activity_drop, avg_orders, today_orders = calculate_activity_drop(partner)

    final_score = round(
        (0.40 * weather["weather_score"])
        + (0.30 * news_confidence)
        + (0.20 * location_match)
        + (0.10 * activity_drop),
        4,
    )

    fraud_passed = cell_tower_verified and motion_pattern_valid and notification_match
    status = "APPROVED" if final_score > 0.7 else "REJECTED"
    if not fraud_passed:
        status = "REJECTED_FRAUD"

    average_income = calculate_average_income_per_hour(partner)
    expected_hours = Decimal("8.00")
    actual_hours = _quantize(expected_hours * Decimal(str(max(0.0, 1 - activity_drop))))
    loss_hours = _quantize(max(expected_hours - actual_hours, Decimal("0.00")))
    payout_amount = Decimal("0.00")
    if status == "APPROVED":
        payout_amount = _quantize(average_income * loss_hours * CRISIS_INDEX[severity])

    audit = [
        {
            "signal": "Weather API",
            "detail": f"rain {weather['rainfall']} mm, temp {weather['temperature']}°C",
            "passed": weather["weather_score"] >= 0.5,
            "score": weather["weather_score"],
        },
        {
            "signal": "News API",
            "detail": scoring_items[0]["title"] if scoring_items else "No relevant city news",
            "passed": news_confidence >= 0.6,
            "score": news_confidence,
        },
        {
            "signal": "Location Match",
            "detail": f"{distance} km from event zone" if distance is not None else "City level match",
            "passed": bool(location_match),
            "score": location_match,
        },
        {
            "signal": "Activity Drop",
            "detail": f"avg ₹{avg_orders} vs today ₹{today_orders}",
            "passed": activity_drop >= 0.4,
            "score": activity_drop,
        },
    ]
    if trigger_signal:
        audit.insert(
            0,
            {
                "signal": "Auto Trigger",
                "detail": (
                    f"{trigger_signal.get('source') or 'system'} detected "
                    f"{trigger_signal.get('event_type') or event_type}"
                ),
                "passed": True,
                "score": 1.0,
            },
        )

    claim = ClaimRecord.objects.create(
        account=account,
        partner=partner,
        event_type=event_type,
        city=account.city or partner.city,
        region=account.region or map_city_to_region(account.city or partner.city),
        crisis_level=severity,
        status=status,
        final_score=final_score,
        weather_score=weather["weather_score"],
        news_confidence=news_confidence,
        location_match=location_match,
        activity_drop=activity_drop,
        average_income_per_hour=average_income,
        expected_hours=expected_hours,
        actual_hours=actual_hours,
        loss_hours=loss_hours,
        payout_amount=payout_amount,
        notification_match=notification_match,
        cell_tower_verified=cell_tower_verified,
        motion_pattern_valid=motion_pattern_valid,
        auto_created=auto_created,
        trigger_source=(trigger_source or (trigger_signal or {}).get("source") or "")[:32],
        event_signature=event_signature,
        trigger_title=(trigger_title or (trigger_signal or {}).get("title") or "")[:255],
        audit=audit,
    )

    ledger_type = "payout_credit" if status == "APPROVED" else "claim_rejected"
    ledger_amount = payout_amount if status == "APPROVED" else Decimal("0.00")
    if status == "APPROVED":
        account.wallet_balance = _quantize(account.wallet_balance + payout_amount)
        account.total_payout_received = _quantize(account.total_payout_received + payout_amount)
        account.save(update_fields=["wallet_balance", "total_payout_received", "updated_at"])

    PremiumLedger.objects.create(
        account=account,
        entry_type=ledger_type,
        amount=ledger_amount,
        direction="credit" if status == "APPROVED" else "debit",
        status="success" if status == "APPROVED" else "failed",
        reference=f"claim-{claim.id}",
        description=f"{status} claim for {event_type}",
        metadata={"final_score": final_score, "severity": severity},
    )

    return claim


def serialize_ledger_entry(entry: PremiumLedger) -> dict:
    return {
        "id": entry.id,
        "entry_type": entry.entry_type,
        "amount": float(entry.amount),
        "direction": entry.direction,
        "status": entry.status,
        "reference": entry.reference,
        "description": entry.description,
        "metadata": entry.metadata,
        "created_at": entry.created_at.isoformat(),
    }


def serialize_claim(claim: ClaimRecord) -> dict:
    return {
        "id": claim.id,
        "event_type": claim.event_type,
        "city": claim.city,
        "region": claim.region,
        "crisis_level": claim.crisis_level,
        "status": claim.status,
        "auto_created": claim.auto_created,
        "trigger_source": claim.trigger_source,
        "trigger_title": claim.trigger_title,
        "final_score": claim.final_score,
        "weather_score": claim.weather_score,
        "news_confidence": claim.news_confidence,
        "location_match": claim.location_match,
        "activity_drop": claim.activity_drop,
        "average_income_per_hour": float(claim.average_income_per_hour),
        "expected_hours": float(claim.expected_hours),
        "actual_hours": float(claim.actual_hours),
        "loss_hours": float(claim.loss_hours),
        "payout_amount": float(claim.payout_amount),
        "audit": claim.audit,
        "created_at": claim.created_at.isoformat(),
    }


def serialize_demo_event(event: DemoNewsEvent) -> dict:
    return {
        "id": event.id,
        "city": event.city,
        "area": event.area,
        "event_type": event.event_type,
        "severity": event.severity,
        "headline": event.headline,
        "summary": event.summary,
        "event_latitude": event.event_latitude,
        "event_longitude": event.event_longitude,
        "effective_date": event.effective_date.isoformat(),
        "is_active": event.is_active,
        "source": event.source,
    }
