from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from registor_and_login.models import DeliveryPartner

from .models import DemoNewsEvent
from .services import (
    auto_generate_claims_for_partner,
    calculate_or_collect_weekly_premium,
    ensure_premium_account,
    evaluate_claim,
    fetch_news_signals,
    fetch_weather_snapshot,
    get_city_coordinates,
    serialize_claim,
    serialize_demo_event,
    serialize_ledger_entry,
    sync_account_location,
)


def _get_partner(phone: str):
    return DeliveryPartner.objects.filter(phone=phone).first()


class PremiumSummaryView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        phone = (request.query_params.get("phone") or "").strip()
        if not phone:
            return Response({"message": "phone is required"}, status=status.HTTP_400_BAD_REQUEST)

        partner = _get_partner(phone)
        if not partner:
            return Response({"message": "User not found"}, status=status.HTTP_404_NOT_FOUND)

        account = ensure_premium_account(partner)
        latitude = request.query_params.get("latitude")
        longitude = request.query_params.get("longitude")
        if latitude and longitude:
            sync_account_location(account, latitude=float(latitude), longitude=float(longitude))

        collect = request.query_params.get("collect") == "true"
        premium_data = calculate_or_collect_weekly_premium(partner, collect=collect)
        snapshot = premium_data["snapshot"]

        return Response(
            {
                "success": True,
                "wallet_balance": float(premium_data["account"].wallet_balance),
                "testing_bonus": float(premium_data["account"].testing_bonus),
                "payment_status": premium_data["payment_status"],
                "premium": {
                    "week_start": snapshot.week_start.isoformat(),
                    "week_end": snapshot.week_end.isoformat(),
                    "weekly_income": float(snapshot.weekly_income),
                    "total_hours": float(snapshot.total_hours),
                    "weekend_hours": float(snapshot.weekend_hours),
                    "category": snapshot.category,
                    "region": snapshot.region,
                    "region_rate": premium_data["region_rate"],
                    "category_multiplier": premium_data["category_multiplier"],
                    "weather_score": snapshot.weather_score,
                    "weather_multiplier": snapshot.weather_multiplier,
                    "premium_amount": float(snapshot.premium_amount),
                    "deducted_on": snapshot.deducted_on.isoformat() if snapshot.deducted_on else None,
                },
                "weather": premium_data["weather"],
                "recent_ledger": [
                    serialize_ledger_entry(entry)
                    for entry in premium_data["account"].ledger_entries.all()[:5]
                ],
            }
        )


class ClaimsDashboardView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        phone = (request.query_params.get("phone") or "").strip()
        if not phone:
            return Response({"message": "phone is required"}, status=status.HTTP_400_BAD_REQUEST)

        partner = _get_partner(phone)
        if not partner:
            return Response({"message": "User not found"}, status=status.HTTP_404_NOT_FOUND)

        account = ensure_premium_account(partner)
        created_claims = auto_generate_claims_for_partner(partner)
        account.refresh_from_db()
        active_events = [
            serialize_demo_event(event)
            for event in DemoNewsEvent.objects.filter(
                city__iexact=account.city or partner.city,
                is_active=True,
                effective_date__lte=timezone.localdate(),
            )[:5]
        ]
        # ✅ Return all claims, sorted newest first (not limited to 10)
        claims = [serialize_claim(claim) for claim in account.claims.all().order_by('-created_at')]

        return Response(
            {
                "success": True,
                "wallet_balance": float(account.wallet_balance),
                "active_events": active_events,
                "auto_generated_claims": [serialize_claim(claim) for claim in created_claims],
                "claims": claims,
                "news_signals": fetch_news_signals(account.city or partner.city),
                "weather": fetch_weather_snapshot(account.city or partner.city),
                "recent_ledger": [serialize_ledger_entry(entry) for entry in account.ledger_entries.all()[:8]],
            }
        )


class SubmitClaimView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        phone = (request.data.get("phone") or "").strip()
        if not phone:
            return Response({"message": "phone is required"}, status=status.HTTP_400_BAD_REQUEST)

        partner = _get_partner(phone)
        if not partner:
            return Response({"message": "User not found"}, status=status.HTTP_404_NOT_FOUND)

        latitude = request.data.get("latitude")
        longitude = request.data.get("longitude")
        city = (request.data.get("city") or "").strip() or None

        latitude_value = float(latitude) if latitude not in (None, "") else None
        longitude_value = float(longitude) if longitude not in (None, "") else None
        created_claims = auto_generate_claims_for_partner(
            partner,
            latitude=latitude_value,
            longitude=longitude_value,
            city=city,
        )
        claim = created_claims[0] if created_claims else evaluate_claim(
            partner,
            latitude=latitude_value,
            longitude=longitude_value,
            city=city,
            notification_match=str(request.data.get("notification_match", "true")).lower() != "false",
            cell_tower_verified=str(request.data.get("cell_tower_verified", "true")).lower() != "false",
            motion_pattern_valid=str(request.data.get("motion_pattern_valid", "true")).lower() != "false",
            auto_created=True,
            trigger_source="manual-sync",
            trigger_title="Manual sync fallback",
        )

        return Response(
            {
                "success": True,
                "message": "Automatic protection check completed",
                "claim": serialize_claim(claim),
                "wallet_balance": float(claim.account.wallet_balance),
            },
            status=status.HTTP_201_CREATED,
        )


class DemoEventView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        city = (request.query_params.get("city") or "").strip()
        events = DemoNewsEvent.objects.all()
        if city:
            events = events.filter(city__iexact=city)
        return Response({"success": True, "events": [serialize_demo_event(event) for event in events[:20]]})

    def post(self, request):
        # ✅ Fast validation - fail early if required fields missing
        phone = (request.data.get("phone") or "").strip()
        city = (request.data.get("city") or "").strip()
        event_type = (request.data.get("event_type") or "").strip()
        headline = (request.data.get("headline") or "").strip()
        
        if not phone:
            return Response({"message": "phone is required"}, status=status.HTTP_400_BAD_REQUEST)
        if not event_type or not headline:
            return Response({"message": "event_type and headline are required"}, status=status.HTTP_400_BAD_REQUEST)

        # ✅ Get partner once (avoid multiple queries)
        partner = _get_partner(phone)
        if not partner:
            return Response({"message": "User not found"}, status=status.HTTP_404_NOT_FOUND)

        # ✅ Use provided city or fall back to partner's city
        if not city:
            city = partner.city or ""
        if not city:
            return Response({"message": "city is required"}, status=status.HTTP_400_BAD_REQUEST)

        severity = (request.data.get("severity") or "moderate").strip()
        
        # ✅ Optimize: Extract coordinates early
        event_latitude = None
        event_longitude = None
        
        try:
            if request.data.get("event_latitude") not in (None, ""):
                event_latitude = float(request.data["event_latitude"])
            if request.data.get("event_longitude") not in (None, ""):
                event_longitude = float(request.data["event_longitude"])
        except (ValueError, TypeError):
            pass

        # ✅ Skip premium account lookup if we already have coordinates
        if event_latitude is None or event_longitude is None:
            # Only fetch account if needed
            account = ensure_premium_account(partner)
            if account.latitude is not None and account.longitude is not None:
                event_latitude = event_latitude or account.latitude
                event_longitude = event_longitude or account.longitude

        # ✅ Fast create - minimal fields
        event = DemoNewsEvent.objects.create(
            city=city,
            area=(request.data.get("area") or "").strip() or partner.area or "",
            event_type=event_type,
            severity=severity,
            headline=headline,
            summary=(request.data.get("summary") or "").strip(),
            event_latitude=event_latitude,
            event_longitude=event_longitude,
            effective_date=request.data.get("effective_date") or timezone.localdate(),
            is_active=str(request.data.get("is_active", "true")).lower() != "false",
            source=(request.data.get("source") or "demo-generator").strip(),
        )
        
        # ✅ Auto-generate claims from this event so frontend can show them immediately
        generated_claims = auto_generate_claims_for_partner(
            partner,
            city=city,
            latitude=event_latitude,
            longitude=event_longitude,
        )
        
        # ✅ Return event + generated claims with full status
        return Response(
            {
                "success": True, 
                "event": {
                    "id": event.id,
                    "city": event.city,
                    "headline": event.headline,
                    "event_type": event.event_type,
                    "severity": event.severity,
                    "created_at": event.created_at.isoformat(),
                },
                "generated_claims": [serialize_claim(claim) for claim in generated_claims],
                "claims_count": len(generated_claims),
            }, 
            status=status.HTTP_201_CREATED
        )
