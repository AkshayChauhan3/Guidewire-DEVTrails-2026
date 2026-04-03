# Bugfix Requirements Document

## Introduction

The Flutter app fails with a connection error "Connection failed at http://127.0.0.1:8000/api" when attempting to start a work session via the "I'm Working" button, despite the Django server running successfully and the login endpoint working correctly. This prevents users from starting work sessions, which is a core feature of the application.

The issue occurs specifically during the session start flow after the user takes a selfie and provides location data. The login endpoint at `/api/login/` works correctly (confirmed by 200 responses in Django logs), but the session start endpoint at `/api/session/start/` fails with a connection error.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the user clicks "I'm Working" button, takes a selfie, provides location, and the app calls `ApiService.startSession()` to POST to `/api/session/start/` THEN the system returns a connection error "Connection failed at http://127.0.0.1:8000/api" instead of successfully starting the session

1.2 WHEN the Flutter app attempts to connect to the session start endpoint THEN the system fails to establish a connection despite Django running and other endpoints (like `/api/login/`) working correctly

### Expected Behavior (Correct)

2.1 WHEN the user clicks "I'm Working" button, takes a selfie, provides location, and the app calls `ApiService.startSession()` to POST to `/api/session/start/` THEN the system SHALL successfully connect to the Django backend and receive a response (either success or validation error, but not a connection error)

2.2 WHEN the Flutter app attempts to connect to the session start endpoint THEN the system SHALL establish a connection to the Django backend at `http://127.0.0.1:8000/api/session/start/` and process the request

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the user attempts to login via the `/api/login/` endpoint THEN the system SHALL CONTINUE TO successfully connect and authenticate users

3.2 WHEN Django is running at `http://127.0.0.1:8000` with CORS enabled and ALLOWED_HOSTS configured THEN the system SHALL CONTINUE TO accept requests from the Flutter app for all working endpoints

3.3 WHEN the Flutter app constructs API URLs using the `baseUrl` configuration THEN the system SHALL CONTINUE TO correctly form URLs for all API endpoints
