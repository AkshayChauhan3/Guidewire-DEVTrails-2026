from django.contrib import admin

from .models import SessionHistory, WorkSession


@admin.register(WorkSession)
class WorkSessionAdmin(admin.ModelAdmin):
    list_display = ("partner", "session_date", "start_time", "end_time", "is_active")
    list_filter = ("session_date", "is_active", "start_verified", "end_verified", "random_verified")
    search_fields = ("partner__phone", "partner__full_name")


@admin.register(SessionHistory)
class SessionHistoryAdmin(admin.ModelAdmin):
    list_display = (
        "partner",
        "history_date",
        "total_earned_amount",
        "total_working_hours",
        "total_shifts",
    )
    list_filter = ("history_date",)
    search_fields = ("partner__phone", "partner__full_name")
