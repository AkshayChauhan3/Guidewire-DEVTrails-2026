# GigShield — Protecting India's Delivery Workforce

> A verification, tracking, and insurance platform built for Zomato & Swiggy delivery partners — making sure the people who keep India fed are never left unprotected.

---

## The Problem

Gig workers are the backbone of India's food delivery ecosystem — yet they remain one of the most financially vulnerable groups in the workforce. No fixed salary. No insurance. No way to prove they were genuinely stranded during a flood, a natural disaster, or even a sudden curfew on their street.
The threats to a delivery partner's income aren't always natural. Sometimes it's a protest blocking the entire city. Sometimes it's a communal curfew that shuts down their area overnight. Sometimes it's heavy waterlogging, a heatwave, or a road closure from a local strike — none of which are their fault, all of which drain their daily earnings with zero compensation.
We built GigShield to change that. Every phase of this system is designed with one goal in mind — so that when a delivery partner has a bad day because of a flood, a heatwave, a protest, a curfew, or any crisis they had no control over, they don't have to fight to prove it. The system does that for them, fairly and transparently.

---

## System Architecture — How It All Fits Together

```
┌─────────────────────────────────────────────────────────────┐
│                        GIGSHIELD PLATFORM                   │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────┐
│   PHASE 1           │  Worker registers → KYC via OCR + Face Match
│   User Registration │  Zomato / Swiggy ID verified → Genuine Gig Worker
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   PHASE 2           │  Taps "I'm Working" → Session starts
│   Session Tracking  │  Random selfie checks → End of day screenshot upload
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   PHASE 3           │  Avg income/hr calculated → Crisis Index applied
│   Premium & Payout  │  Regional premium added → Fair payout generated
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   PHASE 4           │  Claim submitted → 5-signal ML pipeline runs
│   ML Claim Check    │  BERT + XGBoost + Location + Activity → Decision
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│   MARKET CRASH      │  GPS spoofed? → Cell Tower + Accelerometer +
│   DEFENSE           │  Notification Trail kicks in automatically
└─────────────────────┘
```

---

## Phase 1: User Registration

### 1.1 General Information Collection

During registration, the following details will be collected from the user:

- **Personal Info:** Full name, date of birth, gender
- **Contact Info:** Phone number, email address
- **Location Info:** Area / zone of operation, city, pincode
- **Platform Info:** Zomato / Swiggy ID, years of experience as a delivery partner
- **Device Info:** Device type (for app compatibility tracking)
- **Emergency Contact:** Name and phone number of a contact person
- **Bank/Payment Info:** Account number or UPI ID (for payout processing)
- **Vehicle Info:** Vehicle type, registration number

---

### 1.2 Identity Verification (KYC)

To verify the authenticity of each delivery partner, the following steps will be performed:

1. **Zomato / Swiggy ID Screenshot Upload** — User submits a screenshot of their active Zomato or Swiggy delivery profile.
2. **Live Selfie Capture** — User takes a real-time selfie within the app.
3. **OCR Check** — The system extracts the Zomato / Swiggy ID from the uploaded screenshot using OCR.
4. **Face Match** — The live selfie is compared against the profile picture on the Zomato / Swiggy screenshot to confirm identity.

Once all the above steps are successfully completed, the person will be identified as a **genuine gig worker** on the platform.

---

## Phase 2: Work Session Tracking & Verification

### 2.1 Session Management

The user controls their work session through two simple actions:

- **"I'm Working" Button** — User taps this when they begin their shift. This marks the **session start** and logs the starting location.
- **"Session Complete" Button** — User taps this at their **last order's delivery location**. This marks the session end and logs the ending location.

---

### 2.2 Live Verification During Session

To ensure the registered user is actively working throughout the session, the system will:

1. **Random Selfie Requests** — 1 to 2 times per session, at random intervals, the app will prompt the user to take a live selfie.
2. **Live Location Capture** — The user's current location is recorded at the time of each selfie prompt.

These random checks are matched against the registered profile to confirm the person working is the verified gig worker.

---

### 2.3 End-of-Day Verification

At the end of the day, the user must upload a photo of today's completed order history from Zomato / Swiggy. The system will then cross-verify the uploaded history against:

| Verification Point | Details |
|---|---|
| Starting Location | Matched with session start coordinates |
| Ending Location | Matched with last order delivery location |
| Random Check Locations | Matched with mid-session selfie location captures |
| Time Consistency | Order timestamps matched with session duration |

---

### 2.4 Worker Categorization

Based on weekly working hours, each user will be automatically categorized as follows:

| Category | Condition |
|---|---|
| Full-time | 35 hrs/week or more, consistently |
| Part-time | 15 to 34 hrs/week |
| Weekend Worker | More than 60% of hours on Saturday and Sunday |
| Casual | Less than 15 hrs/week |

This categorization will be reflected on the user's profile.

---

## Phase 3: Premium & Insurance Claim Calculation

### 3.1 Average Working Income Per Hour

To calculate the base payout, the system first determines the worker's average hourly income:

> **Avg (Working Income/hr) = Total Monthly Income / Total Hours Worked**

---

### 3.2 Crisis Index (CI)

The **Crisis Index (CI)** is a multiplier factor applied to the average income to calculate the final payout during adverse conditions.

> **Payout = Avg × CI**

| CI Level | Multiplier | Condition |
|---|---|---|
| Mild | 1× Avg | Normal Conditions |
| Moderate | 1.25× Avg | Rainy Day |
| Severe | 1.5× Avg | Heavy Traffic / Waterlogging |
| Emergency | 2× Avg | Natural Disaster |

---

### 3.3 Regional Premium for Gig Workers

An additional regional premium is applied on top of the base income based on geographical conditions:

| Region | Reason | Premium |
|---|---|---|
| North | Snow | 5% + 1.8% = **6.8%** |
| East | Rainfall | 5% + 1.4% = **6.4%** |
| West | Some Heat | 5% + 1.01% = **6.1%** |
| South | Extreme Heat | 5% + 1.5% = **6.5%** |

---

### 3.4 Premium Collection Schedule

The insurance premium is charged on a **weekly basis, every Monday**, and is automatically deducted from the worker's registered payment account (UPI / Bank).

The premium amount is calculated based on:

- The worker's **average hourly income** from the previous week
- Their **worker category** (Full-time, Part-time, Weekend, Casual)
- Their **regional premium percentage** based on their operating zone

This ensures that workers only pay what is proportional to what they actually earned — no flat fees, no surprises.

---

### 3.5 Example — South Region Worker

For a delivery worker operating in the **South region**:

- Base regional premium applied: **6.5%** of daily income
- In extreme situations, payout is further adjusted according to the **Crisis Index (CI)**

---

## Phase 4: Automated Claim Verification with ML

### 4.1 Overview

When a worker submits an insurance claim, we don't want a human manually verifying every single one — that's slow, biased, and doesn't scale. So we built a **multi-signal ML pipeline** that looks at the situation from 5 different angles and makes a confident, explainable decision automatically.

---

### 4.2 How We Verify — Signal by Signal

**1. BERT — What's happening in the news?**
We use `bert-base-uncased` from HuggingFace with zero-shot classification to scan news and social content for crisis-related events like `flood`, `curfew`, `protest`, or `heatwave` — no model training needed.

**2. XGBoost — How bad is the weather?**
Live weather data is pulled from the OpenWeatherMap API and fed into an XGBoost model to generate a severity score. Tree-based models work better than neural networks for this kind of structured tabular data.

**3. Social Media Distress Score — What are people saying?**
We analyze public sentiment in the worker's area to detect widespread distress. In production this uses live feeds; for demo purposes we use the Reddit API or a pre-collected dataset.

**4. Location Matching — Was the worker actually there?**
Using the Haversine formula, we check whether the worker's logged GPS location was within the affected zone. This is what makes a claim **verifiable**, not just claimable.

**5. Activity Drop — Did they actually stop working?**
We compare today's activity against the worker's rolling 30-day average. A sudden, significant drop is a strong real-world signal that something genuinely prevented them from working.

---

### 4.3 Final Decision Model

All five signals are combined into a single weighted score:

```python
score = (0.30 * weather_score +
         0.25 * news_confidence +
         0.20 * social_score +
         0.15 * location_match +
         0.10 * activity_drop)

claim_valid = score > 0.7
```

| Signal | Weight |
|---|---|
| Weather Score | 30% |
| News Confidence (BERT) | 25% |
| Social Distress Score | 20% |
| Location Match | 15% |
| Activity Drop | 10% |

> A claim is **approved** when the final score crosses **0.7**

---

### 4.4 Claim Audit Trail

One thing we were intentional about — the system should never feel like a black box to the worker. Every claim generates a full audit log that shows exactly why it was approved or rejected:

```
Claim #1042 | Worker: Rahul S. | Area: Andheri, Mumbai
├── Weather API     : Rainfall 130mm          ✅  (score: 0.87)
├── News BERT       : "Mumbai floods" detected ✅  (confidence: 0.92)
├── Location Match  : 2.3km from flood zone   ✅
├── Activity Drop   : 90%                     ✅
└── DECISION        : APPROVED                (confidence: 0.91)
```

Every decision is traceable, fair, and explainable — both for the worker and for anyone auditing the system.

---

## Market Crash Defense — What Happens When GPS Fails

Most platforms die when GPS gets spoofed. We don't — because we never built our trust on GPS alone. The moment our system detects suspicious or unavailable GPS, it automatically switches to a **3-layer physical verification stack** that is significantly harder to fake.

---

### Layer 1 — Cell Tower Based Location

When GPS is unavailable, the device automatically falls back to cell tower triangulation. Every phone constantly connects to nearby cell towers — this cannot be turned off without losing network connectivity entirely. We use this to verify the worker is physically present in their registered working area.

**Why it works against fraud:**
- Spoofing cell towers requires specialized hardware worth lakhs of rupees
- A fraudster sitting at home cannot fake being near Andheri's cell towers while claiming to work there
- Cross-referenced against the worker's registered zone from Phase 1 onboarding

---

### Layer 2 — Accelerometer & Motion Verification

A delivery partner on a bike generates a very specific motion signature — acceleration, vibration, frequent stops, turns. A fraudster sitting at home shows completely flat, stationary data. We use the device's built-in accelerometer to verify this throughout the entire "I'm Working" session.

**What we check:**
- Consistent motion patterns during active session hours
- Speed and stop patterns consistent with delivery riding behavior
- Sudden flat/stationary data during claimed working hours triggers a flag

**Why it is the most privacy-friendly signal we have:**
- Requires zero sensitive permissions
- Reads only device motion — no location, no personal data
- Cannot be faked without physically simulating bike-like motion throughout the entire shift

---

### Layer 3 — Notification History Cross-Check

During the active session window, we log all incoming Zomato / Swiggy order notifications in real time using Android's `NotificationListenerService`. At end of day, this notification trail is matched against the session timestamps and the uploaded order history screenshot.

**What a genuine worker's trail looks like:**
```
09:14 AM — "New order assigned"
09:41 AM — "Delivered successfully"
10:03 AM — "New order assigned"
10:38 AM — "Delivered successfully"
```

**What a fraudster's trail looks like:**
- No notifications at all during claimed working hours
- Notification timestamps don't match the order history screenshot
- Identical notification patterns copy-pasted across multiple fake accounts

---

### How All Three Work Together

| Layer | What It Proves | Spoof Difficulty |
|---|---|---|
| Cell Tower Location | Worker is physically in the right area | Very Hard |
| Accelerometer Motion | Worker is actively riding and delivering | Very Hard |
| Notification History | Worker is receiving and completing real orders | Hard |

A fraudster would need to simultaneously fake their cell tower location, simulate consistent bike motion on their device, and generate a matching stream of real Zomato / Swiggy order notifications — all perfectly aligned with an uploaded order history screenshot and random selfie timestamps.

**That is not a hack. That is a full-time job.**

---

### The Audit Trail Still Applies

```
Session #2271 | Worker: Priya M. | Area: Koramangala, Bengaluru
├── GPS Signal        : Unavailable — fallback triggered   ⚠️
├── Cell Tower        : Confirmed in registered zone        ✅
├── Motion Data       : Consistent riding pattern detected  ✅
├── Notification Trail: 11 order notifications matched      ✅
├── Screenshot Match  : Timestamps align                    ✅
└── DECISION          : GENUINE WORKER (confidence: 0.96)
```

Honest workers never get punished. Every decision is explainable, traceable, and disputable.

---

## Tech Stack

Here is everything we used to build GigShield — kept lean, practical, and demo-ready.

---

### Mobile Application — Worker Facing
Built with **Flutter** for cross-platform support on both Android and iOS from a single codebase. Since most delivery workers primarily use mobile phones, the application is designed with a simple, intuitive UI that anyone can navigate without any technical knowledge.

| Feature | Details |
|---|---|
| Framework | Flutter (Dart) |
| KYC & Face Match | Camera plugin + OCR integration |
| Session Tracking | "I'm Working" / "Session Complete" buttons |
| Random Selfie Checks | In-app camera with liveness detection |
| Notification Listener | Android `NotificationListenerService` |
| Accelerometer | Flutter sensors plugin for motion tracking |
| Location | GPS + Cell Tower based fallback (Coarse Location) |
| End-of-Day Upload | Image picker for order history screenshot |

---

### Backend — Python on Replit
All business logic, ML pipelines, and API endpoints are built in **Python** and hosted on Replit for quick, accessible deployment.

| Feature | Details |
|---|---|
| Runtime | Python 3.x on Replit |
| API Framework | FastAPI |
| ML — News Analysis | HuggingFace BERT (`bert-base-uncased`) zero-shot classification |
| ML — Weather Scoring | XGBoost with OpenWeatherMap API |
| ML — Final Decision | Weighted XGBoost scoring model |
| Activity Drop Detection | Rolling 30-day average calculation |
| Location Matching | Haversine formula for GPS / cell tower verification |
| Social Distress Score | Reddit API (free tier) for sentiment analysis |
| Face Match & OCR | OpenCV + Tesseract |
| Database | PostgreSQL / SQLite for session and claim logs |

---

### Web Dashboard — Admin & Analysis
A web-based portal for platform admins to monitor workers, review flagged claims, and oversee the verification pipeline.

| Feature | Details |
|---|---|
| Framework | React.js |
| Styling | Tailwind CSS |
| Charts & Analytics | Recharts / Chart.js |
| Worker Overview | Category breakdown, session history, activity trends |
| Claim Management | Approve, reject, or escalate flagged claims |
| Audit Log Viewer | Full transparency trail for every verified session and claim |
| Fraud Ring Detection | Location clustering map to spot coordinated fraud patterns |
| Admin Controls | Manual override and dispute resolution interface |

---

## Conclusion

Gig workers are the backbone of India's food delivery ecosystem, yet they remain one of the most financially vulnerable groups in the workforce. This platform is our attempt to change that. By combining smart onboarding, real-time session tracking, fair income calculation, and an ML-powered claim verification system — we've built something that doesn't just collect data about gig workers, but actively works in their favour.

Every phase of this system, from the KYC verification in Phase 1 to the GPS spoofing defense in the Market Crash section, is designed with one goal in mind — to make sure that when a Zomato or Swiggy delivery partner has a bad day because of a flood, a heatwave, or a natural disaster, they don't have to fight to prove it. The system does that for them, fairly and transparently.

---

*Built for Guidewire DEVTrails University Hackathon*
