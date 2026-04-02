from django.db import models

# Create your models here.
import os

def profile_image_path(instance, filename):
    ext = filename.split('.')[-1]
    return f"profile_image_{instance.phone}.{ext}"

class DeliveryPartner(models.Model):
    GENDER_CHOICES = [('Male', 'Male'), ('Female', 'Female')]
    PLATFORM_CHOICES = [('Zomato', 'Zomato'), ('Swiggy', 'Swiggy')]

    # Personal
    full_name   = models.CharField(max_length=100)
    dob         = models.DateField()
    gender      = models.CharField(max_length=10, choices=GENDER_CHOICES)

    # Contact
    phone       = models.CharField(max_length=15, unique=True)
    email       = models.EmailField(unique=True)

    # Location
    city        = models.CharField(max_length=100)
    area        = models.CharField(max_length=100)
    pincode     = models.CharField(max_length=10)

    # Platform
    platform    = models.CharField(max_length=20, choices=PLATFORM_CHOICES)
    platform_id = models.CharField(max_length=100)

    # Device
    device_type = models.CharField(max_length=100)

    # Emergency
    emergency_name  = models.CharField(max_length=100)
    emergency_phone = models.CharField(max_length=15)

    # Payment
    upi_id = models.CharField(max_length=100)

    # Vehicle
    vehicle_type   = models.CharField(max_length=50)
    vehicle_number = models.CharField(max_length=20)

    # Profile image — saved as profile_image_{phone}
    profile_image = models.ImageField(upload_to=profile_image_path, blank=True, null=True)

    is_verified = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.full_name} ({self.phone})"