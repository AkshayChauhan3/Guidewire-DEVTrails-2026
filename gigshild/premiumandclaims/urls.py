from django.urls import path

from .views import AdminSummaryView, ClaimsDashboardView, DemoEventView, PremiumSummaryView, SubmitClaimView


urlpatterns = [
    path("premium/summary/", PremiumSummaryView.as_view(), name="premium-summary"),
    path("claims/dashboard/", ClaimsDashboardView.as_view(), name="claims-dashboard"),
    path("claims/submit/", SubmitClaimView.as_view(), name="claims-submit"),
    path("demo-events/", DemoEventView.as_view(), name="demo-events"),
    path("admin/summary/", AdminSummaryView.as_view(), name="admin-summary"),
]
