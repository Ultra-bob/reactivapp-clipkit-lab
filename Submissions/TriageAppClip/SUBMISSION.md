## Team Name: Triage Team
## Clip Name: Medical Triage
## Invocation URL Pattern: `hospital.ca/triage?seat={seatNumber}`

---

### 1. Problem Framing

Which user moment or touchpoint are you targeting?

- [ ] Discovery / first awareness
- [ ] Intent / consideration
- [ ] Purchase / conversion
- [x] In-person / on-site interaction
- [ ] Post-purchase / re-engagement
- [ ] Other: ___

**What friction or missed opportunity are you solving for?**

Emergency rooms and walk-in clinics are bottlenecked at intake. Patients wait in line to hand over a health card and describe symptoms to a clerk — before any clinical assessment begins. Vital signs are only captured once a nurse is available, meaning the sickest patients can sit undetected while healthier ones are seen first simply because they arrived earlier. This App Clip lets patients scan a QR code at their seat and, within seconds, have vitals captured contactlessly via the front camera, their Ontario Health Card scanned via inline OCR, and symptoms submitted via text or voice dictation — compressing the entire intake into a self-service step completed before seeing a nurse.

> **The App Clip fit:** Would a patient install a full app for a single ER visit? No. Would they scan a code on their chair to skip the line? Absolutely. That's a clip.

---

### 2. Proposed Solution

**How is the Clip invoked?**
- [x] QR Code (printed on physical surface — laminated cards on each waiting room seat, encoding the seat number as a URL parameter)

**End-to-end user experience:**
1. **Scan** — Patient scans the QR code on their seat. The Clip launches; seat number is extracted from the URL automatically.
2. **Step 1 — Contactless Vitals** — Front camera activates and captures heart rate, respiratory rate, and blood pressure via the Presage SmartSpectra SDK (a lightweight client that sends frames to a server-side API — no bundled ML models). Live readings appear as colour-coded pill badges. Auto-advances after 5 seconds of stable data.
3. **Step 2 — Health Card OCR** — Camera feed continues; Vision framework runs text recognition every second, matching OHIP format (`XXXX-XXX-XXX-XX`). Auto-advances on detection. "I don't have my health card" button allows skipping.
4. **Step 3 — Symptoms** — Text editor with inline voice dictation (Speech framework). Tap Submit → JSON payload (seat number, median vitals, health card number, symptoms) POSTed to backend API.
5. **Confirmation** — Success overlay: "Symptoms received! Please wait for a nurse." Total time: **under 30 seconds**.

**What happens on the backend (outside the clip):**
- Triage data arrives on a **nurse dashboard** where **AI automatically sorts patients by urgency** based on vitals and symptoms.
- If a health card was provided, the dashboard displays (mock) patient data: allergens, blood type, and known conditions.
- If **multiple submissions arrive with the same seat number**, the triage is updated using both old and new data, letting nurses see if a waiting patient's condition is worsening.

**How does the 8-hour notification window factor into your strategy?**
Hospital visits often span 2–6 hours — well within the 8-hour window. This enables:
- **Wait time updates** — "You are 3rd in queue. Estimated wait: 20 minutes."
- **Triage priority changes** — "A nurse will see you shortly — your case has been prioritized."
- **Post-visit follow-up** — "Your visit summary is ready. Tap to view discharge instructions."

---

### 3. Platform Extensions (if applicable)

This solution proposes one new platform capability: a **camera-to-biometrics pipeline** — a configurable integration point where any Reactiv Clip can route front-camera frames to a third-party biometric SDK for real-time analysis.

**How it works:** The Clip builder exposes a "Camera Biometrics" block. The merchant (or Reactiv partner) selects a provider (e.g. Presage SmartSpectra), configures which signals to capture, and the pipeline handles frame routing, result buffering, and UI binding — no custom code required. The biometric computation happens entirely server-side via the provider's API, so no ML models are bundled and the Clip stays well within the 15 MB size limit.

This single capability unlocks two verticals:

**Healthcare — Contactless vitals for clinical intake:**
- Heart rate, respiratory rate, and blood pressure captured from the front camera in seconds.
- Enables self-service triage: patients scan a QR code, vitals are measured automatically, and the data is submitted to a nurse dashboard.
- Applicable to ERs, walk-in clinics, urgent care, and event medical tents.

**E-commerce — Emotion and engagement sensing:**
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
| AVFoundation | Camera access for vitals and OCR |
| Vision | `VNRecognizeTextRequest` for health card OCR |
| Speech | `SFSpeechRecognizer` for voice dictation |
| SwiftUI | Entire UI |
| URLSession | API submission |

> **Note on the Presage SDK:** The prototype integrates the Presage SmartSpectra SDK for contactless vitals. This is a lightweight API client (all computation is server-side) and was used to demonstrate the biometrics pipeline concept. In a production Reactiv Clip, the SDK integration would be a platform-level concern — configured in the Reactiv builder, not bundled per-clip. The prototype includes a `useMockVitals` flag that bypasses the SDK entirely, generating random vitals locally to demonstrate the flow without any external dependency.

---

### 4. Prototype Description

The prototype implements `TriageAppClipExperience` with a complete 3-stage flow:

| Stage | What it does | Key tech |
|---|---|---|
| **Face Scan** | Contactless vitals via front camera. HR, RR, BP displayed as live median values (rolling 5-second buffer). Auto-advances after 5s of stable data. | Presage SmartSpectra SDK (lightweight client; server-side processing) / Mock mode available |
| **Health Card OCR** | Inline text recognition matching OHIP regex. Auto-detects and auto-advances. Skip button available. | Vision `VNRecognizeTextRequest` |
| **Symptom Entry** | Text editor with inline dictation toggle. Submit POSTs JSON payload to dashboard API. | Speech framework, URLSession |
| **Success** | `ClipSuccessOverlay` confirmation. | Built-in component |

**Additional details:**
- `useMockVitals` flag generates random vitals locally (saves API credits and demonstrates the flow with zero external dependencies).
- `showOCRDebugView` flag renders raw OCR text for testing card detection.
- `HealthCardScannerView.swift` provides `CameraManager` (AVCaptureSession wrapper) and `CameraPreviewView` (UIViewRepresentable).

**Test:** Enter `hospital.ca/triage?seat=5` in the Invocation Console → complete all 3 stages → observe success screen.

---

### 5. Impact Hypothesis

**Channel:** In-person healthcare facilities, deployed as a government-partnered SaaS platform.

**Business model:** Reactiv partners with provincial and federal health authorities to deploy Health Clips across publicly funded hospitals and clinics. Revenue is generated through:

| Revenue stream | Model |
|---|---|
| **Per-facility licensing** | Monthly SaaS fee per hospital/clinic deploying Reactiv Health Clips (comparable to existing EHR subscriptions) |
| **Per-interaction usage** | Volume-based pricing per patient triage completed through the Clip (analogous to payment processing fees) |
| **Platform expansion** | The Health Clip vertical opens Reactiv to an entirely new market — Canadian healthcare spends $330B+ annually, and digital intake is a greenfield opportunity |

**Measurable impact:**

| Metric | Expected improvement | Reasoning |
|---|---|---|
| **Per-patient intake time** | Reduced by 2–4 minutes | Vitals, health card, and symptoms captured before nurse interaction — eliminating the data-collection portion of intake. |
| **Front-desk throughput** | 30–50% more patients processed per hour | Self-service intake at the seat removes the single-threaded bottleneck of clerk-based registration. |
| **Triage accuracy** | Significant improvement | AI-sorted dashboard ensures high-acuity patients are seen first, regardless of arrival order. Vitals data available immediately instead of 20–40 minutes into the visit. |
| **Patient walk-out rate** | Reduced | Wait time notifications and visible progress reduce abandonment — each walk-out is lost revenue for the facility. |
| **Cost per triage** | Lower than current manual intake | Self-service capture reduces staff-hours per patient, directly reducing operational cost. |

**Why this touchpoint is the right place to intervene:**
Every patient passes through the waiting room (100% capture rate), is stationary with phone in hand (ideal for App Clip), and the information collected has direct clinical value. The interaction is inherently ephemeral — no patient will return to the same seat for the same visit. This is the "scan, do, done" pattern App Clips were designed for.

**Scalability:**
- **Walk-in clinics** — QR codes at check-in desks
- **Urgent care centres** — Triage at scale during flu season surges
- **Event medical tents** — Concert venues, sports arenas, and festivals where temporary medical stations need rapid intake with zero infrastructure
- **Telehealth pre-screening** — A QR code texted to a patient before a video call, capturing vitals in advance

The event medical tent use-case is particularly relevant to the Reactiv Clips platform: a QR code at a concert medical station lets a fan submit symptoms and vitals without downloading anything, and the 8-hour notification window covers the entire event duration for follow-up.

---

### Constraint Awareness

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
| **Available frameworks** | AVFoundation (camera), Vision (OCR), Speech (dictation) are all available for real App Clips. SwiftUI, UIKit, and URLSession are standard. |

---

### Novel Use-Case Argument

The hackathon asks: *"What experience fits the shape of an App Clip that nobody has built yet?"*

**Medical triage is a perfect App Clip shape that no one has explored:**

1. **Truly ephemeral** — A patient visits an ER once. They will never install an app for it. But they will scan a QR code if it means faster care.
2. **Physical-digital bridge** — The QR code on the seat connects a physical location (the chair) to a digital action (submitting vitals and symptoms). The seat number becomes the patient identifier.
3. **Zero-commitment, high-value** — The patient gives 30 seconds and zero personal data beyond what they would give to the intake clerk anyway. In return, they skip the line.
4. **Time-critical** — The 8-hour notification window aligns perfectly with a hospital visit, enabling continuous communication without an app download.
5. **Untapped domain** — App Clips have been used for parking, coffee orders, and restaurant check-ins. Healthcare intake is a fundamentally different domain where the same constraints (no install, instant value, single task) unlock massive operational and commercial benefit.

> App Clips were designed for 30-second commerce moments. We're applying the same instant, no-install, scan-and-go pattern to save lives instead of selling lattes — and opening a $330B healthcare market for the Reactiv platform.

---

### Demo Video

Link: *(to be added)*

### Screenshot(s)
*(to be added)*
