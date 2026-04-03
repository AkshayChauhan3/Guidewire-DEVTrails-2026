from django.urls import path

from .views import CityDataView


urlpatterns = [
    path("city-data/", CityDataView.as_view(), name="city-data"),
]
