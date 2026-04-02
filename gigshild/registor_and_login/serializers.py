from rest_framework import serializers
from .models import DeliveryPartner

class DeliveryPartnerSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryPartner
        fields = '__all__'  # Include all fields

    def validate_phone(self, value):
        # Must be digits only, 10 chars
        if not value.isdigit() or len(value) != 10:
            raise serializers.ValidationError("Enter a valid 10-digit phone number.")
        return value

    def validate_pincode(self, value):
        if not value.isdigit() or len(value) != 6:
            raise serializers.ValidationError("Enter a valid 6-digit pincode.")
        return value

# Just phone, no password needed
class LoginSerializer(serializers.Serializer):
    phone = serializers.CharField()