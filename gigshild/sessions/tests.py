import base64
import json
from decimal import Decimal
from datetime import timedelta
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from registor_and_login.models import DeliveryPartner
from sessions.models import SessionHistory, WorkSession


class SessionImageUploadTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.partner = DeliveryPartner.objects.create(
            full_name="Test Partner",
            dob="2000-01-01",
            gender="Male",
            phone="9999999999",
            email="test@example.com",
            city="Indore",
            area="Vijay Nagar",
            pincode="452010",
            platform="Zomato",
            platform_id="Z-100",
            device_type="Android",
            emergency_name="Emergency Contact",
            emergency_phone="8888888888",
            upi_id="test@upi",
            vehicle_type="Bike",
            vehicle_number="MP09AB1234",
            is_verified=False,
        )
        self.partner.profile_image = SimpleUploadedFile(
            "profile.jpg",
            b"profile-image-bytes",
            content_type="image/jpeg",
        )
        self.partner.save()

    @patch("sessions.views.compare_faces", return_value={"match": True, "confidence": 0.95})
    def test_start_session_accepts_multipart_image(self, _mock_compare_faces):
        response = self.client.post(
            "/api/session/start/",
            data={
                "phone": self.partner.phone,
                "latitude": "22.7196",
                "longitude": "75.8577",
                "selfie_image": SimpleUploadedFile(
                    "selfie.jpg",
                    b"session-selfie-bytes",
                    content_type="image/jpeg",
                ),
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(WorkSession.objects.count(), 1)

    @patch("sessions.views.compare_faces", return_value={"match": True, "confidence": 0.95})
    def test_start_session_accepts_base64_image_payload(self, _mock_compare_faces):
        response = self.client.post(
            "/api/session/start/",
            data={
                "phone": self.partner.phone,
                "latitude": "22.7196",
                "longitude": "75.8577",
                "selfie_image": f"data:image/jpeg;base64,{base64.b64encode(b'session-selfie-bytes').decode()}",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(WorkSession.objects.count(), 1)

    @patch("sessions.views._extract_ocr_data")
    def test_session_history_saves_ocr_earnings_hours_and_shifts(self, mock_extract_ocr_data):
        history_date = timezone.localdate()
        now = timezone.now()

        WorkSession.objects.create(
            partner=self.partner,
            session_date=history_date,
            start_time=now - timedelta(hours=5),
            end_time=now - timedelta(hours=3),
            start_verified=True,
            end_verified=True,
            is_active=False,
        )
        WorkSession.objects.create(
            partner=self.partner,
            session_date=history_date,
            start_time=now - timedelta(hours=2),
            end_time=now - timedelta(minutes=30),
            start_verified=True,
            end_verified=True,
            is_active=False,
        )

        mock_extract_ocr_data.side_effect = [
            {
                "text": "Order A\nRs 120.50",
                "order_name": "Order A",
                "amounts": [Decimal("120.50")],
            },
            {
                "text": "Order B\n₹80",
                "order_name": "Order B",
                "amounts": [Decimal("80.00")],
            },
        ]

        response = self.client.post(
            "/api/session/history/",
            data={
                "phone": self.partner.phone,
                "date": str(history_date),
                "images": [
                    SimpleUploadedFile("one.png", b"image-one", content_type="image/png"),
                    SimpleUploadedFile("two.png", b"image-two", content_type="image/png"),
                ],
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(SessionHistory.objects.count(), 1)

        history = SessionHistory.objects.get(partner=self.partner, history_date=history_date)
        self.assertEqual(str(history.total_earned_amount), "200.50")
        self.assertEqual(str(history.total_working_hours), "3.50")
        self.assertEqual(history.total_shifts, 2)
        self.assertEqual(history.extracted_amounts, ["120.50", "80.00"])

    @patch("sessions.views._extract_ocr_data")
    def test_session_history_accepts_flutter_history_field_names(self, mock_extract_ocr_data):
        history_date = timezone.localdate()

        mock_extract_ocr_data.side_effect = [
            {
                "text": "Order A\nRs 120.50",
                "order_name": "Order A",
                "amounts": [Decimal("120.50")],
            },
            {
                "text": "Order B\n₹80",
                "order_name": "Order B",
                "amounts": [Decimal("80.00")],
            },
            {
                "text": "Order C\n₹60",
                "order_name": "Order C",
                "amounts": [Decimal("60.00")],
            },
        ]

        response = self.client.post(
            "/api/session/history/",
            data={
                "phone": self.partner.phone,
                "date": str(history_date),
                "history_image": SimpleUploadedFile(
                    "cover.png",
                    b"cover-image",
                    content_type="image/png",
                ),
                "history_images": [
                    SimpleUploadedFile("one.png", b"image-one", content_type="image/png"),
                    SimpleUploadedFile("two.png", b"image-two", content_type="image/png"),
                ],
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(SessionHistory.objects.count(), 1)

        history = SessionHistory.objects.get(partner=self.partner, history_date=history_date)
        self.assertEqual(str(history.total_earned_amount), "260.50")
        self.assertEqual(history.extracted_amounts, ["120.50", "80.00", "60.00"])

    @patch("sessions.views._extract_ocr_data")
    def test_session_history_deduplicates_same_file_across_supported_field_names(self, mock_extract_ocr_data):
        history_date = timezone.localdate()
        mock_extract_ocr_data.side_effect = [
            {
                "text": "Order A\nRs 120.50",
                "order_name": "Order A",
                "amounts": [Decimal("120.50")],
            },
            {
                "text": "Order B\n₹80",
                "order_name": "Order B",
                "amounts": [Decimal("80.00")],
            },
        ]

        cover = SimpleUploadedFile("cover.png", b"cover-image", content_type="image/png")
        cover_duplicate = SimpleUploadedFile(
            "cover.png",
            b"cover-image",
            content_type="image/png",
        )
        second = SimpleUploadedFile("two.png", b"image-two", content_type="image/png")

        response = self.client.post(
            "/api/session/history/",
            data={
                "phone": self.partner.phone,
                "date": str(history_date),
                "image": cover,
                "images": [cover_duplicate, second],
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(mock_extract_ocr_data.call_count, 2)

    @patch("sessions.views._extract_ocr_data")
    def test_session_history_skips_unreadable_images_when_others_are_valid(self, mock_extract_ocr_data):
        history_date = timezone.localdate()
        mock_extract_ocr_data.side_effect = [
            ValueError("Unsupported or corrupted image file"),
            {
                "text": "Order B\n₹80",
                "order_name": "Order B",
                "amounts": [Decimal("80.00")],
            },
        ]

        response = self.client.post(
            "/api/session/history/",
            data={
                "phone": self.partner.phone,
                "date": str(history_date),
                "images": [
                    SimpleUploadedFile("bad.png", b"bad-image", content_type="image/png"),
                    SimpleUploadedFile("good.png", b"good-image", content_type="image/png"),
                ],
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["warnings"][0]["file"], "bad.png")

        history = SessionHistory.objects.get(partner=self.partner, history_date=history_date)
        self.assertEqual(str(history.total_earned_amount), "80.00")
        self.assertEqual(history.extracted_amounts, ["80.00"])

    def test_session_history_accepts_client_ocr_payload_without_images(self):
        history_date = timezone.localdate()
        now = timezone.now()

        WorkSession.objects.create(
            partner=self.partner,
            session_date=history_date,
            start_time=now - timedelta(hours=4),
            end_time=now - timedelta(hours=1),
            start_verified=True,
            end_verified=True,
            is_active=False,
        )

        response = self.client.post(
            "/api/session/history/",
            data={
                "phone": self.partner.phone,
                "date": str(history_date),
                "total_earned_amount": "345.75",
                "raw_text": "Today earnings Rs 345.75",
                "extracted_amounts": json.dumps(["120.25", "225.50"]),
                "ocr_source": "client",
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["ocr_source"], "client")

        history = SessionHistory.objects.get(partner=self.partner, history_date=history_date)
        self.assertEqual(str(history.total_earned_amount), "345.75")
        self.assertEqual(str(history.total_working_hours), "3.00")
        self.assertEqual(history.extracted_amounts, ["120.25", "225.50"])
        self.assertEqual(history.raw_text, "Today earnings Rs 345.75")
