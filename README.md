# GigShield - Insurance Protection for Gig Workers

**GigShield** is an innovative mobile insurance application designed for gig economy workers (delivery partners). It provides automatic protection coverage based on real-world events and AI-driven claim scoring, protecting workers from income loss during floods, news events, and extreme weather conditions.

---

## Table of Contents

1. [Part 1: Setup & Installation](#part-1-setup--installation)
2. [Part 2: How GigShield Works](#part-2-how-gigshield-works)
3. [Technology Stack](#technology-stack)
4. [Project Structure](#project-structure)
5. [Troubleshooting](#troubleshooting)

---

# PART 1: SETUP & INSTALLATION

## Prerequisites

Before you begin, ensure you have the following installed on your system:

- **Python 3.11+** - Download from [python.org](https://www.python.org/downloads/)
- **Git** - Download from [git-scm.com](https://git-scm.com/)
- **Flutter SDK 3.11.4+** - Download from [flutter.dev](https://flutter.dev/docs/get-started/install)
- **Android Studio** (with Android SDK) - For Android deployment
- **Tesseract OCR** - For image text recognition

### Optional but Recommended:
- **Visual Studio Code** - Code editor
- **Xcode** (macOS only) - For iOS deployment
- **Chrome/Firefox** - For web testing

---

## Installation Steps

### Step 1: Clone the Repository from GitHub

```bash
# Clone the project
git clone https://github.com/yourusername/gigshield.git

# Navigate to project directory
cd gigshield
```

### Step 2: Setup Django Backend

```bash
# Navigate to backend directory
cd gigshild

# Create and activate Python virtual environment
python3 -m venv .venv

# On Linux/macOS:
source .venv/bin/activate

# On Windows:
.venv\Scripts\activate

# Install Python dependencies
pip install -r requirements.txt

# Run database migrations
python manage.py migrate

# Create superuser (optional, for admin panel)
python manage.py createsuperuser

# Start Django development server
python manage.py runserver

# Backend will be available at: http://127.0.0.1:8000/
```

### Step 3: Install System Dependencies (For OCR)

The backend uses Tesseract OCR for processing delivery screenshots. Install it:

**On Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install tesseract-ocr
sudo apt-get install libtesseract-dev
```

**On macOS (with Homebrew):**
```bash
brew install tesseract
```

**On Windows:**
- Download installer from [GitHub Tesseract releases](https://github.com/UB-Mannheim/tesseract/wiki)
- Install to `C:\Program Files\Tesseract-OCR`
- Update Django settings if needed

### Step 4: Setup Flutter Frontend

```bash
# In a new terminal, navigate to frontend
cd gigshild_app

# Get Flutter dependencies
flutter pub get

# For Android development:
flutter devices  # List available devices/emulators

# Run on connected device or emulator:
flutter run

# For Web (testing in browser):
flutter run -d chrome

# For iOS (macOS only):
flutter run -d ios
```

### Step 5: Test the Application

**Option A: Flutter App (Recommended)**
1. Start Flutter app: `flutter run`
2. Go to Login page
3. Enter test phone: `9876543210`
4. Enter any 4-digit OTP
5. Explore Dashboard, Claims, Premium screens

**Option B: Web Interface (Quick Testing)**
1. Open browser: `http://127.0.0.1:8000/static/fake_news_index.html`
2. Fill in event details
3. Click "Publish to Backend"
4. Check Django admin or app for created events

---

## Running the Application Locally

### Start All Services:

**Terminal 1 - Backend:**
```bash
cd gigshild
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python manage.py runserver
# Output: Starting development server at http://127.0.0.1:8000/
```

**Terminal 2 - Frontend:**
```bash
cd gigshild_app
flutter run
# Select device (chrome/android/ios)
```

**Terminal 3 (Optional) - Test Event Creation:**
```bash
# Create test events via web interface
# Open: http://127.0.0.1:8000/web/fake_news_index.html
```

### Access Points:

| Component | URL | Purpose |
|-----------|-----|---------|
| Django Admin | `http://127.0.0.1:8000/admin/` | View database, users, claims |
| API Endpoints | `http://127.0.0.1:8000/api/` | Backend API |
| Web Test Interface | `http://127.0.0.1:8000/web/fake_news_index.html` | Create demo events |
| Flutter App | Device/Emulator | Main mobile application |

---

## Important Configuration Files

### Backend Configuration

**File:** `gigshild/gigshild/settings.py`

Key settings:
- `DEBUG = True` - Development mode
- `ALLOWED_HOSTS = ['127.0.0.1', 'localhost', '10.0.2.2']` - Allowed domains
- `CORS_ALLOW_ALL_ORIGINS = True` - Allow all cross-origin requests (dev only)
- `DATABASES` - SQLite database configuration

### Frontend Configuration

**File:** `gigshild_app/lib/api_service.dart`

Contains API endpoints for communicating with backend:
- Base URL: `http://127.0.0.1:8000` (local)
- Adjust for production deployment

---

# PART 2: HOW GIGSHIELD WORKS

## Application Overview

GigShield is a comprehensive insurance protection system that automatically evaluates and approves claims for gig workers when they are affected by external events like floods, bad weather, or news-related incidents.

### Key Features:

1. **Automatic Premium Calculation** - Weekly premium based on income
2. **Smart Claim Scoring** - AI-driven evaluation of events
3. **Location-Based Protection** - Only events near your location count
4. **Weather Integration** - Real-time weather data for scoring
5. **Session OCR** - Extract earnings from delivery screenshots
6. **Instant Payouts** - Automatic claim approvals to wallet

---

## System Architecture

```
┌─────────────────┐
│  Flutter App    │
│  (Mobile/Web)   │
└────────┬────────┘
         │ HTTP REST API
         ▼
┌─────────────────────────────────┐
│    Django Backend               │
│                                 │
│  Users │ Premium │ Claims │     │
│        │ Accounts│ Records│     │
└────┬──────────┬─────────────────┘
     │          │
     ▼          ▼
┌─────────────────────────────────┐
│   SQLite Database               │
│                                 │
│ - Delivery Partners             │
│ - Premium Accounts              │
│ - Claim Records                 │
│ - Demo Events                   │
│ - Session Histories             │
└─────────────────────────────────┘
```

---

## Complete User Flow

### 1. **User Registration & Login**

**Frontend:** `lib/registor_page.dart` & `lib/login_page.dart`

```
User Opens App
    ↓
Navigates to Registration (first time)
    ↓
    ├─ Fills personal details:
    │  - Full Name, DOB, Gender
    │  - Phone (unique), Email
    │  - Location (City, Area, Pincode)
    │  - Platform (Zomato/Swiggy)
    │  - Vehicle Type & Number
    │  - Emergency Contact
    │  - UPI ID for payments
    │
    └─ Submits form → Backend creates DeliveryPartner entry
                      ↓
                      Auto-creates Premium Account
                      ↓
                      Wallet: ₹5000 testing bonus
```

**API Endpoint:** `POST /api/auth/register/`

### 2. **Premium Account Setup**

**Backend:** `premiumandclaims/models.py` → `PremiumAccount`

When user logs in, system creates/retrieves premium account:

```python
{
  "partner": "DeliveryPartner",
  "wallet_balance": 5000.00,          # Testing bonus
  "testing_bonus": 5000.00,
  "total_premium_paid": 0.00,
  "total_payout_received": 0.00,
  "city": "Mumbai",
  "latitude": 19.0760,
  "longitude": 72.8777,
  "region": "west"                    # Used for regional multipliers
}
```

---

### 3. **Weekly Premium Calculation**

**Feature Location:** `lib/premium_screen.dart`

Every week, the system calculates premium based on:

```
Weekly Premium = Weekly Income × Category Multiplier × Weather Multiplier × Region Rate

Components:
├─ Weekly Income: ₹2000-₹10000 (user estimates or OCR from screenshots)
├─ Category Multiplier: Standard=1.0, Premium=1.2 (user tier)
├─ Region Rate: 
│  - North: ₹150 per ₹1000
│  - South: ₹120 per ₹1000
│  - East:  ₹140 per ₹1000
│  - West:  ₹110 per ₹1000
│
└─ Weather Multiplier: 
   - Normal: 0.8
   - Rainy: 1.2
   - Extreme: 1.5
```

**Example Calculation:**
```
₹5000 income 
× 1.0 multiplier (standard user)
× 1.2 weather (rainy week)
× ₹110/1000 (West region)
= ₹660 premium deducted from wallet weekly
```

**API Endpoint:** `GET /api/premium/summary/?phone=XXXXXXXXXX`

---

### 4. **Demo Event Creation**

**Frontend:** Web interface at `web/fake_news_index.html`

System allows creating test events to demonstrate claims:

```
User fills form:
├─ City: Mumbai (20 major cities supported)
├─ Area: Andheri East
├─ Event Type: Flood, Fire, Accident, Wildfire
├─ Severity: Low, Medium, Severe
├─ Summary: Auto-generated vs. manual
│
└─ Clicks "Publish"
   ↓
   Coordinates fetched from city mapping:
   ├─ Mumbai: (19.0760, 72.8777)
   ├─ Vadodara: (22.3072, 73.1812)
   └─ ... 18 more cities
   ↓
   Backend creates DemoNewsEvent:
   {
     "event_type": "flood",
     "city": "Mumbai",
     "event_latitude": 19.0760,
     "event_longitude": 72.8777,
     "severity": "severe",
     "partner_phone": "9876543210",
     "created_at": "2026-04-03 10:30:00"
   }
```

**API Endpoint:** `POST /api/demo-events/` (Backend creates event)

---

### 5. **Automatic Claim Generation**

**Backend:** `premiumandclaims/services.py` → `auto_generate_claims_for_partner()`

When event is created, system automatically generates claims:

```
Event Created
   ↓
   For each active premium partner in that city:
   ├─ Calculate claim score (0.0 to 1.0)
   ├─ Determine payout amount
   ├─ Set status (APPROVED or REJECTED)
   │
   └─ ClaimRecord saved with:
      {
        "partner": "user",
        "event_type": "flood",
        "city": "Mumbai",
        "status": "APPROVED" or "REJECTED",
        "final_score": 0.72,
        "payout_amount": 500.00,
        "created_at": "2026-04-03 10:31:00"
      }
```

---

### 6. **Smart Claim Scoring Algorithm**

**Backend:** `premiumandclaims/services.py` → `evaluate_claim()`

Claims are approved/rejected based on 4 factors:

#### **Factor 1: Weather Score (40% weight)**

```
Weather Score = Rainfall & Temperature Analysis

Calculation for event location:
├─ Fetch weather data for event coordinates
├─ Check rainfall in last 48 hours
├─ Check wind speed
├─ Check temperature
│
└─ Score calculation:
   - Rainfall > 25mm with wind > 30kmh: 0.8-1.0
   - Rainfall 10-25mm: 0.5-0.8
   - Light rain or no rain: 0.0-0.3
   - Extreme temp: +0.2 bonus
```

**Example:**
- Event: Flood in Mumbai during monsoon
- Rainfall: 45mm in 24 hours + Wind: 40kmh
- Weather Score = 0.85
- Contribution: 0.85 × 40% = 0.34

#### **Factor 2: News/Event Score (30% weight)**

```
News Score = Machine Learning based event relevance

├─ Analyzes news headlines
├─ Checks social media signals
├─ Validates event severity
│
└─ Scores:
   - Major news event (trending): 0.8-1.0
   - Local news (10+ mentions): 0.5-0.8
   - Demo/minor event: 0.3-0.5
   - Unverified event: 0.0-0.3
```

**Example:**
- Event: Flood (major news with 50+ mentions)
- News Score = 0.65
- Contribution: 0.65 × 30% = 0.195

#### **Factor 3: Location Match (20% weight)**

```
Location Match = Distance-based scoring

├─ Calculate distance between:
│  ├─ User's registered location (lat, lng)
│  └─ Event location (lat, lng)
│
└─ Scoring:
   - 0-5km: 1.0 (perfect match)
   - 5-15km: 1.0→0.4 (smooth decline)
   - 15-30km: 0.4→0.2 (further decline)
   - 30km+: 0.2 (minimum credit)
```

**Example:**
- User in Andheri (19.1136, 72.8697)
- Event in Andheri East (19.1186, 72.8768)
- Distance: 0.8km
- Location Score = 1.0
- Contribution: 1.0 × 20% = 0.20

#### **Factor 4: Activity Score (10% weight)**

```
Activity Score = User engagement & delivery activity

├─ Sessions completed in event week: +0.2 each
├─ Total hours worked: +0.3 if > 40 hours
├─ Verified account: +0.1
│
└─ Score: 0.0-1.0 based on activity
```

**Example:**
- 0 sessions in event week = 0.0 activity
- Contribution: 0.0 × 10% = 0.0

#### **Final Score Calculation**

```
Final Score = 
  (Weather × 0.40) +
  (News × 0.30) +
  (Location × 0.20) +
  (Activity × 0.10)

Approval Rule:
├─ Final Score > 0.70: APPROVED ✅
├─ Final Score 0.50-0.70: PENDING (review manual)
└─ Final Score < 0.50: REJECTED ❌
```

**Complete Example:**

```
Event: Flood in Mumbai
- Weather Score: 0.85 × 40% = 0.340
- News Score: 0.65 × 30% = 0.195
- Distance: 2km → Location: 1.0 × 20% = 0.200
- Activity Score: 0.0 × 10% = 0.000
─────────────────────────────────────
FINAL SCORE = 0.735 ✅ APPROVED
```

---

### 7. **Payout Calculation**

**Backend:** `premiumandclaims/services.py` → `calculate_claim_payout()`

When claim is APPROVED, payout is calculated:

```
Payout = Weekly Premium × Payout Multiplier × Proximity Bonus

Where:
├─ Weekly Premium: Amount user paid this week
├─ Payout Multiplier: (typically 2.0x for approved claims)
│
└─ Proximity Bonus:
   - 0-5km: 1.0x
   - 5-10km: 0.8x
   - 10-15km: 0.6x
   - 15km+: 0.4x
```

**Example:**

```
Weekly Premium Paid: ₹660
Multiplier: 2.0x (approved)
Distance: 2km → Bonus: 1.0x

Payout = ₹660 × 2.0 × 1.0 = ₹1320
```

---

### 8. **Session History & OCR Processing**

**Feature Location:** `lib/session_history_screen.dart`

Users can upload delivery app screenshots for earnings verification:

```
User Action:
├─ Takes screenshots of delivery app earnings
├─ Selects date
├─ Uploads multiple images
│
└─ Backend processes:
   ├─ Receives images
   ├─ Converts to OpenCV format (grayscale)
   ├─ Upscales 2x for accuracy
   ├─ Applies adaptive thresholding
   ├─ Runs Tesseract OCR
   ├─ Extracts ₹ amounts using regex
   │
   └─ Returns:
      {
        "total_earned_amount": "1250.75",
        "total_hours": "8.50",
        "extracted_amounts": ["250.50", "300.25", "700.00"],
        "status": "success"
      }
```

**API Endpoint:** `POST /api/session/history/`

---

### 9. **Wallet & Ledger Management**

**Backend:** `premiumandclaims/models.py` → `PremiumLedger`

Every transaction is recorded:

```
Entry Types:
├─ testing_bonus: Initial ₹5000 bonus
├─ premium_debit: Weekly premium removed
├─ payout_credit: Claim payout added
├─ claim_rejected: Rejected claim refund
└─ mock_payment: Test transactions

Example Ledger:
[
  {
    "entry_type": "premium_debit",
    "amount": -660.00,
    "direction": "debit",
    "description": "Weekly premium for week 2026-03-27",
    "created_at": "2026-04-03 10:00:00"
  },
  {
    "entry_type": "payout_credit",
    "amount": +1320.00,
    "direction": "credit",
    "description": "Payout for APPROVED flood claim",
    "reference": "CLAIM#12345",
    "created_at": "2026-04-03 10:31:00"
  }
]
```

---

### 10. **Dashboard Overview**

**Frontend:** `lib/home_screen.dart` & `lib/claim_screen.dart`

Users see comprehensive dashboard with:

```
┌─────────────────────────────────┐
│         HOME DASHBOARD          │
├─────────────────────────────────┤
│                                 │
│  💰 Wallet Balance: ₹4340       │
│  📈 Testing Bonus:  ₹0          │
│  🛡️ Active Premium: ₹660/week  │
│  📊 Total Payouts:  ₹1320       │
│                                 │
├─────────────────────────────────┤
│      RECENT CLAIMS (2026)       │
├─────────────────────────────────┤
│                                 │
│ ✅ Flood          Approved      │
│    Payout: ₹1320  Apr 03        │
│                                 │
│ ✅ Heavy Rain     Approved      │
│    Payout: ₹1000  Mar 31        │
│                                 │
├─────────────────────────────────┤
│      WEEKLY PREMIUM: ₹660       │
│                                 │
│ Income:     ₹5000               │
│ Category:   Standard (1.0x)     │
│ Region:     West (₹110/1000)    │
│ Weather:    Rainy (1.2x)        │
│                                 │
└─────────────────────────────────┘
```

---

## API Endpoints Reference

### Authentication APIs

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/register/` | POST | Register new delivery partner |
| `/api/auth/login/` | POST | Login with phone + OTP |
| `/api/auth/verify-otp/` | POST | Verify OTP |

### Premium APIs

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/premium/summary/` | GET | Get wallet & premium info |
| `/api/premium/collect/` | POST | Collect weekly premium |

### Claims APIs

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/claims/dashboard/` | GET | Get all claims for user |
| `/api/demo-events/` | POST | Create test event |

### Session APIs

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/session/history/` | POST | Upload delivery screenshots |

---

## Data Models Explained

### DeliveryPartner Model

```
Fields:
├─ Personal: full_name, dob, gender
├─ Contact: phone (unique), email (unique)
├─ Location: city, area, pincode
├─ Platform: platform (Zomato/Swiggy), platform_id
├─ Device: device_type
├─ Emergency: emergency_name, emergency_phone
├─ Payment: upi_id
├─ Vehicle: vehicle_type, vehicle_number
├─ Profile: profile_image
└─ Status: is_verified
```

### PremiumAccount Model

```
Linked to: DeliveryPartner (1:1 relationship)

Fields:
├─ wallet_balance: Current money in account
├─ testing_bonus: Initial ₹5000 + any bonuses
├─ total_premium_paid: Cumulative premiums
├─ total_payout_received: Cumulative payouts
├─ Location: city, area, pincode, region
├─ Coordinates: latitude, longitude
└─ Timestamps: created_at, updated_at
```

### ClaimRecord Model

```
Fields:
├─ partner: DeliveryPartner reference
├─ event_type: flood, fire, accident, wildfire
├─ city: event location
├─ latitude, longitude: event coordinates
├─ status: APPROVED, REJECTED, PENDING
├─ final_score: 0.0 - 1.0 scoring result
├─ Scoring breakdown:
│  ├─ weather_score: 0.0 - 1.0
│  ├─ news_score: 0.0 - 1.0
│  ├─ location_distance: km
│  ├─ location_match: 0.0 - 1.0
│  └─ activity_score: 0.0 - 1.0
├─ payout_amount: Calculated payout
├─ premium_deducted_on: Date of premium
└─ created_at, updated_at: Timestamps
```

### PremiumLedger Model

```
Linked to: PremiumAccount

Each transaction creates entry:
├─ account: Premium account reference
├─ entry_type: testing_bonus, premium_debit, payout_credit, claim_rejected
├─ amount: Transaction amount
├─ direction: credit or debit
├─ status: success, pending, failed
├─ reference: Related claim/payment ID
├─ description: Human readable text
├─ metadata: Additional JSON data
└─ created_at: Timestamp
```

---

## Directory Structure

```
gigshield/
├── gigshild/                          # Django Backend
│   ├── manage.py                      # Django management
│   ├── requirements.txt               # Python dependencies
│   ├── db.sqlite3                     # Database
│   │
│   ├── gigshild/                      # Main Django project
│   │   ├── settings.py                # Configuration
│   │   ├── urls.py                    # URL routing
│   │   └── wsgi.py                    # WSGI application
│   │
│   ├── registor_and_login/            # User authentication app
│   │   ├── models.py                  # DeliveryPartner model
│   │   ├── views.py                   # Auth views
│   │   ├── serializers.py             # Data serialization
│   │   └── urls.py                    # Auth routes
│   │
│   ├── premiumandclaims/              # Premium & claims app
│   │   ├── models.py                  # Premium, Claim, Ledger models
│   │   ├── services.py                # Business logic
│   │   ├── views.py                   # API views
│   │   └── urls.py                    # API routes
│   │
│   ├── sessions/                      # Session history app
│   │   ├── models.py                  # SessionHistory model
│   │   ├── views.py                   # OCR processing views
│   │   └── urls.py                    # Session routes
│   │
│   ├── apianddata/                    # Data/API app
│   │   ├── models.py                  # Supporting models
│   │   └── views.py                   # Data views
│   │
│   ├── media/                         # User uploads
│   │   ├── profiles/                  # Profile images
│   │   └── temp/                      # Temporary files
│   │
│   └── migrations/                    # Database migrations
│
└── gigshild_app/                      # Flutter Frontend
    ├── pubspec.yaml                   # Flutter dependencies
    ├── lib/
    │   ├── main.dart                  # App entry point
    │   ├── api_service.dart           # API client
    │   ├── app_state.dart             # State management
    │   │
    │   ├── login_page.dart            # Login screen
    │   ├── otp_page.dart              # OTP verification
    │   ├── registor_page.dart         # Registration
    │   │
    │   ├── home_screen.dart           # Dashboard
    │   ├── claim_screen.dart          # Claims view
    │   ├── premium_screen.dart        # Premium & wallet
    │   ├── profile_screen.dart        # User profile
    │   └── session_history_screen.dart # OCR uploads
    │
    ├── android/                       # Android configuration
    ├── ios/                           # iOS configuration
    ├── web/                           # Web folder
    │   └── fake_news_index.html       # Event creation interface
    └── build/                         # Build outputs
```

---

## Testing the Application

### Quick Test Flow

1. **Start Backend:**
   ```bash
   cd gigshild
   source .venv/bin/activate
   python manage.py runserver
   ```

2. **Start Flutter App:**
   ```bash
   cd gigshild_app
   flutter run
   ```

3. **Create Test Event:**
   - Open: `http://127.0.0.1:8000/web/fake_news_index.html` (in browser)
   - Fill form and publish

4. **Check Claims in App:**
   - Go to Claims screen
   - Should see newly created claim

5. **Verify in Backend:**
   ```bash
   cd gigshild
   python manage.py shell
   
   # Check claims
   from premiumandclaims.models import ClaimRecord
   claim = ClaimRecord.objects.latest('created_at')
   print(f"Status: {claim.status}")
   print(f"Score: {claim.final_score}")
   print(f"Payout: ₹{claim.payout_amount}")
   ```

---

## Technology Stack

### Backend
- **Framework:** Django 6.0.3 with Django REST Framework
- **Database:** SQLite (development)
- **Authentication:** JWT with djangorestframework-simplejwt
- **CORS:** django-cors-headers for cross-origin requests
- **Image Processing:** OpenCV (cv2) + NumPy
- **OCR:** pytesseract (Tesseract backend)
- **Image Format:** Pillow

### Frontend
- **Framework:** Flutter 3.11.4
- **Language:** Dart
- **HTTP Client:** http package
- **Image Processing:** google_mlkit_text_recognition
- **Location:** geolocator package
- **Image Picker:** image_picker package
- **UI:** Material Design (Cupertino for iOS)

### Infrastructure
- **Development Server:** Django development server
- **Database:** SQLite3 (file-based)
- **Environment:** Python virtual environment

---

## Troubleshooting

### Backend Issues

**Problem:** `pip install` fails
```bash
# Solution: Update pip first
pip install --upgrade pip
pip install -r requirements.txt
```

**Problem:** `pytesseract.TesseractNotFoundError`
```bash
# Tesseract not installed. Install system-wide:

# Ubuntu/Debian:
sudo apt-get install tesseract-ocr

# macOS:
brew install tesseract

# Windows: Download installer from https://github.com/UB-Mannheim/tesseract/wiki
```

**Problem:** Port 8000 already in use
```bash
# Use different port:
python manage.py runserver 8001
```

### Frontend Issues

**Problem:** `flutter: pub get` fails
```bash
flutter clean
flutter pub get
```

**Problem:** Android build fails
```bash
flutter doctor -v  # Check your setup
flutter clean
flutter run
```

**Problem:** Can't connect to backend from emulator
- Ensure backend is accessible at `10.0.2.2:8000` (Android emulator)
- Update `api_service.dart` if needed

### API Issues

**Problem:** CORS errors in browser
- Ensure `CORS_ALLOW_ALL_ORIGINS = True` in `settings.py` (development only)

**Problem:** Events not generating claims
- Verify demo event was created: Check Django database
- Check claim generation in backend logs
- Manually trigger: `GET /api/claims/dashboard/?phone=9876543210`

---

## Deployment (Production)

### Security Checklist Before Deployment

- [ ] Set `DEBUG = False` in settings.py
- [ ] Change `SECRET_KEY` to random string
- [ ] Update `ALLOWED_HOSTS` with your domain
- [ ] Use `gunicorn` instead of development server
- [ ] Set `CORS_ALLOW_ALL_ORIGINS = False`
- [ ] Configure allowed origins specifically
- [ ] Use HTTPS (SSL certificate)
- [ ] Setup production database (PostgreSQL)
- [ ] Configure email backend for notifications
- [ ] Setup monitoring and error tracking

### Basic Production Setup

```bash
# Install production server
pip install gunicorn

# Run with gunicorn
gunicorn gigshild.wsgi --bind 0.0.0.0:8000

# Use process manager (supervisor, systemd)
# Follow Django deployment guide: https://docs.djangoproject.com/en/6.0/howto/deployment/
```

---

## Support & Contributing

For issues, questions, or contributions:
1. Check existing issues on GitHub
2. Create detailed issue with steps to reproduce
3. Submit pull requests with tests

---

## License

[Specify your license here - MIT, Apache, etc.]

---

**Last Updated:** April 3, 2026  
**Version:** 1.0.0  
**Status:** Development/Testing
