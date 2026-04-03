from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone

from registor_and_login.models import DeliveryPartner
from sessions.models import SessionHistory

from .models import ClaimRecord, DemoNewsEvent
from .services import auto_generate_claims_for_partner, fetch_news_signals


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
