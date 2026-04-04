# GigShield - Flutter Frontend

This is the mobile/web frontend for **GigShield**, an insurance protection app for gig workers.

## Quick Start

For complete setup and running instructions, see the **[main README.md](../README.md)** in the project root.

### Check Flutter Setup

```bash
# Verify Flutter installation and required components
flutter doctor
```

### Fast Start

```bash
# Get dependencies
flutter pub get

# Run on device/emulator
flutter run

# Run on web browser
flutter run -d chrome
```

## Project Structure

- `lib/main.dart` - App entry point
- `lib/api_service.dart` - Backend API client
- `lib/login_page.dart` - Authentication
- `lib/home_screen.dart` - Main dashboard
- `lib/claim_screen.dart` - Claims view
- `lib/premium_screen.dart` - Premium & wallet
- `lib/session_history_screen.dart` - OCR uploads
- `lib/profile_screen.dart` - User profile

## Dependencies

See `pubspec.yaml` for all Flutter packages used:
- `http` - API calls
- `image_picker` - Photo selection
- `geolocator` - GPS location
- `google_mlkit_text_recognition` - Text recognition
- `device_preview` - Device preview

## Documentation

For complete documentation including:
- Installation & setup
- How the app works
- API endpoints
- Data models
- Testing

👉 See [README.md](../README.md) in project root
