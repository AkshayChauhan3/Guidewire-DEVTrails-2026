from decimal import Decimal

from django.db import models

from registor_and_login.models import DeliveryPartner


class PremiumAccount(models.Model):
    partner = models.OneToOneField(
        DeliveryPartner,
        on_delete=models.CASCADE,
        related_name="premium_account",
    )
    wallet_balance = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal("0.00"),
    )
    testing_bonus = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal("5000.00"),
    )
    total_premium_paid = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal("0.00"),
    )
    total_payout_received = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal("0.00"),
    )
    city = models.CharField(max_length=100, blank=True)
    area = models.CharField(max_length=100, blank=True)
    pincode = models.CharField(max_length=10, blank=True)
    region = models.CharField(max_length=16, default="west")
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"PremiumAccount<{self.partner.phone}>"


class PremiumLedger(models.Model):
    ENTRY_TYPE_CHOICES = [
        ("testing_bonus", "Testing Bonus"),
        ("premium_debit", "Premium Debit"),
        ("payout_credit", "Payout Credit"),
        ("claim_rejected", "Claim Rejected"),
        ("mock_payment", "Mock Payment"),
    ]
    STATUS_CHOICES = [
        ("success", "Success"),
        ("pending", "Pending"),
        ("failed", "Failed"),
    ]

    account = models.ForeignKey(
        PremiumAccount,
        on_delete=models.CASCADE,
        related_name="ledger_entries",
    )
    entry_type = models.CharField(max_length=32, choices=ENTRY_TYPE_CHOICES)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    direction = models.CharField(max_length=8, default="credit")
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="success")
    reference = models.CharField(max_length=64, blank=True)
    description = models.CharField(max_length=255, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]


class WeeklyPremiumSnapshot(models.Model):
    partner = models.ForeignKey(
        DeliveryPartner,
        on_delete=models.CASCADE,
        related_name="weekly_premium_snapshots",
    )
    week_start = models.DateField()
    week_end = models.DateField()
    weekly_income = models.DecimalField(max_digits=12, decimal_places=2)
    total_hours = models.DecimalField(max_digits=8, decimal_places=2)
    weekend_hours = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal("0.00"))
    category = models.CharField(max_length=16)
    region = models.CharField(max_length=16)
    weather_score = models.FloatField(default=0.0)
    weather_multiplier = models.FloatField(default=1.0)
    premium_amount = models.DecimalField(max_digits=12, decimal_places=2)
    deducted_on = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("partner", "week_start")
        ordering = ["-week_start", "-id"]


class ClaimRecord(models.Model):
    STATUS_CHOICES = [
        ("APPROVED", "Approved"),
        ("REJECTED", "Rejected"),
        ("REJECTED_FRAUD", "Rejected Fraud"),
    ]
    CRISIS_LEVEL_CHOICES = [
        ("mild", "Mild"),
        ("moderate", "Moderate"),
        ("severe", "Severe"),
        ("emergency", "Emergency"),
    ]

    account = models.ForeignKey(
        PremiumAccount,
        on_delete=models.CASCADE,
        related_name="claims",
    )
    partner = models.ForeignKey(
        DeliveryPartner,
        on_delete=models.CASCADE,
        related_name="claims",
    )
    event_type = models.CharField(max_length=64)
    city = models.CharField(max_length=100)
    region = models.CharField(max_length=16)
    crisis_level = models.CharField(max_length=16, choices=CRISIS_LEVEL_CHOICES)
    status = models.CharField(max_length=24, choices=STATUS_CHOICES)
    final_score = models.FloatField(default=0.0)
    ai_score = models.FloatField(default=0.0)
    weather_score = models.FloatField(default=0.0)
    news_confidence = models.FloatField(default=0.0)
    location_match = models.FloatField(default=0.0)
    activity_drop = models.FloatField(default=0.0)
    average_income_per_hour = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal("0.00"))
    expected_hours = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal("0.00"))
    actual_hours = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal("0.00"))
    loss_hours = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal("0.00"))
    payout_amount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
    notification_match = models.BooleanField(default=True)
    cell_tower_verified = models.BooleanField(default=True)
    motion_pattern_valid = models.BooleanField(default=True)
    auto_created = models.BooleanField(default=False)
    trigger_source = models.CharField(max_length=32, blank=True)
    event_signature = models.CharField(max_length=255, blank=True)
    trigger_title = models.CharField(max_length=255, blank=True)
    audit = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at", "-id"]


class AdaptiveWeight(models.Model):
    location_key = models.CharField(max_length=128, unique=True)
    weather_weight = models.DecimalField(max_digits=6, decimal_places=4, default=Decimal("0.4000"))
    news_weight = models.DecimalField(max_digits=6, decimal_places=4, default=Decimal("0.3000"))
    location_weight = models.DecimalField(max_digits=6, decimal_places=4, default=Decimal("0.2000"))
    activity_weight = models.DecimalField(max_digits=6, decimal_places=4, default=Decimal("0.1000"))
    last_updated = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"AdaptiveWeight<{self.location_key}>"


class DemoNewsEvent(models.Model):
    EVENT_CHOICES = [
        ("flood", "Flood"),
        ("high_rain", "High Rain"),
        ("high_temperature", "High Temperature"),
        ("strike", "Strike"),
        ("protest", "Protest"),
        ("curfew", "Curfew"),
        ("disaster", "Disaster"),
    ]
    SEVERITY_CHOICES = [
        ("mild", "Mild"),
        ("moderate", "Moderate"),
        ("severe", "Severe"),
        ("emergency", "Emergency"),
    ]

    city = models.CharField(max_length=100)
    area = models.CharField(max_length=100, blank=True)
    event_type = models.CharField(max_length=32, choices=EVENT_CHOICES)
    severity = models.CharField(max_length=16, choices=SEVERITY_CHOICES, default="moderate")
    headline = models.CharField(max_length=255)
    summary = models.TextField(blank=True)
    event_latitude = models.FloatField(null=True, blank=True)
    event_longitude = models.FloatField(null=True, blank=True)
    effective_date = models.DateField()
    is_active = models.BooleanField(default=True)
    source = models.CharField(max_length=64, default="demo-generator")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-effective_date", "-created_at", "-id"]
