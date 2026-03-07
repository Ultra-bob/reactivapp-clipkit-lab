# Solution: Medical Triage App Clip

## Team Name: Triage Team
## Clip Name: Medical Triage
## Invocation URL Pattern: `hospital.ca/triage?seat={seatNumber}`

---

## 1. Problem Framing

**Targeted touchpoint:** In-person / on-site interaction

**The friction we are solving:**

Emergency rooms and walk-in clinics are bottlenecked at intake. When patients arrive, they wait in line just to hand over a health card and verbally describe symptoms to a clerk — before any clinical assessment begins. Vital signs (heart rate, respiratory rate, blood pressure) are only captured once a nurse is available, meaning the sickest patients can sit undetected in the waiting room while healthier ones are seen first simply because they arrived earlier.

This creates three compounding problems:

1. **Intake bottleneck** — Front-desk staff spend several minutes per patient collecting information that the patient could self-report.
2. **Delayed triage** — Without vitals, nurses cannot prioritize effectively. A patient with dangerously elevated heart rate looks the same as everyone else in the queue.
3. **Patient frustration** — Sitting in a busy waiting room with no indication that anyone knows you're there, or how long you'll wait, drives dissatisfaction and walk-outs.

An App Clip is the ideal shape for this problem because patients have zero interest in downloading a hospital app for a single visit. They need to submit information *right now*, from their seat, in under a minute. No account, no onboarding, no commitment.

> **The key-question test:** Would a patient install a full app for a single ER visit? No. Would they scan a code on their chair to skip the line? Absolutely. That's a clip.

---

## 2. Proposed Solution

### How is the Clip invoked?

- **QR Code** — printed on laminated cards attached to each seat in the waiting room. Each QR code encodes the seat number as a URL parameter (e.g., `hospital.ca/triage?seat=14`).

This is the most natural invocation method because:
- Every patient is already seated and stationary (ideal for a camera-based flow).
- The QR code physically labels the seat, so nurses can locate the patient.
- No NFC tap or link sharing is needed — the patient just points their phone at the card on their armrest.

### End-to-end user experience

1. **Scan** — Patient scans the QR code on their seat. The App Clip launches instantly. The seat number is extracted from the URL automatically — no manual entry required.

2. **Step 1 — Contactless Vitals (Face Scan)** — The Clip activates the front camera and begins capturing heart rate, respiratory rate, and blood pressure contactlessly via the Presage SmartSpectra SDK. The patient simply holds still and looks at the screen. Live readings appear as colour-coded pill badges. After 5 seconds of stable data, the Clip auto-advances to the next step. No buttons needed.

3. **Step 2 — Health Card OCR** — The camera feed continues, but now the patient is prompted to hold their Ontario Health Card in front of the camera. The Vision framework runs text recognition every second, matching the OHIP number format (`XXXX-XXX-XXX-XX`). Once detected, the number is displayed with a confirmation checkmark and the Clip auto-advances after 1.5 seconds. A "I don't have my health card" button allows skipping — because the clip must never block on optional data.

4. **Step 3 — Symptom Entry** — A text editor appears with a built-in voice dictation button (using the Speech framework). The patient can type or speak their symptoms. They tap "Submit" and a JSON payload containing seat number, median vitals, health card number, and symptoms is POSTed to the backend API.

5. **Confirmation** — A `ClipSuccessOverlay` confirms "Symptoms received! Please wait for a nurse." The patient puts their phone down. Total time: **under 30 seconds**.

### What happens on the backend (outside the clip)

The triage payload is received by a **nurse dashboard** that:

- **AI-sorts patients by urgency** — Vitals and symptoms are analysed to automatically rank patients. A patient reporting "chest pain" with a heart rate of 130 bpm is surfaced above a patient with a minor cough and normal vitals.
- **Displays health card data** — If a health card was provided, the dashboard uses mock data to show the patient's allergens, blood type, and known conditions — giving the nurse context before they even approach the seat.
- **Supports re-triage** — If a patient's condition changes while waiting, they can re-scan the QR code and submit again. Because the seat number is the same, the dashboard merges the old and new data, showing the nurse a trend (e.g., "heart rate was 85, now 110 — condition may be worsening").

### How does the 8-hour notification window factor into the strategy?

The 8-hour ephemeral push notification window is valuable in a clinical context:

- **Wait time updates** — "You are 3rd in queue. Estimated wait: 20 minutes." Reduces perceived wait time and prevents walk-outs.
- **Triage priority changes** — "A nurse will see you shortly — your case has been prioritized." Provides real-time feedback if AI re-sorts the queue.
- **Lab/test results** — If blood work or imaging is completed during the visit, a notification can direct the patient back to the Clip with results.
- **Post-visit follow-up** — "Your visit summary is ready. Tap to view your discharge instructions." This could link back to the Clip or to a full app download prompt.

This is especially powerful because hospital visits often span 2–6 hours — well within the 8-hour window.

---

## 3. Platform Extensions

This solution proposes one new platform capability: a **camera-to-biometrics pipeline** — a configurable integration point where any Reactiv Clip can route front-camera frames to a third-party biometric SDK for real-time analysis.

**How it works:** The Clip builder exposes a "Camera Biometrics" block. The merchant (or Reactiv partner) selects a provider (e.g. Presage SmartSpectra), configures which signals to capture, and the pipeline handles frame routing, result buffering, and UI binding — no custom code required. The biometric computation happens entirely server-side via the provider's API, so no ML models are bundled and the Clip stays well within the 15 MB size limit.

This single capability unlocks two verticals:

### Healthcare — Contactless vitals for clinical intake
- Heart rate, respiratory rate, and blood pressure captured from the front camera in seconds.
- Enables self-service triage: patients scan a QR code, vitals are measured automatically, and the data is submitted to a nurse dashboard.
- Applicable to ERs, walk-in clinics, urgent care, and event medical tents.

### E-commerce — Emotion and engagement sensing
The same camera-to-biometrics pipeline that reads vitals can also measure **user emotional state and engagement** during a Clip session. Elevated heart rate, micro-expressions, and attention signals (gaze tracking, blink rate) provide real-time data that Reactiv merchants can act on:

| Signal | E-commerce application |
|---|---|
| **Heart rate elevation** | Detects excitement during product browsing — trigger a limited-time offer when a fan's heart rate spikes while viewing merch. |
| **Attention / gaze** | Measures which products receive the most visual attention — surface those items first or push a notification about them later within the 8-hour window. |
| **Engagement duration** | Identifies high-intent users who linger on a product — prompt them with a discount before they leave the Clip. |
| **Emotional valence** | Detects positive reactions (smiling) to specific items — personalise follow-up notifications: *"You loved the tour hoodie — it's still available with free shipping."* |

This transforms Reactiv Clips from passive storefronts into **adaptive, emotionally-aware commerce experiences** — the first platform to offer real-time biometric personalisation at the App Clip layer. For concert merch, imagine a fan scanning a QR code at the booth: the Clip reads their excitement level and dynamically surfaces the merch they're most likely to buy, then pushes a follow-up notification timed to their peak engagement window.

**Frameworks used by the prototype:**

| Framework | Usage |
|---|---|
| **AVFoundation** | Camera access for both vitals capture and health card scanning |
| **Vision** | `VNRecognizeTextRequest` for inline OCR of the health card number |
| **Speech** | `SFSpeechRecognizer` for voice-to-text symptom dictation |
| **SwiftUI** | Entire UI layer |
| **URLSession** | API submission |

> **Note on the Presage SDK:** The Presage SmartSpectra SDK is a lightweight client library that captures camera frames on-device and sends them to a server-side API for all vital sign computation. There are no bundled ML models or heavy processing binaries. In a production Reactiv Clip, the SDK integration would be a platform-level concern — configured in the Reactiv builder, not bundled per-clip. The prototype includes a `useMockVitals` flag that bypasses the SDK entirely, generating random vitals locally to demonstrate the full flow with zero external dependencies.

---

## 4. Prototype Description

The working prototype implements `TriageAppClipExperience` as a single `ClipExperience` view with a complete 3-stage flow:

### Implemented screens & flows

| Stage | What it does | Key tech |
|---|---|---|
| **Face Scan** | Contactless vitals via front camera. Heart rate, respiratory rate, and phasic blood pressure displayed in live pill badges. Rolling 5-second median buffer smooths readings. Auto-advances after 5 seconds of stable data. | Presage SmartSpectra SDK (lightweight client; all processing is server-side via API) / Mock mode available |
| **Health Card OCR** | Inline text recognition on the live camera feed. Matches Ontario Health Card (OHIP) regex pattern. Auto-detects and auto-advances. Skip button available. | Vision `VNRecognizeTextRequest` |
| **Symptom Entry** | Text editor with inline dictation toggle. Red mic icon indicates active recording. Submit POSTs JSON payload to backend API. | Speech framework, URLSession |
| **Success** | `ClipSuccessOverlay` with confirmation message. | Built-in component |

### Additional implementation details

- **Mock vitals mode** — A `useMockVitals` flag generates random vital values locally, preserving API credits during development and demonstrating the full flow with zero external dependencies. When enabled, a separate `CameraManager` provides the camera preview (since the SmartSpectra SDK is bypassed).
- **Rolling buffers** — Heart rate, respiratory rate, and blood pressure are stored in `(Date, Float)` tuples with a 5-second sliding window. The median is computed for both live display and the final payload, smoothing out momentary spikes.
- **OCR debug overlay** — A `showOCRDebugView` flag renders raw OCR text on-screen, useful for testing card detection in different lighting conditions.
- **Error handling** — Network errors, server error codes, and response bodies are displayed inline. Loading state disables the submit button to prevent double submission.

### Supporting files

- `HealthCardScannerView.swift` — Contains `CameraManager` (an `AVCaptureSession` wrapper that provides camera preview frames and exposes `latestFrame` for OCR) and `CameraPreviewView` (a `UIViewRepresentable` bridge for the live camera feed).

### How to test

1. Run the simulator (`Cmd+R`).
2. Enter `hospital.ca/triage?seat=5` in the Invocation Console.
3. The clip opens and begins the face scan stage.
4. After vitals stabilize (5 seconds), it advances to health card scanning.
5. Present a card with an OHIP-format number, or tap "I don't have my health card."
6. Enter symptoms via text or dictation, then tap Submit.
7. Observe the success confirmation screen.

---

## 5. Impact Hypothesis

### Business model: Government-partnered SaaS for healthcare

Reactiv partners with provincial and federal health authorities to deploy Health Clips across publicly funded hospitals and clinics. This opens a new vertical for the Reactiv platform beyond commerce.

### Revenue model

| Revenue stream | Model |
|---|---|
| **Per-facility licensing** | Monthly SaaS fee per hospital/clinic deploying Reactiv Health Clips (comparable to existing EHR subscriptions) |
| **Per-interaction usage** | Volume-based pricing per patient triage completed through the Clip (analogous to payment processing fees) |
| **Platform expansion** | The Health Clip vertical opens Reactiv to an entirely new market — Canadian healthcare spends $330B+ annually, and digital intake is a greenfield opportunity |

### Measurable impact

| Metric | Expected improvement | Reasoning |
|---|---|---|
| **Per-patient intake time** | Reduced by 2–4 minutes | Vitals, health card, and symptoms are captured before the nurse interaction — eliminating the data-collection portion of intake. |
| **Front-desk throughput** | 30–50% more patients processed per hour | Self-service intake at the seat removes the single-threaded bottleneck of clerk-based registration. |
| **Triage accuracy** | Significant improvement in prioritization | AI-sorted dashboard ensures high-acuity patients are seen first, regardless of arrival order. Vitals data that would otherwise only be captured 20–40 minutes into the visit is available immediately. |
| **Patient walk-out rate** | Reduced | Wait time notifications and visible progress reduce abandonment — each walk-out is lost revenue for the facility. |
| **Cost per triage** | Lower than current manual intake | Self-service capture reduces staff-hours per patient, directly reducing operational cost for the facility. |

### Why this touchpoint is the right place to intervene

The waiting room is a **high-friction, high-volume, time-critical** touchpoint where:

- Every patient passes through it (100% capture rate).
- The patient is stationary and has their phone in hand (ideal for an App Clip interaction).
- The information collected (vitals, health card, symptoms) has direct clinical value.
- There is no alternative digital channel — patients currently have no way to self-report without waiting for staff.
- The interaction is inherently ephemeral — a patient will never return to the same waiting room seat for the same visit. This is exactly the "scan, do, done" pattern App Clips are designed for.

### Broader scalability

The same pattern generalises beyond emergency departments:

- **Walk-in clinics** — QR codes at check-in desks
- **Urgent care centres** — Triage at scale during flu season surges
- **Event medical tents** — Concert venues, sports arenas, and festivals where temporary medical stations need rapid intake with zero infrastructure
- **Telehealth pre-screening** — A QR code texted to a patient before a video call, capturing vitals in advance

The event medical tent use-case is particularly relevant to the Reactiv Clips platform: a QR code at a concert medical station lets a fan submit symptoms and vitals without downloading anything, and the 8-hour notification window covers the entire duration of the event for follow-up.

---

## 6. Constraint Awareness

Every design decision maps back to a real App Clip constraint:

| Constraint | How we address it |
|---|---|
| **URL-based invocation** | QR codes on each seat encode `hospital.ca/triage?seat={n}`. The URL parameter drives the entire experience — no manual input needed. |
| **15 MB size limit** | No bundled images, models, or assets. UI is entirely SwiftUI. Vitals computation happens server-side. OCR and speech recognition use on-device Apple frameworks (Vision, Speech). |
| **Ephemeral lifecycle** | No saved state, no accounts, no login. Each scan is self-contained. The seat number provides identity. If the patient re-scans, the backend handles de-duplication by seat. |
| **30-second moment** | The 3-step flow (face scan → health card → symptoms) is designed to complete in under 30 seconds. Face scan auto-advances after 5 seconds. Health card auto-advances on detection. Symptom entry is a single text field with a submit button. |
| **Single focused task** | One task: submit your triage information. No browsing, no history, no settings. |
| **8-hour notification window** | Used for wait time updates, triage priority changes, and post-visit follow-up — all within a typical hospital visit window. |
| **No onboarding** | The QR code on the seat *is* the onboarding. "Scan to check in" is self-explanatory. The Clip opens directly into the face scan with a single instruction line. |
| **Available frameworks** | AVFoundation (camera), Vision (OCR), Speech (dictation) are all in the "Available" list for real App Clips. SwiftUI, UIKit, and URLSession are standard. |

---

## 7. Novel Use-Case Argument

The hackathon asks: *"What experience fits the shape of an App Clip that nobody has built yet?"*

**Medical triage is a perfect App Clip shape that no one has explored:**

1. **Truly ephemeral** — A patient visits an ER once. They will never install an app for it. But they will scan a QR code if it means faster care.
2. **Physical-digital bridge** — The QR code on the seat connects a physical location (the chair) to a digital action (submitting vitals and symptoms). The seat number becomes the patient identifier.
3. **Zero-commitment, high-value** — The patient gives 30 seconds and zero personal data beyond what they would give to the intake clerk anyway. In return, they skip the line.
4. **Time-critical** — The 8-hour notification window aligns perfectly with a hospital visit, enabling continuous communication without an app download.
5. **Untapped domain** — App Clips have been used for parking, coffee orders, and restaurant check-ins. Healthcare intake is a fundamentally different domain where the same constraints (no install, instant value, single task) unlock massive operational and commercial benefit.
6. **New market for Reactiv** — This is not just a novel use-case for App Clips — it's a novel *vertical* for the Reactiv platform. The same no-code builder that serves Shopify merchants can serve hospitals, opening a $330B+ healthcare market.

> App Clips were designed for 30-second commerce moments. We're applying the same instant, no-install, scan-and-go pattern to save lives instead of selling lattes — and opening a $330B healthcare market for the Reactiv platform.
