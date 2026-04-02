from django.urls import path
from .views import RegisterView, LoginView, ProfileView,verify_user

urlpatterns = [
    path('register/', RegisterView.as_view(), name='register'),
    path('login/',    LoginView.as_view(),    name='login'),
    path('profile/<str:phone>/', ProfileView.as_view(), name='profile'),
    path('verify-user/', verify_user, name='verify_user'),
]