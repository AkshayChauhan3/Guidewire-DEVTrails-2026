import logging

from django.db.models import Count, Q, Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from registor_and_login.models import DeliveryPartner

from .models import DemoNewsEvent
from .models import ClaimRecord, PremiumLedger
from .services import (
    auto_generate_claims_for_partner,
    calculate_or_collect_weekly_premium,
    ensure_premium_account,
    evaluate_claim,
    fetch_news_signals,
    fetch_weather_snapshot,
    reverse_geocode_city,
    reverse_geocode_location,
    serialize_claim,
    serialize_demo_event,
    serialize_ledger_entry,
    sync_account_location,
)

logger = logging.getLogger(__name__)


def _get_partner(phone: str):
    return DeliveryPartner.objects.filter(phone=phone).first()


def _get_partners_for_location(city: str, area: str | None = None):
    partners = DeliveryPartner.objects.filter(city__iexact=city.strip())
    area = (area or "").strip()
    if area:
        partners = partners.filter(area__iexact=area)
    return partners.order_by("id")


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
        city = (request.query_params.get("city") or "").strip() or None

        if latitude and longitude:
            lat_f = float(latitude)
            lon_f = float(longitude)
            # Auto-resolve city from coordinates if not explicitly provided
            if not city:
                city = reverse_geocode_city(lat_f, lon_f)
            sync_account_location(
                account,
                city=city,
                latitude=lat_f,
                longitude=lon_f,
            )

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
                    "daily_income_cap": premium_data.get("daily_income_cap"),
                    "total_hours": float(snapshot.total_hours),
                    "weekend_hours": float(snapshot.weekend_hours),
                    "category": snapshot.category,
                    "region": snapshot.region,
                    "region_rate": premium_data["region_rate"],
                    "category_multiplier": premium_data["category_multiplier"],
                    "weather_score": snapshot.weather_score,
                    "weather_multiplier": snapshot.weather_multiplier,
                    "premium_amount": float(snapshot.premium_amount),
                    "base_premium": premium_data.get("base_premium"),
                    "adaptive_score": premium_data.get("adaptive_score"),
                    "rule_score": premium_data.get("rule_score"),
                    "location_key": premium_data.get("location_key"),
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
                "message": "AI hybrid protection check completed",
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
        city = (request.data.get("city") or "").strip()
        area = (request.data.get("area") or "").strip()
        event_type = (request.data.get("event_type") or "").strip()
        headline = (request.data.get("headline") or "").strip()
        
        if not event_type or not headline:
            return Response({"message": "event_type and headline are required"}, status=status.HTTP_400_BAD_REQUEST)

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

        # Demo/news events are global blasts in this mode, so every partner receives the trigger.
        target_partners = DeliveryPartner.objects.order_by("id")
        first_partner = target_partners.first()

        # ✅ Fast create - minimal fields
        event = DemoNewsEvent.objects.create(
            city=city,
            area=area or (first_partner.area if first_partner else "") or "",
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
        
        # ✅ Auto-generate claims for every partner in the system.
        generated_claims = []
        claim_errors: list[dict[str, str]] = []
        for target_partner in target_partners:
            try:
                generated_claims.extend(
                    auto_generate_claims_for_partner(
                        target_partner,
                        city=city,
                        latitude=event_latitude,
                        longitude=event_longitude,
                    )
                )
            except Exception as exc:  # pragma: no cover - defensive guard for demo publishing
                logger.exception(
                    "Failed to auto-generate claims for partner %s while publishing demo event %s",
                    target_partner.id,
                    event.id,
                )
                claim_errors.append(
                    {
                        "partner_id": str(target_partner.id),
                        "message": str(exc),
                    }
                )
        
        # ✅ Return event + generated claims with full status
        response_body = {
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
        }
        if claim_errors:
            response_body["claim_errors"] = claim_errors
            response_body["message"] = "Event published, but some claim generations failed"

        return Response(
            response_body,
            status=status.HTTP_201_CREATED
        )


class AdminSummaryView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        collected = PremiumLedger.objects.filter(entry_type="premium_debit").aggregate(
            total=Sum("amount"),
            count=Count("id"),
        )
        credited = PremiumLedger.objects.filter(entry_type="payout_credit").aggregate(
            total=Sum("amount"),
            count=Count("id"),
        )
        claims = ClaimRecord.objects.aggregate(
            total=Count("id"),
            approved=Count("id", filter=Q(status="APPROVED")),
            rejected=Count("id", filter=Q(status="REJECTED")),
            rejected_fraud=Count("id", filter=Q(status="REJECTED_FRAUD")),
        )
        accounts = {
            "count": PremiumLedger.objects.values("account_id").distinct().count(),
        }

        collected_total = collected["total"] or 0
        credited_total = credited["total"] or 0

        return Response(
            {
                "success": True,
                "summary": {
                    "money_collected": float(collected_total),
                    "money_credited": float(credited_total),
                    "claims_generated": claims["total"] or 0,
                    "claims_by_status": {
                        "approved": claims["approved"] or 0,
                        "rejected": claims["rejected"] or 0,
                        "rejected_fraud": claims["rejected_fraud"] or 0,
                    },
                    "ledger_counts": {
                        "premium_debit": collected["count"] or 0,
                        "payout_credit": credited["count"] or 0,
                    },
                    "net_balance": float(collected_total - credited_total),
                    "accounts_touched": accounts["count"],
                    "updated_at": timezone.now().isoformat(),
                },
            }
        )
