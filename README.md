# GigShield - Insurance for Gig Workers

**GigShield** is a mobile insurance application for delivery partners and gig workers. It provides automatic protection coverage, tracks work sessions, manages premium accounts, and processes insurance claims with OCR-based earnings verification.

---

## Quick Setup (5 Minutes)

### Prerequisites
- **Python 3.10** and **pip**
- **Flutter 3.11+**
- **Chrome** (for web testing)
- **Tesseract OCR** (required for earnings extraction)
- **C/C++ Build Tools** (required for face recognition library)
- **Git**

### System Dependencies for Face Recognition

Face recognition requires C/C++ compilation tools:

**Linux/Ubuntu:**
```bash
sudo apt-get install build-essential cmake
```

**macOS:**
```bash
xcode-select --install
```

**Windows:**
1. Download Visual Studio Community: https://visualstudio.microsoft.com/community/
2. Install with "C++ build tools" workload
3. Or use MinGW: https://www.mingw-w64.org/

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

### Step 1: Check Flutter Installation

```bash
# Check Flutter setup and requirements
flutter doctor

# Install any missing components shown in the output
```

### Step 2: Get Flutter Ready

```bash
# Go to Flutter app folder
cd ../gigshild_app

# Get dependencies
flutter pub get
```

### Step 3: Run on Chrome (Web)

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

## Generate Fake Events (Demo Only)

For testing claim triggers and payout logic without real weather events:

### Open Fake News Generator

```
Path: gigshild_app/web/fake_news_index.html
```

**Steps:**
1. Open the HTML file in your browser while Flutter app is running
2. Enter your phone number (same as registered in the app)
3. Select city, area, and event type (flood, strike, protest, curfew, etc.)
4. Click "Generate Headlines" to create test news stories
5. Click "Publish to Backend" to activate the fake event
6. The app will now detect this event and trigger claim eligibility

---

## Backend Logic

### 1. Premium Collection (Weekly)

Calculates personalized insurance premiums every Monday:

**Income Calculation:**
- `weekly_income` = sum of last 7 days earnings

**Worker Category:**
- **Full-time:** 35+ working hours/week (1.0x multiplier)
- **Part-time:** 15-34 hours/week (0.8x multiplier)
- **Weekend:** 60%+ weekend hours (0.7x multiplier)
- **Casual:** <15 hours/week (0.5x multiplier)

**Region Premium (Base Rate):**
- North: 6.8% | East: 6.4% | West: 6.1% | South: 6.5%

**Weather Risk Adjustment:**
- Fetches real-time weather (rainfall, temperature, humidity, wind)
- ML model (XGBoost) scores weather risk (0-1)
- Multiplies premium by `1 + (weather_score × 0.5)`

**Final Premium:**
```
premium = weekly_income × region_rate × category_multiplier × weather_multiplier
```

### 2. Location-Based Tracking

Captures and maps worker location to insurance regions:

- GPS location captured during work sessions
- Reverse geocoded to city, area, pincode
- Mapped to region: North/South/East/West
- Stored for claim verification and fraud detection

### 3. Claim Verification

Approves or rejects insurance claims using multi-factor scoring:

**Data Sources:**
- **Weather API:** Current conditions at claim location
- **News API:** Active events (floods, strikes, protests)
- **Location Matching:** Distance check (< 5km = match)
- **Activity Drop:** Compare today's orders vs 30-day average

**ML Scoring (Final Decision):**
```
final_score = (
    0.40 × weather_score +          # Weather impact
    0.30 × news_confidence +        # Event detection
    0.20 × location_match +         # Location proximity
    0.10 × activity_drop            # Order volume drop
)
```

**Claim Decision:**
- `score > 0.7` → **APPROVED** ✅
- `score ≤ 0.7` → **REJECTED** ❌

**Fraud Protection:**
- Validates cell tower consistency
- Checks motion patterns
- Verifies notification timeline
- Any failure → **REJECTED_FRAUD**

### 4. Payout Calculation

Calculates income loss compensation based on disruption severity:

**Formula:**
```
avg_rate = monthly_income / total_hours
loss_hours = expected_hours - actual_hours

Crisis Levels (Multiplier):
- Mild: 1.0x
- Moderate: 1.25x
- Severe: 1.5x
- Emergency: 2.0x

payout = avg_rate × loss_hours × crisis_multiplier
```

Example: If avg rate is ₹200/hour, lost 4 hours during severe crisis:
`payout = 200 × 4 × 1.5 = ₹1200`

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

---

## 🎥 Demo Video

Watch the execution video on YouTube: [https://www.youtube.com/watch?v=WbCT-Czzg40]
