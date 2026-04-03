from django.urls import path

from .views import HistorySessionView, RandomCheckView, StartSessionView, StopSessionView

urlpatterns = [
    path("session/start/", StartSessionView.as_view(), name="session_start"),
    path("session/stop/", StopSessionView.as_view(), name="session_stop"),
    path("session/random-check/", RandomCheckView.as_view(), name="session_random_check"),
    path("session/history/", HistorySessionView.as_view(), name="session_history"),
]
