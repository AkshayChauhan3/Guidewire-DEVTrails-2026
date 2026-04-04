# GigShield - Insurance for Gig Workers

**GigShield** is a mobile insurance application for delivery partners and gig workers. It provides automatic protection coverage, tracks work sessions, manages premium accounts, and processes insurance claims with OCR-based earnings verification.

---

## Quick Setup (5 Minutes)

### Prerequisites
- **Python 3.10** and **pip**
- **Flutter 3.11+**
- **Chrome** (for web testing)
- **Tesseract OCR** (required for earnings extraction)
- **Git**

---

## Setup & Run Backend

### Step 1: Setup Django Backend

```bash
# Navigate to backend folder
cd gigshild

# Create virtual environment
python3 -m venv .venv

# Activate it
# On Linux/macOS:
source .venv/bin/activate

# On Windows:
.venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Create database
python manage.py migrate

# Start server (runs on http://127.0.0.1:8000)
python manage.py runserver
```

### Step 2: Install Tesseract OCR (Required)

Tesseract is essential for extracting earnings data from delivery screenshots.

**Linux/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install tesseract-ocr
```

**macOS:**
```bash
brew install tesseract
```

**Windows:**
1. Download installer: https://github.com/UB-Mannheim/tesseract/wiki
2. Run the installer and install to `C:\Program Files\Tesseract-OCR`
3. Verify installation - open Command Prompt and run:
   ```bash
   tesseract --version
   ```

---

## Setup & Run Frontend

### Step 1: Get Flutter Ready

```bash
# Go to Flutter app folder
cd ../gigshild_app

# Get dependencies
flutter pub get
```

### Step 2: Run on Chrome (Web)

```bash
# Run Chrome browser with Flutter
flutter run -d chrome

# App opens at http://127.0.0.1:PORT and connects to backend at http://127.0.0.1:8000
```

---

## Running Both Together

**Terminal 1 (Backend):**
```bash
cd gigshild
source .venv/bin/activate
python manage.py runserver
```

**Terminal 2 (Frontend - Chrome Web):**
```bash
cd gigshild_app
flutter run -d chrome
```

Chrome opens automatically. The Flutter app connects to the Django backend at `http://127.0.0.1:8000`. Login with test credentials or register a new account.

---

## What's Inside

**Backend (Django):**
- User registration & authentication with face verification
- Work session tracking with location verification
- Premium account & wallet management
- Insurance claim processing
- OCR extraction for earnings verification

**Frontend (Flutter):**
- User login & registration
- Work session start/end with live location
- Premium panel to view balance & payouts
- Claims submission
- Session history

---

## Tech Stack

| Backend | Frontend |
|---------|----------|
| Django 6.0 | Flutter 3.11+ |
| Django REST Framework | Dart |
| JWT Authentication | Google ML Kit (Text Recognition) |
| SQLite (dev) | Geolocator |
| Tesseract OCR | Image Picker |

---

## Key Features

- User authentication with phone & email
- Location-based work session verification
- Automatic premium deduction & payout processing
- OCR-based earnings extraction from screenshots
- Real-time work session tracking
- Insurance claim management
- Wallet & transaction history

---

## Project Structure

```
gigshild/               # Django Backend
├── registor_and_login/ # Auth & user profiles
├── sessions/           # Work session tracking
├── premiumandclaims/   # Claims & wallet
├── apianddata/         # API endpoints
└── manage.py

gigshild_app/           # Flutter Frontend
├── lib/
│   ├── main.dart
│   ├── login_page.dart
│   ├── home_screen.dart
│   ├── premium_screen.dart
│   ├── claim_screen.dart
│   └── api_service.dart
└── pubspec.yaml
```

---

## Quick Test

1. **Register:** Enter phone, email, Zomato ID, and upload ID proof
2. **Verify Selfie:** Take/upload selfie photo to verify your identity
3. **Start Session:** Tap start button to begin work session tracking
4. **Premium:** Check premium balance and transaction history in premium panel
5. **Claims:** Submit insurance claim with earnings screenshot (OCR extracts data)
6. **History:** View all previous sessions and transactions

---

## Testing with Images (For Hackathon Teams)

**Download test images here:** [https://drive.google.com/drive/u/0/folders/1aqMzJ0KxyQ8iEqEPrH06L_D2ZMS1GASs]

### How to Test Registration & Verification:

**Step 1: Registration**
1. Enter Phone: **Any 10-digit mobile number** (e.g., 9876543210 or your own)
2. Platform: Select "Zomato"
3. Platform ID: `ZOMATO123456` (or any test ID)
4. **Upload Zomato ID Proof:** Download and upload the provided `zomato_id_screenshot.jpg` from drive

**Step 2: Selfie Verification**
1. During verification, select "Upload from device"
2. Upload the provided selfie image from Google Drive
3. Verification automatically succeeds

### Testing Rules:

**For Hackathon Judges:**
- **Use provided test images** from drive link to test the complete flow
- **If using your own Delivery ID**, you MUST provide:
  - Your Delivery ID screenshot (Zomato/Swiggy)
  - Your personal selfie photo (must match for verification)
- **Current Mode:** Media upload allowed for testing purposes
- **Production Mode:** Will use live camera feed (selfie-only, no file upload)

---

## API Endpoints (Examples)

```
POST   /api/register/          - User registration
POST   /api/login/             - User login
GET    /api/sessions/          - Get work sessions
POST   /api/claim/submit/      - Submit claim
GET    /api/premium/wallet/    - Check wallet balance
```

---

## Notes

- Backend runs on `http://127.0.0.1:8000`
- Frontend runs in Chrome at `http://127.0.0.1` (automatically assigned port)
- Both use localhost, so they connect seamlessly
- SQLite database is auto-created on first run
- Use **any 10-digit phone number** for registration and testing
