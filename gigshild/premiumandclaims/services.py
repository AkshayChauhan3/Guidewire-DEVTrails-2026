from __future__ import annotations

import json
import math
import re
from difflib import SequenceMatcher
from functools import lru_cache
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

from .models import AdaptiveWeight, ClaimRecord, DemoNewsEvent, PremiumAccount, PremiumLedger, WeeklyPremiumSnapshot


TWOPLACES = Decimal("0.01")
FOURPLACES = Decimal("0.0001")
TESTING_BONUS = Decimal("5000.00")
ADAPTIVE_WEIGHT_PRIORS = {
    "weather": Decimal("0.4000"),
    "news": Decimal("0.3000"),
    "location": Decimal("0.2000"),
    "activity": Decimal("0.1000"),
}
ADAPTIVE_MIN_WEIGHT = Decimal("0.0500")
ADAPTIVE_LEARNING_RATE_APPROVED = Decimal("0.0300")
ADAPTIVE_LEARNING_RATE_REJECTED = Decimal("0.0100")
ADAPTIVE_NEARBY_RADIUS_KM = Decimal("20.0")
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

# State → region mapping — used when reverse geocoding returns a state name.
# This covers the full map of India so any city outside the hardcoded sets
# gets the correct region automatically via the geocode API.
STATE_REGION: dict[str, str] = {
    # ── North ──────────────────────────────────────────────────────────────
    "delhi": "north",
    "national capital territory of delhi": "north",
    "haryana": "north",
    "punjab": "north",
    "himachal pradesh": "north",
    "uttarakhand": "north",
    "uttar pradesh": "north",
    "rajasthan": "north",
    "jammu and kashmir": "north",
    "jammu & kashmir": "north",
    "ladakh": "north",
    # ── South ──────────────────────────────────────────────────────────────
    "karnataka": "south",
    "tamil nadu": "south",
    "kerala": "south",
    "andhra pradesh": "south",
    "telangana": "south",
    "puducherry": "south",
    "lakshadweep": "south",
    # ── East ───────────────────────────────────────────────────────────────
    "west bengal": "east",
    "odisha": "east",
    "bihar": "east",
    "jharkhand": "east",
    "assam": "east",
    "arunachal pradesh": "east",
    "manipur": "east",
    "meghalaya": "east",
    "mizoram": "east",
    "nagaland": "east",
    "sikkim": "east",
    "tripura": "east",
    # ── West (default for remaining states) ────────────────────────────────
    "maharashtra": "west",
    "gujarat": "west",
    "goa": "west",
    "madhya pradesh": "west",
    "chhattisgarh": "west",
    "dadra and nagar haveli and daman and diu": "west",
}



WEATHER_API_KEY = "a8732e24e79b406fa46135338260304"
NEWS_API_KEY = "a46c74aa3af14d13bdb56789d2c56bfb"
GEOCODE_API_KEY = "68ba83244a2ff811480127gzja3e139"
AUTO_CLAIM_WEATHER_THRESHOLD = 0.58
MAX_NEWS_SIGNALS = 8
REAL_NEWS_VALIDATION_THRESHOLD = Decimal("0.6200")
SYNTHETIC_NEWS_SOURCES = {
    "demo-generator",
    "system-demo-seed",
    "web-ui-gen",
    "demo-fallback",
    "flutter-app",
    "manual-sync",
}
HF_EVENT_MODEL_NAME = "typeform/distilbert-base-uncased-mnli"
AI_SEVERITY_WEIGHTS = {
    "mild": Decimal("0.55"),
    "moderate": Decimal("0.70"),
    "severe": Decimal("0.85"),
    "emergency": Decimal("1.00"),
}
AI_EVENT_LABELS = {
    "flood": "flood",
    "waterlogging": "flood",
    "rain": "flood",
    "protest": "protest",
    "strike": "protest",
    "heatwave": "heatwave",
    "heat wave": "heatwave",
    "extreme heat": "heatwave",
    "disaster": "disaster",
    "emergency": "disaster",
}

try:  # pragma: no cover - optional dependency
    from transformers import pipeline as hf_pipeline
except Exception:  # pragma: no cover - transformers may be unavailable in CI
    hf_pipeline = None


def _quantize(value: Decimal | int | float | str) -> Decimal:
    return Decimal(str(value)).quantize(TWOPLACES, rounding=ROUND_HALF_UP)


def _safe_json(url: str) -> dict:
    req = request.Request(url)
    with request.urlopen(req, timeout=10) as response:
        payload = response.read().decode("utf-8")
        return json.loads(payload) if payload else {}


@lru_cache(maxsize=1)
def _get_hf_news_pipeline():
    if hf_pipeline is None:
        return None

    try:
        return hf_pipeline(
            "zero-shot-classification",
            model=HF_EVENT_MODEL_NAME,
            device=-1,
        )
    except Exception:
        return None


def _news_text_for_ai(news_text: str) -> str:
    cleaned = re.sub(r"\s+", " ", (news_text or "").strip())
    return cleaned[:512]


def _news_item_text(item: dict) -> str:
    return _news_text_for_ai(f"{item.get('title') or ''} {item.get('description') or ''}")


def _tokenize_news_text(text: str) -> set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9]+", (text or "").lower())
        if len(token) > 2
    }


def _news_text_similarity(left: str, right: str) -> float:
    left_clean = _news_text_for_ai(left).lower()
    right_clean = _news_text_for_ai(right).lower()
    if not left_clean or not right_clean:
        return 0.0

    left_tokens = _tokenize_news_text(left_clean)
    right_tokens = _tokenize_news_text(right_clean)
    token_overlap = 0.0
    if left_tokens and right_tokens:
        token_overlap = len(left_tokens & right_tokens) / len(left_tokens | right_tokens)

    sequence_ratio = SequenceMatcher(None, left_clean, right_clean).ratio()
    return round((0.6 * token_overlap) + (0.4 * sequence_ratio), 4)


def _is_synthetic_source(source: str | None) -> bool:
    normalized = (source or "").strip().lower()
    return (
        normalized in SYNTHETIC_NEWS_SOURCES
        or "demo" in normalized
        or "fake" in normalized
        or "mock" in normalized
    )


def _severity_from_text(text: str, confidence: float) -> str:
    normalized = (text or "").lower()
    if any(word in normalized for word in ["emergency", "evacuation", "shutdown", "collapsed"]):
        return "emergency"
    if any(word in normalized for word in ["severe", "extreme", "catastrophic", "major", "flood"]):
        return "severe"
    if any(word in normalized for word in ["heavy", "high", "warning", "disruption", "strike", "protest"]):
        return "moderate"
    if confidence >= 0.85:
        return "severe"
    if confidence >= 0.65:
        return "moderate"
    return "mild"


def _normalize_ai_event_type(event_type: str, text: str) -> str:
    normalized = (event_type or "").strip().lower()
    if normalized in AI_EVENT_LABELS:
        return AI_EVENT_LABELS[normalized]

    text_lower = (text or "").lower()
    for keyword, mapped in AI_EVENT_LABELS.items():
        if keyword in text_lower:
            return mapped

    return infer_event_type(text)


def _build_ai_result(
    *,
    text: str,
    event_type: str,
    confidence: float,
    severity: str,
    source: str,
    weather_score: float | None = None,
) -> dict:
    ai_score = Decimal(str(confidence)) * AI_SEVERITY_WEIGHTS.get(severity, Decimal("0.55"))
    boost_reason = None
    if event_type == "flood" and weather_score is not None and float(weather_score) >= 0.75:
        ai_score *= Decimal("1.12")
        boost_reason = "weather_boost"
    ai_score = min(max(ai_score, Decimal("0.0")), Decimal("1.0"))
    return {
        "event_type": event_type,
        "severity": severity,
        "confidence": round(float(confidence), 4),
        "ai_score": round(ai_score, 4),
        "source": source,
        "text": text,
        "boost_reason": boost_reason,
    }


def analyze_news_with_ai(news_text: str, weather_score: float | None = None) -> dict:
    text = _news_text_for_ai(news_text)
    if not text:
        return _build_ai_result(
            text="",
            event_type="disaster",
            confidence=0.0,
            severity="mild",
            source="fallback-empty",
            weather_score=weather_score,
        )

    classifier = _get_hf_news_pipeline()
    if classifier is not None:
        try:
            result = classifier(
                text,
                candidate_labels=["flood", "protest", "heatwave", "disaster"],
                multi_label=False,
            )
            labels = result.get("labels") or []
            scores = result.get("scores") or []
            if labels and scores:
                top_label = str(labels[0]).lower()
                confidence = float(scores[0])
            else:
                top_label = "disaster"
                confidence = 0.0
            event_type = _normalize_ai_event_type(top_label, text)
            severity = _severity_from_text(text, confidence)
            return _build_ai_result(
                text=text,
                event_type=event_type,
                confidence=confidence,
                severity=severity,
                source="huggingface",
                weather_score=weather_score,
            )
        except Exception:
            pass

    event_type = infer_event_type(text)
    severity = infer_severity(text)
    confidence = 0.90 if event_type != "disaster" else 0.60
    if "emergency" in text.lower():
        confidence = 0.95
    elif any(word in text.lower() for word in ["severe", "flood", "heatwave", "protest"]):
        confidence = 0.82
    return _build_ai_result(
        text=text,
        event_type=_normalize_ai_event_type(event_type, text),
        confidence=confidence,
        severity=severity,
        source="rule-based-fallback",
        weather_score=weather_score,
    )


def _aggregate_ai_analyses(analyses: list[dict], fallback_text: str = "disaster") -> dict:
    if not analyses:
        return analyze_news_with_ai(fallback_text)

    ranked = sorted(
        analyses,
        key=lambda value: float(value.get("ai_score") or value.get("confidence") or 0.0),
        reverse=True,
    )
    top_items = ranked[:3]
    top_count = len(top_items)
    averaged_ai_score = sum(
        float(item.get("ai_score") or item.get("confidence") or 0.0)
        for item in top_items
    ) / top_count
    averaged_confidence = sum(
        float(item.get("confidence") or 0.0)
        for item in top_items
    ) / top_count

    event_votes = Counter(item.get("event_type") or "disaster" for item in top_items)
    severity_order = {"mild": 0, "moderate": 1, "severe": 2, "emergency": 3}
    severity = max(
        (item.get("severity") or "mild" for item in top_items),
        key=lambda value: severity_order.get(value, 0),
    )
    event_type = event_votes.most_common(1)[0][0]
    boost_reason = "weather_boost" if any(item.get("boost_reason") == "weather_boost" for item in top_items) else None

    return {
        "event_type": event_type,
        "severity": severity,
        "confidence": round(averaged_confidence, 4),
        "ai_score": round(min(averaged_ai_score, 1.0), 4),
        "source": "aggregated-ai",
        "top_signals": top_items,
        "boost_reason": boost_reason,
    }


def _slugify_text(value: str) -> str:
    cleaned = "".join(ch.lower() if ch.isalnum() else "-" for ch in (value or "").strip())
    collapsed = "-".join(part for part in cleaned.split("-") if part)
    return collapsed[:80]


def _build_event_signature(*parts: object) -> str:
    joined = "|".join(str(part or "").strip().lower() for part in parts)
    digest = sha1(joined.encode("utf-8")).hexdigest()[:16]
    return f"{_slugify_text(joined)[:72]}-{digest}"


def _normalize_location_key(value: str) -> str:
    return (value or "global").strip().lower()


def _normalize_city_key(city: str | None) -> str | None:
    if not city:
        return None
    normalized = re.sub(r"[^a-z0-9]+", "_", city.strip().lower()).strip("_")
    return normalized or None


def get_location_key(city: str | None, lat: float | None, lon: float | None) -> str:
    if lat is not None and lon is not None:
        return f"lat_{float(lat):.2f}_lon_{float(lon):.2f}"
    normalized_city = _normalize_city_key(city)
    return normalized_city or "global"


def _parse_lat_lon_key(location_key: str) -> tuple[float | None, float | None]:
    match = re.fullmatch(r"lat_(-?\d+(?:\.\d+)?)_lon_(-?\d+(?:\.\d+)?)", _normalize_location_key(location_key))
    if not match:
        return None, None
    return float(match.group(1)), float(match.group(2))


def _weight_value(value: Decimal | float | int | str) -> Decimal:
    return Decimal(str(value)).quantize(FOURPLACES, rounding=ROUND_HALF_UP)


def normalize_weights(weights: dict[str, Decimal | float | int | str]) -> dict[str, Decimal]:
    raw_weights = {
        "weather": max(_weight_value(weights.get("weather", ADAPTIVE_WEIGHT_PRIORS["weather"])), ADAPTIVE_MIN_WEIGHT),
        "news": max(_weight_value(weights.get("news", ADAPTIVE_WEIGHT_PRIORS["news"])), ADAPTIVE_MIN_WEIGHT),
        "location": max(_weight_value(weights.get("location", ADAPTIVE_WEIGHT_PRIORS["location"])), ADAPTIVE_MIN_WEIGHT),
        "activity": max(_weight_value(weights.get("activity", ADAPTIVE_WEIGHT_PRIORS["activity"])), ADAPTIVE_MIN_WEIGHT),
    }
    total = sum(raw_weights.values(), Decimal("0.0000"))
    if total <= 0:
        return ADAPTIVE_WEIGHT_PRIORS.copy()

    normalized = {
        name: (value / total).quantize(FOURPLACES, rounding=ROUND_HALF_UP)
        for name, value in raw_weights.items()
    }
    # Keep exact sum stable after rounding.
    correction = Decimal("1.0000") - sum(normalized.values(), Decimal("0.0000"))
    if correction:
        normalized["weather"] = (normalized["weather"] + correction).quantize(FOURPLACES, rounding=ROUND_HALF_UP)
    return normalized


def _weights_from_model(weight: AdaptiveWeight) -> dict[str, Decimal]:
    return normalize_weights(
        {
            "weather": weight.weather_weight,
            "news": weight.news_weight,
            "location": weight.location_weight,
            "activity": weight.activity_weight,
        }
    )


def _weight_defaults_from(location_key: str | None) -> dict[str, Decimal]:
    location_key = _normalize_location_key(location_key or "global")
    if location_key == "global":
        return ADAPTIVE_WEIGHT_PRIORS.copy()
    city_weight = AdaptiveWeight.objects.filter(location_key=location_key).first()
    if city_weight:
        return _weights_from_model(city_weight)
    return ADAPTIVE_WEIGHT_PRIORS.copy()


def _get_or_create_weight_record(location_key: str) -> AdaptiveWeight:
    location_key = _normalize_location_key(location_key)
    defaults = _weight_defaults_from(location_key)
    return AdaptiveWeight.objects.get_or_create(
        location_key=location_key,
        defaults={
            "weather_weight": defaults["weather"],
            "news_weight": defaults["news"],
            "location_weight": defaults["location"],
            "activity_weight": defaults["activity"],
        },
    )[0]


def get_weights(location_key: str) -> dict[str, Decimal]:
    location_key = _normalize_location_key(location_key)
    record = AdaptiveWeight.objects.filter(location_key=location_key).first()
    if record:
        return _weights_from_model(record)
    if location_key == "global":
        return ADAPTIVE_WEIGHT_PRIORS.copy()
    return ADAPTIVE_WEIGHT_PRIORS.copy()


def _resolve_effective_weight_record(
    city: str | None,
    lat: float | None,
    lon: float | None,
) -> tuple[str, dict[str, Decimal]]:
    location_key = get_location_key(city, lat, lon)
    if lat is not None and lon is not None:
        exact_key = _normalize_location_key(location_key)
        exact_record = AdaptiveWeight.objects.filter(location_key=exact_key).first()
        if exact_record:
            return exact_key, _weights_from_model(exact_record)
    city_key = _normalize_city_key(city)
    if city_key:
        city_record = AdaptiveWeight.objects.filter(location_key=city_key).first()
        if city_record:
            return city_key, _weights_from_model(city_record)
    global_record = _get_or_create_weight_record("global")
    return "global", _weights_from_model(global_record)


def map_city_to_region(city: str, state: str | None = None) -> str:
    """Map city (and optionally state) to a premium region.

    Resolution order:
      1. State name via STATE_REGION  (geocode API — most accurate, covers whole India)
      2. City name via NORTH/SOUTH/EAST_CITIES  (hardcoded fallback for common cities)
      3. Default → "west"
    """
    if state:
        region = STATE_REGION.get(state.strip().lower())
        if region:
            return region
    normalized = (city or "").strip().lower()
    if normalized in NORTH_CITIES:
        return "north"
    if normalized in SOUTH_CITIES:
        return "south"
    if normalized in EAST_CITIES:
        return "east"
    return "west"




def reverse_geocode_location(latitude: float, longitude: float) -> dict:
    """Resolve city AND state from lat/lon using geocode.maps.co.

    Returns a dict with keys ``city`` (str | None) and ``state`` (str | None).
    Both values are stripped title-cased strings, or None on failure.
    Always returns the dict — never raises.
    """
    try:
        query = parse.urlencode({
            "lat": latitude,
            "lon": longitude,
            "api_key": GEOCODE_API_KEY,
        })
        data = _safe_json(f"https://geocode.maps.co/reverse?{query}")
        address = data.get("address") or {}

        # City: city > town > county > state_district
        raw_city = (
            address.get("city")
            or address.get("town")
            or address.get("county")
            or address.get("state_district")
            or ""
        ).strip()

        # State: state field returned directly by the API
        raw_state = (address.get("state") or "").strip()

        return {
            "city": raw_city if raw_city else None,
            "state": raw_state if raw_state else None,
        }
    except (error.URLError, error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError):
        return {"city": None, "state": None}


def reverse_geocode_city(latitude: float, longitude: float) -> str | None:
    """Thin wrapper — returns just the city string (backward-compat)."""
    return reverse_geocode_location(latitude, longitude)["city"]


def ensure_premium_account(partner: DeliveryPartner) -> PremiumAccount:
    account, created = PremiumAccount.objects.get_or_create(
        partner=partner,
        defaults={
            "wallet_balance": TESTING_BONUS,
            "testing_bonus": TESTING_BONUS,
            "city": partner.city,
            "area": partner.area,
            "pincode": partner.pincode,
            "region": map_city_to_region(partner.city),
            # latitude/longitude left None — filled by sync_account_location() on session start
            "latitude": None,
            "longitude": None,
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

    # ── Auto-resolve city + state from coordinates when city is absent ──
    _state: str | None = None
    if latitude is not None and longitude is not None:
        geo = reverse_geocode_location(latitude, longitude)
        if not city and geo["city"]:
            city = geo["city"]
        _state = geo["state"]   # always capture state for accurate region mapping

    if city:
        account.city = city
        # Use state-aware region lookup — accurate for any Indian city via geocode API
        account.region = map_city_to_region(city, state=_state)
        dirty_fields.extend(["city", "region"])
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
                "ai_analysis": analyze_news_with_ai(f"{event.headline} {event.summary}"),
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
                    "ai_analysis": analyze_news_with_ai(f"{title} {description}"),
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
            "ai_analysis": analyze_news_with_ai(
                f"{city} sees high rainfall warning for delivery workers"
            ),
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


def fetch_real_news_signals(city: str, *, event_type: str | None = None) -> list[dict]:
    city = (city or "Mumbai").strip() or "Mumbai"
    query_terms = [
        city,
        "flood OR heavy rain OR strike OR protest OR heatwave OR disaster",
    ]
    if event_type:
        normalized_event = event_type.strip().lower()
        event_keywords = {
            "flood": "flood OR waterlogging OR storm",
            "high_rain": "rain OR flooding OR waterlogging",
            "high_temperature": "heatwave OR heat OR temperature",
            "strike": "strike OR shutdown",
            "protest": "protest OR rally",
            "curfew": "curfew OR lockdown",
            "disaster": "disaster OR emergency",
        }
        query_terms.append(event_keywords.get(normalized_event, normalized_event))

    try:
        query_text = " ".join(query_terms)
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
        signals: list[dict] = []
        seen_keys: set[tuple[str, str]] = set()
        for article in (data.get("articles") or [])[:MAX_NEWS_SIGNALS]:
            title = article.get("title") or ""
            description = article.get("description") or ""
            source = (article.get("source") or {}).get("name") or "newsapi"
            key = (title.strip().lower(), source.strip().lower())
            if not title or key in seen_keys:
                continue
            seen_keys.add(key)
            text = f"{title} {description}".strip()
            ai_analysis = analyze_news_with_ai(text)
            signals.append(
                {
                    "title": title,
                    "source": source,
                    "description": description,
                    "event_type": ai_analysis.get("event_type") or infer_event_type(text),
                    "severity": ai_analysis.get("severity") or infer_severity(text),
                    "ai_analysis": ai_analysis,
                    "published_at": article.get("publishedAt"),
                    "event_location": {"latitude": None, "longitude": None},
                    "url": article.get("url") or "",
                    "signature": _build_event_signature(
                        city,
                        ai_analysis.get("event_type") or infer_event_type(text),
                        source,
                        title,
                        article.get("publishedAt"),
                    ),
                }
            )
        return signals
    except (error.URLError, error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError):
        return []


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
    event_counter = Counter(
        (
            (item.get("ai_analysis") or {}).get("event_type")
            or item.get("event_type")
            or "disaster"
        )
        for item in news_items
    )
    event_type = event_counter.most_common(1)[0][0]
    severity = max(
        (
            (item.get("ai_analysis") or {}).get("severity")
            or item.get("severity")
            or "mild"
            for item in news_items
        ),
        key=lambda value: severity_weights.get(value, 0.40),
    )
    confidence = max(
        severity_weights.get(
            (item.get("ai_analysis") or {}).get("severity")
            or item.get("severity")
            or "mild",
            0.40,
        )
        for item in news_items[:3]
    )
    if len(news_items) > 1:
        confidence = min(confidence + 0.05, 1.0)
    return round(confidence, 4), event_type, severity


def validate_real_news_corroboration(
    *,
    city: str,
    trigger_signal: dict | None,
    real_news_items: list[dict],
    trigger_source: str | None = None,
    weather_score: float | None = None,
) -> dict:
    trigger_signal = trigger_signal or {}
    trigger_source = (
        (trigger_source or trigger_signal.get("source") or "").strip().lower()
    )
    trigger_title = _news_item_text(trigger_signal)
    trigger_event_type = (
        trigger_signal.get("event_type")
        or infer_event_type(trigger_title)
    )
    trigger_severity = trigger_signal.get("severity") or infer_severity(trigger_title)
    requires_validation = _is_synthetic_source(trigger_source)

    best_match: dict | None = None
    best_score = 0.0
    for item in real_news_items:
        item_text = _news_item_text(item)
        if not item_text:
            continue
        ai_analysis = item.get("ai_analysis") or analyze_news_with_ai(
            item_text,
            weather_score=weather_score,
        )
        similarity = _news_text_similarity(trigger_title, item_text)
        ai_confidence = float(ai_analysis.get("ai_score") or ai_analysis.get("confidence") or 0.0)
        event_alignment = 1.0 if (
            (ai_analysis.get("event_type") or item.get("event_type")) == trigger_event_type
            or trigger_event_type in item_text.lower()
        ) else 0.0
        severity_alignment = 1.0 if (
            (ai_analysis.get("severity") or item.get("severity")) == trigger_severity
        ) else 0.0
        score = round(
            (0.40 * similarity)
            + (0.35 * ai_confidence)
            + (0.15 * event_alignment)
            + (0.10 * severity_alignment),
            4,
        )
        if score > best_score:
            best_score = score
            best_match = {
                "title": item.get("title"),
                "source": item.get("source"),
                "event_type": ai_analysis.get("event_type") or item.get("event_type"),
                "severity": ai_analysis.get("severity") or item.get("severity"),
                "score": score,
                "similarity": similarity,
                "ai_confidence": round(ai_confidence, 4),
                "url": item.get("url") or "",
            }

    supported = best_score >= float(REAL_NEWS_VALIDATION_THRESHOLD)
    if requires_validation:
        is_valid = supported
    else:
        is_valid = True

    reason = "real-news-corroborated" if is_valid else "synthetic-news-not-supported"
    if requires_validation and not real_news_items:
        reason = "no-real-news-corroboration"

    return {
        "city": city,
        "requires_validation": requires_validation,
        "is_valid": is_valid,
        "score": round(best_score, 4),
        "threshold": float(REAL_NEWS_VALIDATION_THRESHOLD),
        "matched_news": best_match or {},
        "reason": reason,
    }


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


def calculate_adaptive_score(
    *,
    city: str | None,
    latitude: float | None,
    longitude: float | None,
    weather_score: float | Decimal,
    news_confidence: float | Decimal,
    location_match: float | Decimal,
    activity_drop: float | Decimal,
) -> tuple[Decimal, str, dict[str, Decimal]]:
    location_key, weights = _resolve_effective_weight_record(city, latitude, longitude)
    signals = {
        "weather": _weight_value(weather_score),
        "news": _weight_value(news_confidence),
        "location": _weight_value(location_match),
        "activity": _weight_value(activity_drop),
    }
    score = sum(
        weights[name] * signals[name]
        for name in ("weather", "news", "location", "activity")
    ).quantize(FOURPLACES, rounding=ROUND_HALF_UP)
    return score, location_key, weights


def _calculate_rule_score(
    *,
    weather_score: float,
    news_confidence: float,
    location_match: float,
    activity_drop: float,
    fraud_passed: bool,
) -> Decimal:
    score = (
        Decimal("0.30") * _weight_value(1.0 if weather_score >= 0.50 else weather_score)
        + Decimal("0.25") * _weight_value(news_confidence)
        + Decimal("0.20") * _weight_value(location_match)
        + Decimal("0.15") * _weight_value(activity_drop)
        + Decimal("0.10") * _weight_value(1.0 if fraud_passed else 0.0)
    )
    return min(score, Decimal("1.0000")).quantize(FOURPLACES, rounding=ROUND_HALF_UP)


def _apply_weight_delta(weights: dict[str, Decimal], delta: dict[str, Decimal]) -> dict[str, Decimal]:
    adjusted = {
        name: weights[name] + delta.get(name, Decimal("0.0000"))
        for name in ("weather", "news", "location", "activity")
    }
    return normalize_weights(adjusted)


def _save_weights(location_key: str, weights: dict[str, Decimal]) -> AdaptiveWeight:
    location_key = _normalize_location_key(location_key)
    record = AdaptiveWeight.objects.filter(location_key=location_key).first()
    if record is None:
        record = AdaptiveWeight(location_key=location_key)
    record.weather_weight = weights["weather"]
    record.news_weight = weights["news"]
    record.location_weight = weights["location"]
    record.activity_weight = weights["activity"]
    record.save()
    return record


def update_weights_after_claim(
    claim: ClaimRecord,
    *,
    city: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
    weather_score: float | None = None,
    news_confidence: float | None = None,
    location_match: float | None = None,
    activity_drop: float | None = None,
    adaptive_score: Decimal | None = None,
    rule_score: Decimal | None = None,
) -> None:
    city = city or claim.city
    latitude = claim.account.latitude if latitude is None else latitude
    longitude = claim.account.longitude if longitude is None else longitude
    weather_score = float(weather_score if weather_score is not None else claim.weather_score)
    news_confidence = float(news_confidence if news_confidence is not None else claim.news_confidence)
    location_match = float(location_match if location_match is not None else claim.location_match)
    activity_drop = float(activity_drop if activity_drop is not None else claim.activity_drop)

    specific_key = get_location_key(city, latitude, longitude)
    city_key = _normalize_city_key(city)
    influence_multiplier = Decimal("1.0000") if claim.status == "APPROVED" else Decimal("0.3500")
    learning_rate = (
        ADAPTIVE_LEARNING_RATE_APPROVED
        if claim.status == "APPROVED"
        else ADAPTIVE_LEARNING_RATE_REJECTED
    )

    # Positive learning lifts the strongest contributors; rejected claims pull
    # everything down a bit, but never below the minimum floor.
    signal_strength = normalize_weights(
        {
            "weather": max(_weight_value(weather_score), Decimal("0.0000")),
            "news": max(_weight_value(news_confidence), Decimal("0.0000")),
            "location": max(_weight_value(location_match), Decimal("0.0000")),
            "activity": max(_weight_value(activity_drop), Decimal("0.0000")),
        }
    )
    if claim.status == "APPROVED":
        delta = {
            name: learning_rate * signal_strength[name]
            for name in signal_strength
        }
    else:
        delta = {
            name: -(learning_rate * signal_strength[name] * influence_multiplier)
            for name in signal_strength
        }

    updates: list[tuple[str, dict[str, Decimal]]] = []

    global_record = AdaptiveWeight.objects.filter(location_key="global").first()
    global_weights = _weights_from_model(global_record) if global_record else ADAPTIVE_WEIGHT_PRIORS.copy()
    updates.append(("global", _apply_weight_delta(global_weights, {k: delta[k] * Decimal("0.30") for k in delta})))

    if city_key:
        city_record = AdaptiveWeight.objects.filter(location_key=city_key).first()
        city_weights = _weights_from_model(city_record) if city_record else global_weights
        updates.append((city_key, _apply_weight_delta(city_weights, {k: delta[k] * Decimal("0.60") for k in delta})))

    if specific_key != "global":
        specific_record = AdaptiveWeight.objects.filter(location_key=specific_key).first()
        specific_weights = _weights_from_model(specific_record) if specific_record else (city_weights if city_key else global_weights)
        updates.append((specific_key, _apply_weight_delta(specific_weights, delta)))

    if latitude is not None and longitude is not None:
        for nearby in AdaptiveWeight.objects.filter(location_key__startswith="lat_"):
            if _normalize_location_key(nearby.location_key) == _normalize_location_key(specific_key):
                continue
            nearby_lat, nearby_lon = _parse_lat_lon_key(nearby.location_key)
            if nearby_lat is None or nearby_lon is None:
                continue
            distance = haversine_distance_km(latitude, longitude, nearby_lat, nearby_lon)
            if distance > float(ADAPTIVE_NEARBY_RADIUS_KM):
                continue
            closeness = max(Decimal("0.15"), Decimal("1.0000") - (Decimal(str(distance)) / ADAPTIVE_NEARBY_RADIUS_KM))
            nearby_weights = _weights_from_model(nearby)
            updates.append(
                (
                    nearby.location_key,
                    _apply_weight_delta(
                        nearby_weights,
                        {k: delta[k] * closeness * Decimal("0.20") for k in delta},
                    ),
                )
            )

    # Later updates may target the same record more than once. Keep the last
    # computed value, which already includes the most specific influence.
    deduped_updates: dict[str, dict[str, Decimal]] = {}
    for key, values in updates:
        deduped_updates[key] = values

    for key, values in deduped_updates.items():
        _save_weights(key, values)


def update_weights_after_premium(
    *,
    city: str | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
    weather_score: float,
    news_confidence: float,
    location_match: float,
    activity_drop: float,
    is_high_risk: bool,
) -> None:
    specific_key = get_location_key(city, latitude, longitude)
    city_key = _normalize_city_key(city)
    influence_multiplier = Decimal("1.0000") if is_high_risk else Decimal("0.3500")
    learning_rate = ADAPTIVE_LEARNING_RATE_APPROVED if is_high_risk else ADAPTIVE_LEARNING_RATE_REJECTED

    signal_strength = normalize_weights(
        {
            "weather": max(_weight_value(weather_score), Decimal("0.0000")),
            "news": max(_weight_value(news_confidence), Decimal("0.0000")),
            "location": max(_weight_value(location_match), Decimal("0.0000")),
            "activity": max(_weight_value(activity_drop), Decimal("0.0000")),
        }
    )
    if is_high_risk:
        delta = {
            name: learning_rate * signal_strength[name]
            for name in signal_strength
        }
    else:
        delta = {
            name: -(learning_rate * signal_strength[name] * influence_multiplier)
            for name in signal_strength
        }

    updates: list[tuple[str, dict[str, Decimal]]] = []

    global_record = AdaptiveWeight.objects.filter(location_key="global").first()
    global_weights = _weights_from_model(global_record) if global_record else ADAPTIVE_WEIGHT_PRIORS.copy()
    updates.append(("global", _apply_weight_delta(global_weights, {k: delta[k] * Decimal("0.30") for k in delta})))

    if city_key:
        city_record = AdaptiveWeight.objects.filter(location_key=city_key).first()
        city_weights = _weights_from_model(city_record) if city_record else global_weights
        updates.append((city_key, _apply_weight_delta(city_weights, {k: delta[k] * Decimal("0.60") for k in delta})))

    if specific_key != "global":
        specific_record = AdaptiveWeight.objects.filter(location_key=specific_key).first()
        specific_weights = _weights_from_model(specific_record) if specific_record else (city_weights if city_key else global_weights)
        updates.append((specific_key, _apply_weight_delta(specific_weights, delta)))

    if latitude is not None and longitude is not None:
        for nearby in AdaptiveWeight.objects.filter(location_key__startswith="lat_"):
            if _normalize_location_key(nearby.location_key) == _normalize_location_key(specific_key):
                continue
            nearby_lat, nearby_lon = _parse_lat_lon_key(nearby.location_key)
            if nearby_lat is None or nearby_lon is None:
                continue
            distance = haversine_distance_km(latitude, longitude, nearby_lat, nearby_lon)
            if distance > float(ADAPTIVE_NEARBY_RADIUS_KM):
                continue
            closeness = max(Decimal("0.15"), Decimal("1.0000") - (Decimal(str(distance)) / ADAPTIVE_NEARBY_RADIUS_KM))
            nearby_weights = _weights_from_model(nearby)
            updates.append(
                (
                    nearby.location_key,
                    _apply_weight_delta(
                        nearby_weights,
                        {k: delta[k] * closeness * Decimal("0.20") for k in delta},
                    ),
                )
            )

    deduped_updates: dict[str, dict[str, Decimal]] = {}
    for key, values in updates:
        deduped_updates[key] = values

    for key, values in deduped_updates.items():
        _save_weights(key, values)


def _history_range(partner: DeliveryPartner, days: int, until_date=None):
    until_date = until_date or timezone.localdate()
    start_date = until_date - timedelta(days=days - 1)
    return SessionHistory.objects.filter(
        partner=partner,
        history_date__range=(start_date, until_date),
    ).order_by("history_date")


def calculate_weekly_metrics(partner: DeliveryPartner, until_date=None) -> dict:
    """Calculates income, hours, and worker category for the last 7 days."""
    until_date = until_date or timezone.localdate()
    # Fetch work history records for the past week
    histories = list(_history_range(partner, 7, until_date))

    # Tally up total income and hours worked across all shifts
    weekly_income = sum((history.total_earned_amount for history in histories), Decimal("0.00"))
    total_hours = sum((history.total_working_hours for history in histories), Decimal("0.00"))

    # Track weekend hours specifically (Saturday and Sunday) to help determine the worker category
    weekend_hours = sum(
        (history.total_working_hours for history in histories if history.history_date.weekday() >= 5),
        Decimal("0.00"),
    )

    # Classify the worker based on their weekly activity
    category = "casual"
    if total_hours >= Decimal("35.00"):
        category = "full_time"
    elif total_hours >= Decimal("15.00"):
        category = "part_time"
    elif total_hours > 0 and (weekend_hours / total_hours) > Decimal("0.60"):
        # If they work mostly on weekends, classify them as a weekend worker
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
    """Measures how much today's earnings have dropped compared to the 30-day average."""
    today = today or timezone.localdate()
    # Look at the last 30 days of work history to establish a baseline
    month_histories = list(_history_range(partner, 30, today))
    if not month_histories:
        return 0.0, Decimal("0.00"), Decimal("0.00")

    # Calculate average daily earnings over the last month
    total_income = sum((history.total_earned_amount for history in month_histories), Decimal("0.00"))
    avg_orders = (total_income / Decimal(max(len(month_histories), 1))).quantize(TWOPLACES)

    # Identify today's earnings to compare against the average
    today_history = next((history for history in month_histories if history.history_date == today), None)
    today_orders = today_history.total_earned_amount if today_history else Decimal("0.00")

    if avg_orders <= 0:
        return 0.0, avg_orders, today_orders

    # Calculate the percentage drop in earnings, keeping it between 0.0 (no drop) and 1.0 (100% drop)
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


def calculate_daily_income_cap(partner: DeliveryPartner, today=None) -> Decimal:
    metrics = calculate_weekly_metrics(partner, today)
    weekly_income = metrics["weekly_income"]
    if weekly_income <= 0:
        return Decimal("0.00")
    return _quantize(weekly_income / Decimal("7"))


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
    daily_income_cap = calculate_daily_income_cap(partner, today)
    weather = fetch_weather_snapshot(account.city or partner.city)
    existing_snapshot = WeeklyPremiumSnapshot.objects.filter(
        partner=partner,
        week_start=metrics["week_start"],
    ).first()

    news_items = fetch_real_news_signals(account.city or partner.city)
    news_confidence, event_type, severity = calculate_news_confidence(news_items)
    location_match, distance = calculate_location_match(account, news_items)
    activity_drop, avg_orders, today_orders = calculate_activity_drop(partner)

    adaptive_score, location_key, adaptive_weights = calculate_adaptive_score(
        city=account.city or partner.city,
        latitude=account.latitude,
        longitude=account.longitude,
        weather_score=weather["weather_score"],
        news_confidence=news_confidence,
        location_match=location_match,
        activity_drop=activity_drop,
    )

    region = account.region or map_city_to_region(account.city or partner.city)
    learned_rate_from_weights = REGION_PREMIUM[region] * (Decimal("0.7") + (adaptive_score * Decimal("0.6")))
    region_rate = learned_rate_from_weights

    category_multiplier = CATEGORY_MULTIPLIER[metrics["category"]]
    base_premium = _quantize(metrics["weekly_income"] * region_rate * category_multiplier)

    rule_score = _weight_value(weather["weather_score"])
    premium_multiplier = (
        Decimal("1.0000")
        + (Decimal("0.6") * adaptive_score)
        + (Decimal("0.4") * rule_score)
    )

    premium = base_premium * premium_multiplier
    premium = min(premium, base_premium * Decimal("2.0"))
    premium = max(premium, base_premium * Decimal("0.5"))
    if daily_income_cap > 0:
        premium = min(premium, daily_income_cap)

    last_snapshot = WeeklyPremiumSnapshot.objects.filter(partner=partner).order_by("-week_start").first()
    if last_snapshot and last_snapshot.premium_amount:
        old_premium = last_snapshot.premium_amount
        final_premium = Decimal("0.7") * old_premium + Decimal("0.3") * premium
        premium_amount = _quantize(final_premium)
    else:
        premium_amount = _quantize(premium)

    already_collected = bool(existing_snapshot and existing_snapshot.deducted_on)
    if daily_income_cap > 0:
        premium_amount = min(premium_amount, daily_income_cap)
    if collect and not already_collected:
        premium_amount = min(premium_amount, _quantize(max(account.wallet_balance, Decimal("0.00"))))

    weather_multiplier = float(premium_multiplier)
    deducted_on = existing_snapshot.deducted_on if existing_snapshot and existing_snapshot.deducted_on else None
    if collect and not already_collected:
        deducted_on = today

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
            "weather_multiplier": weather_multiplier,
            "premium_amount": premium_amount,
            "deducted_on": deducted_on,
        },
    )

    payment_status = "preview"
    if collect and already_collected:
        payment_status = "already_debited"
    elif collect and premium_amount > 0:
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
    elif collect:
        payment_status = "debited"

    is_high_risk = premium_multiplier > Decimal("1.2000")
    update_weights_after_premium(
        city=account.city or partner.city,
        latitude=account.latitude,
        longitude=account.longitude,
        weather_score=weather["weather_score"],
        news_confidence=news_confidence,
        location_match=location_match,
        activity_drop=activity_drop,
        is_high_risk=is_high_risk,
    )

    return {
        "account": account,
        "snapshot": snapshot,
        "weather": weather,
        "payment_status": payment_status,
        "region_rate": float(region_rate),
        "category_multiplier": float(category_multiplier),
        "base_premium": float(base_premium),
        "daily_income_cap": float(daily_income_cap),
        "adaptive_score": float(adaptive_score),
        "rule_score": float(rule_score),
        "location_key": location_key,
        "adaptive_weights": {name: float(value) for name, value in adaptive_weights.items()},
    }


@transaction.atomic
def collect_weekly_premium_for_all_partners(*, today=None) -> dict:
    today = today or timezone.localdate()
    partners = DeliveryPartner.objects.order_by("id")
    results = []

    for partner in partners:
        result = calculate_or_collect_weekly_premium(partner, collect=True, today=today)
        results.append(
            {
                "partner_id": partner.id,
                "phone": partner.phone,
                "payment_status": result["payment_status"],
                "premium_amount": result["snapshot"].premium_amount,
            }
        )

    return {
        "processed": len(results),
        "debited": sum(1 for item in results if item["payment_status"] == "debited"),
        "already_debited": sum(1 for item in results if item["payment_status"] == "already_debited"),
        "results": results,
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
    real_news_items = fetch_real_news_signals(account.city or partner.city)
    trigger_source_normalized = (trigger_source or (trigger_signal or {}).get("source") or "").strip().lower()
    trigger_is_synthetic = _is_synthetic_source(trigger_source_normalized)
    validation = validate_real_news_corroboration(
        city=account.city or partner.city,
        trigger_signal=trigger_signal,
        real_news_items=real_news_items,
        trigger_source=trigger_source_normalized,
        weather_score=weather.get("weather_score"),
    )

    if trigger_is_synthetic:
        scoring_items = real_news_items
    elif trigger_signal:
        scoring_items = [trigger_signal, *real_news_items]
    else:
        scoring_items = real_news_items or news_items

    scoring_items = scoring_items[:3]
    enriched_items = []
    for item in scoring_items:
        text = f"{item.get('title') or ''} {item.get('description') or ''}".strip()
        ai_analysis = item.get("ai_analysis") or analyze_news_with_ai(
            text,
            weather_score=weather.get("weather_score"),
        )
        enriched_items.append({**item, "ai_analysis": ai_analysis})

    news_confidence, legacy_event_type, legacy_severity = calculate_news_confidence(enriched_items)
    news_preview = [
        {
            "title": item.get("title"),
            "source": item.get("source"),
            "event_type": item.get("event_type"),
            "severity": item.get("severity"),
            "confidence": round(
                float(
                    (item.get("ai_analysis") or {}).get("confidence")
                    or (item.get("ai_analysis") or {}).get("ai_score")
                    or 0.0
                ),
                4,
            ),
            "url": item.get("url") or "",
        }
        for item in enriched_items[:3]
    ]
    ai_analyses = [item["ai_analysis"] for item in enriched_items if item.get("ai_analysis")]
    if ai_analyses:
        top_ai_analysis = _aggregate_ai_analyses(ai_analyses, fallback_text="disaster")
    else:
        top_ai_analysis = {
            "event_type": infer_event_type((trigger_signal or {}).get("title") or trigger_title or "disaster"),
            "severity": infer_severity((trigger_signal or {}).get("title") or trigger_title or "disaster"),
            "confidence": 0.0,
            "ai_score": 0.0,
            "source": "no-real-news",
            "text": "",
            "boost_reason": None,
        }
    event_type = top_ai_analysis.get("event_type") or legacy_event_type
    severity = top_ai_analysis.get("severity") or legacy_severity
    ai_score = float(top_ai_analysis.get("ai_score") or top_ai_analysis.get("confidence") or 0.0)
    location_match, distance = calculate_location_match(account, enriched_items)
    activity_drop, avg_orders, today_orders = calculate_activity_drop(partner)

    fraud_passed = cell_tower_verified and motion_pattern_valid and notification_match and validation["is_valid"]
    adaptive_score, location_key, adaptive_weights = calculate_adaptive_score(
        city=account.city or partner.city,
        latitude=account.latitude,
        longitude=account.longitude,
        weather_score=weather["weather_score"],
        news_confidence=news_confidence,
        location_match=location_match,
        activity_drop=activity_drop,
    )
    rule_score = _calculate_rule_score(
        weather_score=weather["weather_score"],
        news_confidence=news_confidence,
        location_match=location_match,
        activity_drop=activity_drop,
        fraud_passed=fraud_passed,
    )
    final_score = (
        (Decimal("0.35") * _weight_value(ai_score))
        + (Decimal("0.25") * _weight_value(weather["weather_score"]))
        + (Decimal("0.20") * _weight_value(location_match))
        + (Decimal("0.20") * _weight_value(activity_drop))
    ).quantize(FOURPLACES, rounding=ROUND_HALF_UP)

    status = "APPROVED" if final_score > Decimal("0.7000") else "REJECTED"
    if not fraud_passed:
        status = "REJECTED_FRAUD"

    average_income = calculate_average_income_per_hour(partner)
    daily_income_cap = calculate_daily_income_cap(partner)
    expected_hours = Decimal("8.00")
    actual_hours = _quantize(expected_hours * Decimal(str(max(0.0, 1 - activity_drop))))
    loss_hours = _quantize(max(expected_hours - actual_hours, Decimal("0.00")))
    payout_amount = Decimal("0.00")
    if status == "APPROVED":
        payout_amount = _quantize(average_income * loss_hours * CRISIS_INDEX[severity])
        payout_amount = min(payout_amount, daily_income_cap)

    audit = [
        {
            "signal": "AI Analysis",
            "detail": (
                f"AI detected {event_type} event with {float(top_ai_analysis.get('confidence') or 0.0):.2f} confidence"
                f" and {severity} severity"
                + (
                    " after weather boost"
                    if top_ai_analysis.get("boost_reason") == "weather_boost"
                    else ""
                )
            ),
            "passed": ai_score >= 0.5,
            "score": round(ai_score, 4),
            "event_type": event_type,
            "severity": severity,
            "source": top_ai_analysis.get("source"),
        },
        {
            "signal": "Real News Validation",
            "detail": (
                f"{validation['reason']} | matched "
                f"{validation.get('matched_news', {}).get('title') or 'no supporting article'}"
            ),
            "passed": validation["is_valid"],
            "score": validation["score"],
            "threshold": validation["threshold"],
            "matched_news": validation.get("matched_news") or {},
            "requires_validation": validation["requires_validation"],
            "validation_summary": {
                "city": validation["city"],
                "reason": validation["reason"],
                "threshold": validation["threshold"],
                "score": validation["score"],
                "is_valid": validation["is_valid"],
                "matched_title": validation.get("matched_news", {}).get("title"),
                "matched_source": validation.get("matched_news", {}).get("source"),
                "matched_similarity": validation.get("matched_news", {}).get("similarity"),
                "matched_confidence": validation.get("matched_news", {}).get("ai_confidence"),
            },
        },
        {
            "signal": "Weather API",
            "detail": (
                "Weather confirmed high rainfall"
                if float(weather.get("rainfall") or 0.0) >= 25
                else f"rain {weather['rainfall']} mm, temp {weather['temperature']}°C"
            ),
            "passed": weather["weather_score"] >= 0.5,
            "score": weather["weather_score"],
        },
        {
            "signal": "News API",
            "detail": (
                f"{len(enriched_items)} article(s) analyzed"
                + (
                    f" - {', '.join([item['title'] for item in news_preview if item.get('title')][:3])}"
                    if news_preview
                    else " - No relevant city news"
                )
            ),
            "passed": news_confidence >= 0.6,
            "score": news_confidence,
            "articles": news_preview,
        },
        {
            "signal": "Location Match",
            "detail": (
                "Location within 5km"
                if distance is not None and distance <= 5
                else f"{distance} km from event zone" if distance is not None else "City level match"
            ),
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
    audit.extend(
        [
            {
                "signal": "Adaptive Model",
                "detail": f"location {location_key} using learned weights",
                "passed": final_score > Decimal("0.7000"),
                "score": float(adaptive_score),
                "weights": {name: float(value) for name, value in adaptive_weights.items()},
            },
            {
                "signal": "Rule Engine",
                "detail": "Blended verification and signal thresholds",
                "passed": fraud_passed and rule_score >= Decimal("0.5000"),
                "score": float(rule_score),
            },
        ]
    )

    claim = ClaimRecord.objects.create(
        account=account,
        partner=partner,
        event_type=event_type,
        city=account.city or partner.city,
        region=account.region or map_city_to_region(account.city or partner.city),
        crisis_level=severity,
        status=status,
        final_score=float(final_score),
        ai_score=ai_score,
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
        metadata={
            "final_score": float(final_score),
            "ai_score": ai_score,
            "adaptive_score": float(adaptive_score),
            "rule_score": float(rule_score),
            "severity": severity,
            "event_type": event_type,
        },
    )

    update_weights_after_claim(
        claim,
        city=account.city or partner.city,
        latitude=account.latitude,
        longitude=account.longitude,
        weather_score=weather["weather_score"],
        news_confidence=news_confidence,
        location_match=location_match,
        activity_drop=activity_drop,
        adaptive_score=adaptive_score,
        rule_score=rule_score,
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
        "ai_score": claim.ai_score,
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
        "created_at": event.created_at.isoformat(),
    }
