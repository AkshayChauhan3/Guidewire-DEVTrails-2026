import json
from datetime import timedelta
from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone

from registor_and_login.models import DeliveryPartner
from sessions.models import SessionHistory

from .models import AdaptiveWeight, ClaimRecord, DemoNewsEvent, WeeklyPremiumSnapshot
from .services import (
    analyze_news_with_ai,
    auto_generate_claims_for_partner,
    calculate_or_collect_weekly_premium,
    evaluate_claim,
    ensure_premium_account,
    fetch_news_signals,
)


class PremiumAndClaimsTests(TestCase):
    def setUp(self):
        self.partner = DeliveryPartner.objects.create(
            full_name="Asha Kumar",
            dob="1998-01-15",
            gender="Female",
            phone="9999990001",
            email="asha@example.com",
            city="Mumbai",
            area="Andheri",
            pincode="400053",
            platform="Zomato",
            platform_id="Z-1001",
            device_type="Android",
            emergency_name="Ravi Kumar",
            emergency_phone="9999991111",
            upi_id="asha@upi",
            vehicle_type="Bike",
            vehicle_number="MH01AB1234",
            is_verified=True,
        )

        for day_offset in range(1, 8):
            SessionHistory.objects.create(
                partner=self.partner,
                history_date=timezone.localdate() - timedelta(days=day_offset),
                total_earned_amount="1400.00",
                total_working_hours="8.00",
                total_shifts=1,
            )

        SessionHistory.objects.create(
            partner=self.partner,
            history_date=timezone.localdate(),
            total_earned_amount="100.00",
            total_working_hours="1.00",
            total_shifts=1,
        )

    @patch("premiumandclaims.services._safe_json")
    def test_fetch_news_signals_includes_demo_and_newsapi_items(self, mock_safe_json):
        DemoNewsEvent.objects.create(
            city="Mumbai",
            area="Andheri",
            event_type="flood",
            severity="severe",
            headline="Andheri flood alert disrupts delivery lanes",
            summary="Simulated event for hackathon demo.",
            effective_date=timezone.localdate(),
            is_active=True,
            source="demo-generator",
        )
        mock_safe_json.return_value = {
            "articles": [
                {
                    "title": "Mumbai protest slows food delivery routes",
                    "description": "Traffic block reported near western suburbs",
                    "publishedAt": timezone.now().isoformat(),
                    "url": "https://example.com/mumbai-protest",
                    "source": {"name": "City Desk"},
                }
            ]
        }

        signals = fetch_news_signals("Mumbai")

        self.assertGreaterEqual(len(signals), 2)
        self.assertEqual(signals[0]["source"], "demo-generator")
        self.assertTrue(any(item["source"] == "City Desk" for item in signals))

    @patch("premiumandclaims.services.fetch_weather_snapshot")
    @patch("premiumandclaims.services.fetch_news_signals")
    def test_auto_generated_claims_are_deduplicated(self, mock_fetch_news, mock_weather):
        now_iso = timezone.now().isoformat()
        mock_weather.return_value = {
            "city": "Mumbai",
            "region_label": "Maharashtra",
            "country": "India",
            "temperature": 34.0,
            "humidity": 78,
            "wind_speed": 18.0,
            "rainfall": 48.0,
            "condition": "flood rain",
            "last_updated": now_iso,
            "source": "weatherapi",
            "weather_score": 0.88,
        }
        mock_fetch_news.return_value = [
            {
                "title": "Mumbai flood alert disrupts rider movement",
                "source": "demo-generator",
                "description": "Roads waterlogged in key zones",
                "event_type": "flood",
                "severity": "severe",
                "published_at": now_iso,
                "event_location": {"latitude": None, "longitude": None},
                "signature": "demo-flood-mumbai",
            }
        ]

        created_first = auto_generate_claims_for_partner(self.partner, city="Mumbai")
        created_second = auto_generate_claims_for_partner(self.partner, city="Mumbai")

        self.assertGreaterEqual(len(created_first), 1)
        self.assertEqual(created_second, [])
        self.assertEqual(ClaimRecord.objects.filter(partner=self.partner, auto_created=True).count(), 2)

    @patch("premiumandclaims.views.auto_generate_claims_for_partner", return_value=[])
    def test_demo_event_broadcasts_to_all_partners_in_location_without_phone(self, mock_auto_generate):
        DeliveryPartner.objects.create(
            full_name="Rahul Patil",
            dob="1997-06-10",
            gender="Male",
            phone="9999990002",
            email="rahul@example.com",
            city="Mumbai",
            area="Andheri",
            pincode="400053",
            platform="Swiggy",
            platform_id="S-2002",
            device_type="Android",
            emergency_name="Meena Patil",
            emergency_phone="9999992222",
            upi_id="rahul@upi",
            vehicle_type="Bike",
            vehicle_number="MH01CD5678",
            is_verified=True,
        )
        DeliveryPartner.objects.create(
            full_name="Neha Sharma",
            dob="1996-03-22",
            gender="Female",
            phone="9999990003",
            email="neha@example.com",
            city="Mumbai",
            area="Bandra",
            pincode="400050",
            platform="Zomato",
            platform_id="Z-3003",
            device_type="Android",
            emergency_name="Rakesh Sharma",
            emergency_phone="9999993333",
            upi_id="neha@upi",
            vehicle_type="Scooter",
            vehicle_number="MH01EF9012",
            is_verified=True,
        )

        response = self.client.post(
            "/api/demo-events/",
            data=json.dumps(
                {
                    "city": "Mumbai",
                    "area": "Andheri",
                    "event_type": "flood",
                    "severity": "severe",
                    "headline": "Andheri flood alert disrupts delivery lanes",
                    "summary": "Simulated event for location-wide testing.",
                    "source": "demo-generator",
                    "is_active": True,
                }
            ),
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["claims_count"], 0)
        self.assertEqual(mock_auto_generate.call_count, 3)
        self.assertEqual(DemoNewsEvent.objects.count(), 1)

    @patch("premiumandclaims.views.auto_generate_claims_for_partner", return_value=[])
    def test_demo_event_targets_all_partners(
        self,
        mock_auto_generate,
    ):
        DeliveryPartner.objects.create(
            full_name="Rahul Patil",
            dob="1997-06-10",
            gender="Male",
            phone="9999990002",
            email="rahul@example.com",
            city="Mumbai",
            area="Andheri",
            pincode="400053",
            platform="Swiggy",
            platform_id="S-2002",
            device_type="Android",
            emergency_name="Meena Patil",
            emergency_phone="9999992222",
            upi_id="rahul@upi",
            vehicle_type="Bike",
            vehicle_number="MH01CD5678",
            is_verified=True,
        )
        DeliveryPartner.objects.create(
            full_name="Neha Sharma",
            dob="1996-03-22",
            gender="Female",
            phone="9999990003",
            email="neha@example.com",
            city="Mumbai",
            area="Bandra",
            pincode="400050",
            platform="Zomato",
            platform_id="Z-3003",
            device_type="Android",
            emergency_name="Rakesh Sharma",
            emergency_phone="9999993333",
            upi_id="neha@upi",
            vehicle_type="Scooter",
            vehicle_number="MH01EF9012",
            is_verified=True,
        )

        response = self.client.post(
            "/api/demo-events/",
            data=json.dumps(
                {
                    "city": "Mumbai",
                    "area": "Andheri",
                    "event_type": "flood",
                    "severity": "severe",
                    "headline": "Mumbai flood alert disrupts delivery lanes",
                    "summary": "Simulated event for same-area targeting.",
                    "source": "demo-generator",
                    "is_active": True,
                }
            ),
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["claims_count"], 0)
        self.assertEqual(mock_auto_generate.call_count, 3)
        targeted_areas = [call.args[0].area for call in mock_auto_generate.call_args_list]
        self.assertIn("Andheri", targeted_areas)
        self.assertIn("Bandra", targeted_areas)

    def test_demo_event_publishes_even_without_matching_partners(self):
        response = self.client.post(
            "/api/demo-events/",
            data=json.dumps(
                {
                    "city": "Pune",
                    "area": "Koregaon Park",
                    "event_type": "flood",
                    "severity": "severe",
                    "headline": "Pune flood alert disrupts delivery lanes",
                    "summary": "Simulated event for location-agnostic testing.",
                    "source": "demo-generator",
                    "is_active": True,
                }
            ),
            content_type="application/json",
            HTTP_HOST="127.0.0.1",
        )

        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertEqual(payload["claims_count"], 1)
        self.assertEqual(payload["event"]["city"], "Pune")
        self.assertGreaterEqual(DemoNewsEvent.objects.filter(city__iexact="Pune").count(), 1)

    def test_admin_summary_returns_collected_credited_and_claim_totals(self):
        account = ensure_premium_account(self.partner)
        account.wallet_balance = Decimal("2500.00")
        account.save(update_fields=["wallet_balance", "updated_at"])

        from .models import PremiumLedger

        PremiumLedger.objects.create(
            account=account,
            entry_type="premium_debit",
            amount=Decimal("125.50"),
            direction="debit",
            status="success",
            reference="premium-test-1",
            description="Premium collected",
        )
        PremiumLedger.objects.create(
            account=account,
            entry_type="payout_credit",
            amount=Decimal("45.25"),
            direction="credit",
            status="success",
            reference="payout-test-1",
            description="Payout credited",
        )

        ClaimRecord.objects.create(
            account=account,
            partner=self.partner,
            event_type="flood",
            city="Mumbai",
            region="west",
            crisis_level="severe",
            status="APPROVED",
        )
        ClaimRecord.objects.create(
            account=account,
            partner=self.partner,
            event_type="strike",
            city="Mumbai",
            region="west",
            crisis_level="moderate",
            status="REJECTED",
        )

        response = self.client.get("/api/admin/summary/", HTTP_HOST="127.0.0.1")

        self.assertEqual(response.status_code, 200)
        summary = response.json()["summary"]
        self.assertEqual(summary["money_collected"], 125.5)
        self.assertEqual(summary["money_credited"], 45.25)
        self.assertEqual(summary["claims_generated"], 2)
        self.assertEqual(summary["claims_by_status"]["approved"], 1)
        self.assertEqual(summary["claims_by_status"]["rejected"], 1)

    @patch("premiumandclaims.services.fetch_weather_snapshot")
    @patch("premiumandclaims.services.fetch_news_signals")
    @patch("premiumandclaims.services.fetch_real_news_signals")
    @patch("premiumandclaims.services.analyze_news_with_ai")
    def test_evaluate_claim_updates_adaptive_weights(
        self,
        mock_ai,
        mock_real_news,
        mock_fetch_news,
        mock_weather,
    ):
        now_iso = timezone.now().isoformat()
        mock_weather.return_value = {
            "city": "Mumbai",
            "region_label": "Maharashtra",
            "country": "India",
            "temperature": 33.0,
            "humidity": 70,
            "wind_speed": 14.0,
            "rainfall": 42.0,
            "condition": "heavy rain",
            "last_updated": now_iso,
            "source": "weatherapi",
            "weather_score": 0.9,
        }
        mock_fetch_news.return_value = [
            {
                "title": "Mumbai flood alert disrupts rider movement",
                "source": "demo-generator",
                "description": "Roads waterlogged in key zones",
                "event_type": "flood",
                "severity": "severe",
                "published_at": now_iso,
                "event_location": {"latitude": None, "longitude": None},
                "signature": "demo-flood-mumbai",
            }
        ]
        mock_real_news.return_value = [
            {
                "title": "Mumbai flood alert disrupts rider movement",
                "source": "City Desk",
                "description": "Roads waterlogged in key zones",
                "event_type": "flood",
                "severity": "severe",
                "published_at": now_iso,
                "event_location": {"latitude": None, "longitude": None},
                "url": "https://example.com/mumbai-flood",
                "signature": "newsapi-mumbai-flood",
            }
        ]
        mock_ai.return_value = {
            "event_type": "flood",
            "severity": "severe",
            "confidence": 0.82,
            "ai_score": 0.88,
            "source": "huggingface",
            "text": "Mumbai flood alert disrupts rider movement Roads waterlogged in key zones",
        }

        claim = evaluate_claim(
            self.partner,
            city="Mumbai",
            latitude=19.0760,
            longitude=72.8777,
            notification_match=True,
            cell_tower_verified=True,
            motion_pattern_valid=True,
        )

        self.assertEqual(claim.status, "APPROVED")
        self.assertGreater(claim.ai_score, 0.7)
        self.assertTrue(any(item.get("signal") == "AI Analysis" for item in claim.audit))
        self.assertTrue(AdaptiveWeight.objects.filter(location_key="global").exists())
        self.assertTrue(
            AdaptiveWeight.objects.filter(location_key="mumbai").exists()
            or AdaptiveWeight.objects.filter(location_key__startswith="lat_").exists()
        )

    def test_analyze_news_with_ai_falls_back_without_model(self):
        result = analyze_news_with_ai("Severe flood warning issued for Mumbai")

        self.assertEqual(result["event_type"], "flood")
        self.assertEqual(result["severity"], "severe")
        self.assertGreater(result["confidence"], 0.0)

    @patch("premiumandclaims.services.fetch_weather_snapshot")
    @patch("premiumandclaims.services.fetch_real_news_signals")
    @patch("premiumandclaims.services.fetch_news_signals")
    @patch("premiumandclaims.services.analyze_news_with_ai")
    def test_synthetic_claim_is_rejected_without_real_news(self, mock_ai, mock_news, mock_real_news, mock_weather):
        mock_weather.return_value = {
            "city": "Mumbai",
            "region_label": "Maharashtra",
            "country": "India",
            "temperature": 33.0,
            "humidity": 70,
            "wind_speed": 14.0,
            "rainfall": 40.0,
            "condition": "heavy rain",
            "last_updated": timezone.now().isoformat(),
            "source": "weatherapi",
            "weather_score": 0.9,
        }
        mock_news.return_value = []
        mock_real_news.return_value = []
        mock_ai.return_value = {
            "event_type": "flood",
            "severity": "severe",
            "confidence": 0.95,
            "ai_score": 0.9,
            "source": "huggingface",
            "text": "Fake flood headline",
        }

        claim = evaluate_claim(
            self.partner,
            city="Mumbai",
            latitude=19.0760,
            longitude=72.8777,
            trigger_signal={
                "title": "Fake flood headline",
                "description": "Synthetic demo news",
                "source": "web-ui-gen",
                "event_type": "flood",
                "severity": "severe",
            },
            auto_created=True,
            trigger_source="web-ui-gen",
        )

        self.assertEqual(claim.status, "REJECTED_FRAUD")
        self.assertEqual(claim.payout_amount, Decimal("0.00"))
        self.assertTrue(
            any(
                item.get("signal") == "Real News Validation"
                and item.get("passed") is False
                for item in claim.audit
            )
        )

    @patch("premiumandclaims.services.fetch_weather_snapshot")
    @patch("premiumandclaims.services.fetch_news_signals")
    @patch("premiumandclaims.services.fetch_real_news_signals")
    @patch("premiumandclaims.services.analyze_news_with_ai")
    def test_evaluate_claim_averages_multiple_ai_signals_and_boosts_floods(
        self,
        mock_ai,
        mock_real_news,
        mock_fetch_news,
        mock_weather,
    ):
        now_iso = timezone.now().isoformat()
        mock_weather.return_value = {
            "city": "Mumbai",
            "region_label": "Maharashtra",
            "country": "India",
            "temperature": 32.0,
            "humidity": 82,
            "wind_speed": 11.0,
            "rainfall": 49.0,
            "condition": "heavy rain",
            "last_updated": now_iso,
            "source": "weatherapi",
            "weather_score": 0.92,
        }
        mock_fetch_news.return_value = [
            {"title": "Mumbai flood alert", "description": "Roads waterlogged", "source": "demo"},
            {"title": "City protest update", "description": "Traffic delayed", "source": "demo"},
            {"title": "Heatwave advisory", "description": "Stay hydrated", "source": "demo"},
        ]
        mock_real_news.return_value = [
            {
                "title": "Mumbai flood alert",
                "description": "Roads waterlogged",
                "source": "City Desk",
                "ai_analysis": {
                    "event_type": "flood",
                    "severity": "severe",
                    "confidence": 0.80,
                    "ai_score": 0.72,
                    "source": "huggingface",
                    "text": "Mumbai flood alert Roads waterlogged",
                    "boost_reason": "weather_boost",
                },
            },
            {
                "title": "City protest update",
                "description": "Traffic delayed",
                "source": "Metro News",
                "ai_analysis": {
                    "event_type": "protest",
                    "severity": "moderate",
                    "confidence": 0.70,
                    "ai_score": 0.56,
                    "source": "huggingface",
                    "text": "City protest update Traffic delayed",
                    "boost_reason": None,
                },
            },
            {
                "title": "Heatwave advisory",
                "description": "Stay hydrated",
                "source": "Metro News",
                "ai_analysis": {
                    "event_type": "heatwave",
                    "severity": "moderate",
                    "confidence": 0.60,
                    "ai_score": 0.42,
                    "source": "huggingface",
                    "text": "Heatwave advisory Stay hydrated",
                    "boost_reason": None,
                },
            },
        ]
        mock_ai.return_value = {
            "event_type": "flood",
            "severity": "severe",
            "confidence": 0.80,
            "ai_score": 0.72,
            "source": "huggingface",
            "text": "unused",
            "boost_reason": "weather_boost",
        }

        claim = evaluate_claim(
            self.partner,
            city="Mumbai",
            latitude=19.0760,
            longitude=72.8777,
            notification_match=True,
            cell_tower_verified=True,
            motion_pattern_valid=True,
        )

        self.assertGreater(claim.ai_score, 0.55)
        self.assertTrue(
            any(
                item.get("signal") == "AI Analysis"
                and "weather boost" in str(item.get("detail", "")).lower()
                for item in claim.audit
            )
        )

    @patch("premiumandclaims.services.calculate_daily_income_cap")
    @patch("premiumandclaims.services.calculate_weekly_metrics")
    @patch("premiumandclaims.services.fetch_weather_snapshot")
    @patch("premiumandclaims.services.fetch_real_news_signals")
    def test_weekly_premium_is_capped_to_daily_average(
        self,
        mock_real_news,
        mock_weather,
        mock_weekly_metrics,
        mock_daily_cap,
    ):
        mock_weekly_metrics.return_value = {
            "weekly_income": Decimal("14000.00"),
            "total_hours": Decimal("40.00"),
            "weekend_hours": Decimal("8.00"),
            "category": "full_time",
            "week_start": timezone.localdate() - timedelta(days=6),
            "week_end": timezone.localdate(),
        }
        mock_daily_cap.return_value = Decimal("250.00")
        mock_weather.return_value = {
            "city": "Mumbai",
            "region_label": "Maharashtra",
            "country": "India",
            "temperature": 33.0,
            "humidity": 80,
            "wind_speed": 18.0,
            "rainfall": 44.0,
            "condition": "heavy rain",
            "last_updated": timezone.now().isoformat(),
            "source": "weatherapi",
            "weather_score": 0.91,
        }
        mock_real_news.return_value = [
            {
                "title": "Mumbai flood alert disrupts rider movement",
                "source": "City Desk",
                "description": "Roads waterlogged in key zones",
                "event_type": "flood",
                "severity": "severe",
                "published_at": timezone.now().isoformat(),
                "event_location": {"latitude": None, "longitude": None},
                "signature": "newsapi-mumbai-flood",
            }
        ]

        result = calculate_or_collect_weekly_premium(self.partner, collect=False)

        self.assertLessEqual(result["snapshot"].premium_amount, Decimal("250.00"))
        self.assertEqual(result["daily_income_cap"], float(Decimal("250.00")))

    @patch("premiumandclaims.services.calculate_daily_income_cap")
    @patch("premiumandclaims.services.calculate_weekly_metrics")
    @patch("premiumandclaims.services.fetch_weather_snapshot")
    @patch("premiumandclaims.services.fetch_real_news_signals")
    def test_weekly_premium_collect_is_idempotent_and_keeps_deduction_mark(
        self,
        mock_real_news,
        mock_weather,
        mock_weekly_metrics,
        mock_daily_cap,
    ):
        fixed_date = timezone.localdate()
        week_start = fixed_date - timedelta(days=6)
        mock_weekly_metrics.return_value = {
            "weekly_income": Decimal("14000.00"),
            "total_hours": Decimal("40.00"),
            "weekend_hours": Decimal("8.00"),
            "category": "full_time",
            "week_start": week_start,
            "week_end": fixed_date,
        }
        mock_daily_cap.return_value = Decimal("5000.00")
        mock_weather.return_value = {
            "city": "Mumbai",
            "region_label": "Maharashtra",
            "country": "India",
            "temperature": 33.0,
            "humidity": 80,
            "wind_speed": 18.0,
            "rainfall": 44.0,
            "condition": "heavy rain",
            "last_updated": timezone.now().isoformat(),
            "source": "weatherapi",
            "weather_score": 0.91,
        }
        mock_real_news.return_value = [
            {
                "title": "Mumbai flood alert disrupts rider movement",
                "source": "City Desk",
                "description": "Roads waterlogged in key zones",
                "event_type": "flood",
                "severity": "severe",
                "published_at": timezone.now().isoformat(),
                "event_location": {"latitude": None, "longitude": None},
                "signature": "newsapi-mumbai-flood",
            }
        ]

        account = ensure_premium_account(self.partner)
        account.wallet_balance = Decimal("5000.00")
        account.save(update_fields=["wallet_balance", "updated_at"])

        first = calculate_or_collect_weekly_premium(
            self.partner,
            collect=True,
            today=fixed_date,
        )
        first_amount = first["snapshot"].premium_amount
        account.refresh_from_db()
        balance_after_first = account.wallet_balance

        second = calculate_or_collect_weekly_premium(
            self.partner,
            collect=True,
            today=fixed_date,
        )
        account.refresh_from_db()

        preview = calculate_or_collect_weekly_premium(
            self.partner,
            collect=False,
            today=fixed_date,
        )
        snapshot = WeeklyPremiumSnapshot.objects.get(
            partner=self.partner,
            week_start=week_start,
        )

        self.assertEqual(first["payment_status"], "debited")
        self.assertEqual(second["payment_status"], "already_debited")
        self.assertEqual(balance_after_first, Decimal("5000.00") - first_amount)
        self.assertEqual(account.wallet_balance, balance_after_first)
        self.assertEqual(preview["payment_status"], "preview")
        self.assertIsNotNone(snapshot.deducted_on)
