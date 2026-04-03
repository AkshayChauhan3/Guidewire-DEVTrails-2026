from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from registor_and_login.models import DeliveryPartner
from premiumandclaims.services import (
    auto_generate_claims_for_partner,
    fetch_news_signals,
    fetch_weather_snapshot,
)


def _clean_city(raw_city):
    city = (raw_city or "").strip()
    return city or "Mumbai"


def _resolve_city(phone=None, city=None):
    requested_city = _clean_city(city)
    if city:
        return requested_city

    if phone:
        partner = DeliveryPartner.objects.filter(phone=phone).only("city").first()
        if partner and partner.city:
            return _clean_city(partner.city)

    return requested_city


class CityDataView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        phone = request.query_params.get("phone")
        city = _resolve_city(phone=phone, city=request.query_params.get("city"))
        if phone:
            partner = DeliveryPartner.objects.filter(phone=phone).first()
            if partner:
                auto_generate_claims_for_partner(partner, city=city)

        weather = fetch_weather_snapshot(city)
        news = fetch_news_signals(weather.get("city") or city)

        return Response(
            {
                "success": True,
                "city": weather.get("city") or city,
                "weather": {
                    "city": weather.get("city") or city,
                    "region": weather.get("region_label") or "",
                    "country": weather.get("country") or "",
                    "temp_c": weather.get("temperature"),
                    "feelslike_c": weather.get("temperature"),
                    "humidity": weather.get("humidity"),
                    "wind_kph": weather.get("wind_speed"),
                    "precip_mm": weather.get("rainfall"),
                    "condition": weather.get("condition"),
                    "icon": "",
                    "last_updated": weather.get("last_updated"),
                    "weather_score": weather.get("weather_score"),
                },
                "news": [
                    {
                        "title": item.get("title") or "No title",
                        "source": item.get("source") or "",
                        "description": item.get("description") or "",
                        "url": item.get("url") or "",
                        "published_at": item.get("published_at"),
                        "event_type": item.get("event_type"),
                        "severity": item.get("severity"),
                    }
                    for item in news
                ],
                "errors": {},
            }
        )
