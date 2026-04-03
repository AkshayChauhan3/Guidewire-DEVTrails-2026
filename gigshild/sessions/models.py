from django.db import models
from django.utils import timezone

from registor_and_login.models import DeliveryPartner


class WorkSession(models.Model):
    partner = models.ForeignKey(DeliveryPartner, on_delete=models.CASCADE)
    session_date = models.DateField(default=timezone.localdate)

    start_time = models.DateTimeField(null=True, blank=True)
    start_latitude = models.FloatField(null=True, blank=True)
    start_longitude = models.FloatField(null=True, blank=True)
    start_verified = models.BooleanField(default=False)

    end_time = models.DateTimeField(null=True, blank=True)
    end_latitude = models.FloatField(null=True, blank=True)
    end_longitude = models.FloatField(null=True, blank=True)
    end_verified = models.BooleanField(default=False)

    random_due_at = models.DateTimeField(null=True, blank=True)
    random_time = models.DateTimeField(null=True, blank=True)
    random_latitude = models.FloatField(null=True, blank=True)
    random_longitude = models.FloatField(null=True, blank=True)
    random_verified = models.BooleanField(default=False)

    is_active = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def is_complete(self):
        if not (self.start_verified and self.end_verified):
            return False
        if self.random_due_at and self.end_time and self.end_time < self.random_due_at:
            return True
        return self.random_verified


class SessionHistory(models.Model):
    partner = models.ForeignKey(DeliveryPartner, on_delete=models.CASCADE)
    history_date = models.DateField(default=timezone.localdate)
    total_earned_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_working_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    total_shifts = models.PositiveIntegerField(default=0)
    extracted_amounts = models.JSONField(default=list, blank=True)
    raw_text = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("partner", "history_date")


    def __str__(self):
        return f"{self.partner.phone} - {self.history_date}"
