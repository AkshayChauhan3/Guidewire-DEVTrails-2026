import base64
import binascii
import json
import logging
import os
import random
import re
import uuid
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation

import cv2
import numpy as np
from django.core.files.base import ContentFile
from django.utils import timezone
from rest_framework import status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from registor_and_login.face import compare_faces
from registor_and_login.models import DeliveryPartner
from .models import SessionHistory, WorkSession

try:
    import pytesseract
    from PIL import ImageFile
    if ImageFile is not None:
        ImageFile.LOAD_TRUNCATED_IMAGES = True
except ImportError:
    pytesseract = None

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Selfie / auth helpers
# ─────────────────────────────────────────────────────────────────────────────

def _save_temp_selfie(selfie):
    os.makedirs("media/temp", exist_ok=True)
    filename = f"{uuid.uuid4().hex}_{selfie.name}"
    selfie_path = os.path.join("media/temp", filename)
    with open(selfie_path, "wb") as f:
        for chunk in selfie.chunks():
            f.write(chunk)
    return selfie_path


def _get_request_value(request, key):
    value = request.data.get(key)
    if value not in (None, ""):
        return value
    return request.POST.get(key)


def _get_selfie_from_request(request):
    selfie = request.FILES.get("selfie_image")
    if selfie is not None:
        return selfie

    selfie = request.data.get("selfie_image")
    if hasattr(selfie, "chunks"):
        return selfie

    if not isinstance(selfie, str) or not selfie.strip():
        return None

    encoded_image = selfie.strip()
    extension = "jpg"
    if ";base64," in encoded_image:
        header, encoded_image = encoded_image.split(";base64,", 1)
        if "/" in header:
            extension = header.split("/")[-1]

    try:
        decoded_image = base64.b64decode(encoded_image, validate=True)
    except (binascii.Error, ValueError):
        return None

    return ContentFile(decoded_image, name=f"selfie_upload.{extension}")


def _verify_selfie(partner, selfie):
    if not partner.profile_image:
        return False, {"error": "User does not have a profile image to compare against ❌"}

    profile_path = partner.profile_image.path
    selfie_path = _save_temp_selfie(selfie)
    result = compare_faces(profile_path, selfie_path)

    if os.path.exists(selfie_path):
        os.remove(selfie_path)

    if result["match"] and result["confidence"] > 0.5:
        partner.is_verified = True
        partner.save()
        return True, result

    return False, result


def _get_history_images(request):
    images = []
    seen_signatures = set()

    def append_unique(image_file):
        if image_file is None:
            return
        signature = (getattr(image_file, "name", ""), getattr(image_file, "size", None))
        if signature in seen_signatures:
            return
        seen_signatures.add(signature)
        images.append(image_file)

    for image_file in request.FILES.getlist("images"):
        append_unique(image_file)
    for image_file in request.FILES.getlist("history_images"):
        append_unique(image_file)
    append_unique(request.FILES.get("image"))
    append_unique(request.FILES.get("history_image"))
    return images


def _parse_history_date(value):
    if not value:
        return timezone.localdate()
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def _parse_decimal_value(value):
    if value in (None, ""):
        return None

    try:
        return Decimal(str(value)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError):
        return None


def _parse_extracted_amounts(value):
    if value in (None, ""):
        return []

    if isinstance(value, list):
        return [str(item) for item in value]

    try:
        parsed = json.loads(value)
    except (TypeError, ValueError, json.JSONDecodeError):
        return []

    if not isinstance(parsed, list):
        return []

    return [str(item) for item in parsed]


def _calculate_total_working_hours(history_date, sessions):
    total_seconds = 0
    now = timezone.now()
    for session in sessions:
        if not session.start_time:
            continue
        if timezone.localtime(session.start_time).date() != history_date:
            continue
        end_time = session.end_time or now
        total_seconds += max((end_time - session.start_time).total_seconds(), 0)
    return (Decimal(total_seconds) / Decimal("3600")).quantize(Decimal("0.01"))


# ─────────────────────────────────────────────────────────────────────────────
# Image preprocessing
# ─────────────────────────────────────────────────────────────────────────────

def _preprocess_for_ocr(img_array: np.ndarray) -> np.ndarray:
    """
    Convert a BGR image (OpenCV) into a grayscale upscaled image
    optimised for Tesseract on dark-background mobile UIs (Swiggy, Zomato etc.)

    Steps:
      1. Convert to grayscale
      2. Upscale 2× (Tesseract accuracy improves significantly above ~150 dpi)
      3. Adaptive threshold – handles uneven lighting across the screenshot
    """
    gray = cv2.cvtColor(img_array, cv2.COLOR_BGR2GRAY)
    upscaled = cv2.resize(gray, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
    # Adaptive threshold works better than global threshold for screenshots
    processed = cv2.adaptiveThreshold(
        upscaled, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        blockSize=31,
        C=15,
    )
    return processed


# ─────────────────────────────────────────────────────────────────────────────
# Amount extraction - simple and reliable
# ─────────────────────────────────────────────────────────────────────────────

# Match rupee amounts: REQUIRED ₹/7/F/R prefix, digits, optional comma, optional decimals
_AMOUNT_PATTERN = re.compile(r'[₹7FfRr€®]\s*(\d{1,3}(?:[,]\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)')


def _extract_all_amounts(text: str) -> list[Decimal]:
    """
    Extract all rupee amounts from OCR text.
    Returns list of Decimal amounts found.
    """
    amounts = []
    for match in _AMOUNT_PATTERN.finditer(text):
        amount_str = match.group(1).replace(",", "").strip()
        if not amount_str:
            continue
        try:
            # Ensure 2 decimal places
            amount = Decimal(amount_str)
            if amount > 0:  # Only positive amounts
                amounts.append(amount.quantize(Decimal('0.01')))
        except (InvalidOperation, ValueError):
            continue
    return amounts


# ─────────────────────────────────────────────────────────────────────────────
# Core OCR extraction
# ─────────────────────────────────────────────────────────────────────────────

def _extract_ocr_data(image_file) -> dict:
    """
    Simple OCR extraction: reads image and extracts all amounts.
    Returns amounts and raw text.
    """
    if pytesseract is None:
        raise RuntimeError("pytesseract is not installed")

    # Read and decode image
    image_file.seek(0)
    raw_bytes = image_file.read()
    if not raw_bytes:
        raise ValueError("Image file is empty")

    arr = np.frombuffer(raw_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image – unsupported format or corrupted file")

    # Preprocess image
    processed = _preprocess_for_ocr(img)

    # Extract all text from image using Tesseract
    raw_text = pytesseract.image_to_string(processed)
    
    # Extract all amounts from the text
    amounts = _extract_all_amounts(raw_text)
    total_earned = sum(amounts, Decimal("0.00"))

    return {
        "text": raw_text,
        "amounts": amounts,
        "total_earned": total_earned,
        "trips": [{"amount": a, "status": "complete"} for a in amounts],
    }


# ─────────────────────────────────────────────────────────────────────────────
# Views
# ─────────────────────────────────────────────────────────────────────────────

class StartSessionView(APIView):
    permission_classes = [AllowAny]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        phone = _get_request_value(request, "phone")
        selfie = _get_selfie_from_request(request)
        latitude = _get_request_value(request, "latitude")
        longitude = _get_request_value(request, "longitude")

        if not phone or not selfie or latitude is None or longitude is None:
            return Response(
                {"message": "phone, selfie_image, latitude, longitude are required ❌"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            partner = DeliveryPartner.objects.get(phone=phone)
        except DeliveryPartner.DoesNotExist:
            return Response({"message": "User not found ❌"}, status=status.HTTP_404_NOT_FOUND)

        existing = WorkSession.objects.filter(partner=partner, is_active=True).first()
        if existing:
            return Response(
                {"message": "Session already active ❌", "session_id": existing.id},
                status=status.HTTP_400_BAD_REQUEST,
            )

        verified, result = _verify_selfie(partner, selfie)
        if not verified:
            return Response(
                {"message": "Selfie verification failed ❌", "details": result},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        now = timezone.now()
        random_hours = random.choice([1, 2, 3])
        random_due_at = now + timedelta(hours=random_hours)

        session = WorkSession.objects.create(
            partner=partner,
            session_date=timezone.localdate(),
            start_time=now,
            start_latitude=float(latitude),
            start_longitude=float(longitude),
            start_verified=True,
            is_active=True,
            random_due_at=random_due_at,
        )

        return Response(
            {
                "message": "Session started ✅",
                "session_id": session.id,
                "random_due_at": random_due_at,
                "random_hours": random_hours,
            },
            status=status.HTTP_201_CREATED,
        )


class RandomCheckView(APIView):
    permission_classes = [AllowAny]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        session_id = _get_request_value(request, "session_id")
        phone = _get_request_value(request, "phone")
        selfie = _get_selfie_from_request(request)
        latitude = _get_request_value(request, "latitude")
        longitude = _get_request_value(request, "longitude")

        if not selfie or latitude is None or longitude is None:
            return Response(
                {"message": "selfie_image, latitude, longitude are required ❌"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        session = None
        if session_id:
            session = WorkSession.objects.filter(id=session_id, is_active=True).first()
        elif phone:
            try:
                partner = DeliveryPartner.objects.get(phone=phone)
            except DeliveryPartner.DoesNotExist:
                return Response({"message": "User not found ❌"}, status=status.HTTP_404_NOT_FOUND)
            session = WorkSession.objects.filter(partner=partner, is_active=True).first()

        if not session:
            return Response({"message": "Active session not found ❌"}, status=status.HTTP_404_NOT_FOUND)

        if session.random_verified:
            return Response(
                {"message": "Random check already completed ✅"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        now = timezone.now()
        if session.random_due_at and now < session.random_due_at:
            return Response(
                {"message": "Random check not due yet ❌", "random_due_at": session.random_due_at},
                status=status.HTTP_400_BAD_REQUEST,
            )

        verified, result = _verify_selfie(session.partner, selfie)
        if not verified:
            return Response(
                {"message": "Selfie verification failed ❌", "details": result},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        session.random_time = now
        session.random_latitude = float(latitude)
        session.random_longitude = float(longitude)
        session.random_verified = True
        session.save()

        return Response(
            {
                "message": "Random check verified ✅",
                "session_id": session.id,
                "random_time": session.random_time,
            },
            status=status.HTTP_200_OK,
        )


class StopSessionView(APIView):
    permission_classes = [AllowAny]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        session_id = _get_request_value(request, "session_id")
        phone = _get_request_value(request, "phone")
        selfie = _get_selfie_from_request(request)
        latitude = _get_request_value(request, "latitude")
        longitude = _get_request_value(request, "longitude")

        if not selfie or latitude is None or longitude is None:
            return Response(
                {"message": "selfie_image, latitude, longitude are required ❌"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        session = None
        if session_id:
            session = WorkSession.objects.filter(id=session_id, is_active=True).first()
        elif phone:
            try:
                partner = DeliveryPartner.objects.get(phone=phone)
            except DeliveryPartner.DoesNotExist:
                return Response({"message": "User not found ❌"}, status=status.HTTP_404_NOT_FOUND)
            session = WorkSession.objects.filter(partner=partner, is_active=True).first()

        if not session:
            return Response({"message": "Active session not found ❌"}, status=status.HTTP_404_NOT_FOUND)

        verified, result = _verify_selfie(session.partner, selfie)
        if not verified:
            return Response(
                {"message": "Selfie verification failed ❌", "details": result},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        now = timezone.now()
        session.end_time = now
        session.end_latitude = float(latitude)
        session.end_longitude = float(longitude)
        session.end_verified = True
        session.is_active = False
        session.save()

        return Response(
            {
                "message": "Session ended ✅",
                "session_id": session.id,
                "end_time": session.end_time,
                "is_complete": session.is_complete(),
            },
            status=status.HTTP_200_OK,
        )


class HistorySessionView(APIView):
    permission_classes = [AllowAny]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        phone = _get_request_value(request, "phone")
        history_date = _parse_history_date(_get_request_value(request, "date"))
        images = _get_history_images(request)
        ocr_source = (_get_request_value(request, "ocr_source") or "").strip().lower()
        client_total = _parse_decimal_value(_get_request_value(request, "total_earned_amount"))
        client_raw_text = (_get_request_value(request, "raw_text") or "").strip()
        client_extracted_amounts = _parse_extracted_amounts(
            _get_request_value(request, "extracted_amounts")
        )

        if not phone:
            return Response(
                {"message": "phone is required ❌"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if history_date is None:
            return Response(
                {"message": "date must be in YYYY-MM-DD format ❌"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if ocr_source != "client" and not images:
            return Response(
                {"message": "At least one image is required in image or images ❌"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            partner = DeliveryPartner.objects.get(phone=phone)
        except DeliveryPartner.DoesNotExist:
            return Response({"message": "User not found ❌"}, status=status.HTTP_404_NOT_FOUND)

        unreadable_images = []
        extracted_items = []
        used_client_ocr = ocr_source == "client"

        if used_client_ocr:
            if client_total is None:
                return Response(
                    {"message": "total_earned_amount is required for client OCR ❌"},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if not client_raw_text and not client_extracted_amounts:
                return Response(
                    {
                        "message": "raw_text or extracted_amounts is required for client OCR ❌"
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            total_earned_amount = client_total
            extracted_amounts = client_extracted_amounts
            raw_text = client_raw_text
            all_trips = []
        else:
            for image_file in images:
                try:
                    extracted_items.append(_extract_ocr_data(image_file))
                except RuntimeError as exc:
                    return Response({"message": str(exc)}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
                except Exception as exc:
                    filename = getattr(image_file, "name", "unknown")
                    unreadable_images.append({"file": filename, "reason": str(exc) or "Unreadable image"})
                    logger.warning("OCR failed for %s: %s", filename, exc)

            if not extracted_items:
                return Response(
                    {
                        "message": "Unable to read any uploaded image ❌",
                        "details": unreadable_images,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            total_earned_amount = sum(
                item.get("total_earned", Decimal("0.00")) for item in extracted_items
            ).quantize(Decimal("0.01"))
            extracted_amounts = [
                str(a) for item in extracted_items for a in item.get("amounts", [])
            ]
            raw_text = "\n\n".join(
                item["text"] for item in extracted_items if item.get("text")
            )
            all_trips = [
                {
                    "amount": str(t["amount"]) if t.get("amount") is not None else None,
                    "status": t.get("status", "complete"),
                }
                for item in extracted_items
                for t in item.get("trips", [])
            ]

        sessions = WorkSession.objects.filter(
            partner=partner, session_date=history_date
        ).order_by("start_time")
        total_working_hours = _calculate_total_working_hours(history_date, sessions)
        total_shifts = sessions.count()

        history, _ = SessionHistory.objects.update_or_create(
            partner=partner,
            history_date=history_date,
            defaults={
                "total_earned_amount": total_earned_amount,
                "total_working_hours": total_working_hours,
                "total_shifts": total_shifts,
                "extracted_amounts": extracted_amounts,
                "raw_text": raw_text,
            },
        )

        all_trips = [
            {
                "amount": str(t["amount"]) if t.get("amount") is not None else None,
                "status": t.get("status", "complete"),
            }
            for item in extracted_items
            for t in item.get("trips", [])
        ]

        return Response(
            {
                "message": "Session history saved ✅",
                "history_id": history.id,
                "date": history.history_date,
                "total_earned_amount": str(history.total_earned_amount),
                "total_working_hours": str(history.total_working_hours),
                "total_shifts": history.total_shifts,
                "extracted_amounts": history.extracted_amounts,
                "trips": all_trips,
                "raw_text": history.raw_text,
                "warnings": unreadable_images,
                "ocr_source": "client" if used_client_ocr else "server",
            },
            status=status.HTTP_200_OK,
        )
