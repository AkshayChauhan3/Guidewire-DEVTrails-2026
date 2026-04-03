from django.shortcuts import render
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from .serializers import DeliveryPartnerSerializer, LoginSerializer
from .models import DeliveryPartner
from premiumandclaims.services import ensure_premium_account


class RegisterView(APIView):
    permission_classes = [AllowAny]  # No token needed to register

    def post(self, request):
        # request.data contains form fields
        # request.FILES contains uploaded files like profile_image
        serializer = DeliveryPartnerSerializer(
            data=request.data  # DRF handles FILES automatically here
        )

        if serializer.is_valid():
            partner = serializer.save()
            account = ensure_premium_account(partner)
            return Response({
                "message": "Registered successfully 🚀",
                "partner": {
                    **serializer.data,
                    "wallet_balance": float(account.wallet_balance),
                    "testing_bonus": float(account.testing_bonus),
                    "region": account.region,
                }
            }, status=status.HTTP_201_CREATED)

        # If invalid, return what went wrong
        return Response({
            "message": "Registration failed ❌",
            "errors": serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)

class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)

        if serializer.is_valid():
            phone = serializer.validated_data['phone']

            # Check if phone exists
            try:
                partner = DeliveryPartner.objects.get(phone=phone)
            except DeliveryPartner.DoesNotExist:
                return Response({
                    "message": "No account found with this phone number ❌"
                }, status=status.HTTP_404_NOT_FOUND)

            account = ensure_premium_account(partner)
            # Phone found → Login success
            return Response({
                "message": "Login successful 🚀",
                "partner": {
                    "id":        partner.id,
                    "full_name": partner.full_name,
                    "phone":     partner.phone,
                    "email":     partner.email,
                    "city":      partner.city,
                    "platform":  partner.platform,
                    "wallet_balance": float(account.wallet_balance),
                    "testing_bonus": float(account.testing_bonus),
                    "region": account.region,
                }
            }, status=status.HTTP_200_OK)

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class ProfileView(APIView):
    permission_classes = [AllowAny]

    def get(self, request, phone):
        try:
            partner = DeliveryPartner.objects.get(phone=phone)
        except DeliveryPartner.DoesNotExist:
            return Response({
                "message": "User not found ❌"
            }, status=status.HTTP_404_NOT_FOUND)

        account = ensure_premium_account(partner)
        return Response({
            "message": "User data fetched ✅",
            "partner": {
                "id":              partner.id,
                "full_name":       partner.full_name,
                "dob":             partner.dob,
                "gender":          partner.gender,
                "phone":           partner.phone,
                "email":           partner.email,
                "city":            partner.city,
                "area":            partner.area,
                "pincode":         partner.pincode,
                "platform":        partner.platform,
                "platform_id":     partner.platform_id,
                "device_type":     partner.device_type,
                "emergency_name":  partner.emergency_name,
                "emergency_phone": partner.emergency_phone,
                "upi_id":          partner.upi_id,
                "vehicle_type":    partner.vehicle_type,
                "vehicle_number":  partner.vehicle_number,
                "profile_image":   request.build_absolute_uri(partner.profile_image.url) if partner.profile_image else None,
                "is_verified":     partner.is_verified,
                "wallet_balance":  float(account.wallet_balance),
                "testing_bonus":   float(account.testing_bonus),
                "region":          account.region,
            }
        }, status=status.HTTP_200_OK)

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import os

@csrf_exempt
def verify_user(request):
    if request.method == "POST":
        phone = request.POST.get('phone')
        selfie = request.FILES.get('selfie_image')

        if not phone or not selfie:
            return JsonResponse({"error": "Phone number and selfie image are required ❌"}, status=400)

        try:
            partner = DeliveryPartner.objects.get(phone=phone)
        except DeliveryPartner.DoesNotExist:
            return JsonResponse({"error": "User not found ❌"}, status=404)

        if not partner.profile_image:
            return JsonResponse({"error": "User does not have a profile image to compare against ❌"}, status=400)

        profile_path = partner.profile_image.path
        
        os.makedirs("media/temp", exist_ok=True)
        selfie_path = os.path.join("media/temp", selfie.name)

        # Save selfie file
        with open(selfie_path, "wb") as f:
            for chunk in selfie.chunks():
                f.write(chunk)

        # Import your function
        from .face import compare_faces

        result = compare_faces(profile_path, selfie_path)
        
        # Cleanup temporary selfie
        if os.path.exists(selfie_path):
            os.remove(selfie_path)

        if result["match"] and result["confidence"] > 0.5:
            status = "VERIFIED ✅"
            partner.is_verified = True
            partner.save()
        else:
            status = "REJECTED ❌"

        return JsonResponse({
            "status": status,
            "match": result["match"],
            "confidence": result["confidence"]
        })
