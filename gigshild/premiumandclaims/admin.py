from django.contrib import admin

from .models import AdaptiveWeight, ClaimRecord, DemoNewsEvent, PremiumAccount, PremiumLedger, WeeklyPremiumSnapshot


@admin.register(PremiumAccount)
class PremiumAccountAdmin(admin.ModelAdmin):
    list_display = ("partner", "city", "region", "wallet_balance", "updated_at")
    search_fields = ("partner__phone", "partner__full_name", "city", "region")


@admin.register(PremiumLedger)
class PremiumLedgerAdmin(admin.ModelAdmin):
    list_display = ("account", "entry_type", "amount", "direction", "status", "created_at")
    search_fields = ("account__partner__phone", "reference", "description")
    list_filter = ("entry_type", "direction", "status")


@admin.register(WeeklyPremiumSnapshot)
class WeeklyPremiumSnapshotAdmin(admin.ModelAdmin):
    list_display = ("partner", "week_start", "region", "premium_amount", "created_at")
    search_fields = ("partner__phone", "partner__full_name", "region")


@admin.register(ClaimRecord)
class ClaimRecordAdmin(admin.ModelAdmin):
    list_display = ("partner", "city", "event_type", "status", "final_score", "created_at")
    search_fields = ("partner__phone", "city", "event_type", "trigger_title")
    list_filter = ("status", "crisis_level", "auto_created")


@admin.register(AdaptiveWeight)
class AdaptiveWeightAdmin(admin.ModelAdmin):
    list_display = ("location_key", "weather_weight", "news_weight", "location_weight", "activity_weight", "last_updated")
    search_fields = ("location_key",)


@admin.register(DemoNewsEvent)
class DemoNewsEventAdmin(admin.ModelAdmin):
    list_display = ("city", "event_type", "severity", "headline", "effective_date", "is_active")
    search_fields = ("city", "headline", "source")
    list_filter = ("event_type", "severity", "is_active")
