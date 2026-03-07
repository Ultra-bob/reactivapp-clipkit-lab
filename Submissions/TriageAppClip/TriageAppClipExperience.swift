import SwiftUI
import SmartSpectraSwiftSDK
import Speech
import Vision
import AVFoundation

struct TriageAppClipExperience: ClipExperience {
    // Set to true to bypass Presage SDK and use random vitals (saves API credits)
    private static let useMockVitals = true
    // Set to true to display the raw OCR text overlay for debugging the health card scanner
    private static let showOCRDebugView = true

    static let urlPattern = "hospital.ca/triage"
    static let clipName = "Medical Triage"
    static let clipDescription = "Submit your medical symptoms quickly from your seat"
    static let teamName = "Triage Team"

    static let touchpoint: JourneyTouchpoint = JourneyTouchpoint(
        id: "triage-submit",
        title: "Triage Submission",
        icon: "cross.fill",
        context: "Patient arriving and needs to submit symptoms.",
        notificationHint: "Follow up with patient after triage.",
        sortOrder: 10
    )
    static let invocationSource: InvocationSource = .qrCode

    let context: ClipContext

    @State private var symptoms: String = ""
    @State private var requestSeatNumber: String = ""
    @State private var requestBloodPressure: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submitted: Bool = false
    @State private var errorMessage: String? = nil

    // Health card OCR (runs on existing camera feed)
    @State private var healthCardNumber: String = ""
    @State private var ocrTimer: Timer? = nil
    @State private var ocrDebugTexts: [String] = []
    private static let ohipPattern = #"\b(\d{4})[\s\-]*(\d{3})[\s\-]*(\d{3})[\s\-]*([A-Za-z]{2})?\b"#

    // Dictation
    @State private var isDictating: Bool = false
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var recognitionTask: SFSpeechRecognitionTask? = nil
    private let audioEngine = AVAudioEngine()

    // Rolling 5-second vitals buffers: (timestamp, value)
    @State private var hrBuffer: [(Date, Float)] = []
    @State private var rrBuffer: [(Date, Float)] = []
    @State private var bpBuffer: [(Date, Float)] = []
    private let bufferWindow: TimeInterval = 5.0

    // Mock vitals timer
    @State private var mockTimer: Timer? = nil

    // Front camera for mock mode (provides preview + OCR frames)
    @StateObject private var cameraManager = CameraManager()

    @ObservedObject private var sdk = SmartSpectraSwiftSDK.shared
    @ObservedObject private var vitalsProcessor = SmartSpectraVitalsProcessor.shared

    var body: some View {
        ZStack {
            ClipBackground()

            ScrollView {
                VStack(spacing: 20) {
                    ClipHeader(
                        title: "Medical Triage",
                        subtitle: "Submit symptoms to triage desk.",
                        systemImage: "cross.case.fill"
                    )
                    .padding(.top, 16)

                    if submitted {
                        ClipSuccessOverlay(message: "Symptoms received! Please wait for a nurse.")
                    } else {
                        // Live camera preview
                        if Self.useMockVitals {
                            CameraPreviewView(cameraManager: cameraManager)
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    Text("MOCK")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange, in: Capsule())
                                        .padding(8)
                                }
                                .padding(.horizontal, 24)
                        } else if let cameraImage = vitalsProcessor.imageOutput {
                            Image(uiImage: cameraImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 24)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray5))
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.secondary)
                                        Text("Starting camera...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                )
                                .padding(.horizontal, 24)
                        }

                        VStack(alignment: .leading, spacing: 8) {

                            Text("What are your symptoms?")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 8) {
                                TextField("Describe how you feel...", text: $symptoms)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .disabled(isSubmitting)

                                Button {
                                    isDictating ? stopDictation() : startDictation()
                                } label: {
                                    Image(systemName: isDictating ? "mic.fill" : "mic")
                                        .font(.system(size: 20))
                                        .foregroundColor(isDictating ? .red : .accentColor)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(isDictating
                                                    ? Color.red.opacity(0.12)
                                                    : Color.accentColor.opacity(0.08))
                                        )
                                }
                                .disabled(isSubmitting)
                                .accessibilityLabel(isDictating ? "Stop dictation" : "Start dictation")
                            }
                                
                            let hrMedian = median(of: hrBuffer)
                            let rrMedian = median(of: rrBuffer)
                            let bpMedian = median(of: bpBuffer)

                            if hrMedian == nil && rrMedian == nil && bpMedian == nil {
                                Text(vitalsProcessor.statusHint.isEmpty ? "Waiting for face..." : vitalsProcessor.statusHint)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(.top, 8)
                            } else {
                                HStack(spacing: 24) {
                                    if let hr = hrMedian {
                                        VStack(alignment: .leading) {
                                            Text("Heart Rate")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(Int(hr)) BPM")
                                                .font(.headline)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    if let rr = rrMedian {
                                        VStack(alignment: .leading) {
                                            Text("Breathing")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(Int(rr)) RPM")
                                                .font(.headline)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    if let bp = bpMedian {
                                        VStack(alignment: .leading) {
                                            Text("Blood Pressure")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("\(Int(bp)) mmHg")
                                                .font(.headline)
                                                .foregroundColor(.purple)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Health card (optional — auto-scanned from camera)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Health Card (Optional)")
                                .font(.headline)
                                .foregroundColor(.primary)

                            HStack(spacing: 8) {
                                TextField("Card number", text: $healthCardNumber)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.body.monospacedDigit())
                                    .disabled(isSubmitting)

                                if !healthCardNumber.isEmpty {
                                    Button {
                                        healthCardNumber = ""
                                        startOCRScanning()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            if healthCardNumber.isEmpty {
                                Label("Hold your health card up to the camera to scan", systemImage: "camera.viewfinder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Label("Card detected!", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            // Debug: show raw OCR text
                            if Self.showOCRDebugView, !ocrDebugTexts.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("DEBUG — OCR")
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                    ForEach(Array(ocrDebugTexts.enumerated()), id: \.offset) { _, text in
                                        Text(text)
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 24)

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.footnote)
                                .padding(.horizontal, 24)
                        }

                        ClipActionButton(title: isSubmitting ? "Submitting..." : "Submit", icon: "paperplane.fill") {
                            submitSymptoms()
                        }
                        .disabled(symptoms.isEmpty || isSubmitting)
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            requestSeatNumber = context.queryParameters["seatNumber"] ?? ""

            if Self.useMockVitals {
                startMockVitals()
                cameraManager.start()
            } else {
                SmartSpectraSwiftSDK.shared.setApiKey("ShdNWcKc0D5alluayVgzv75yQxjWfOg3953qUs4M")
                sdk.setSmartSpectraMode(.continuous)
                sdk.setMeasurementDuration(30.0)
                sdk.setCameraPosition(.front)
                vitalsProcessor.startProcessing()
                vitalsProcessor.startRecording()
            }
            startOCRScanning()
        }
        .onDisappear {
            stopOCRScanning()
            if Self.useMockVitals {
                stopMockVitals()
                cameraManager.stop()
            } else {
                vitalsProcessor.stopRecording()
                vitalsProcessor.stopProcessing()
            }
        }
        .onChange(of: sdk.metricsBuffer) { metrics in
            guard !Self.useMockVitals else { return }
            guard let metrics = metrics else { return }
            let now = Date()
            let cutoff = now.addingTimeInterval(-bufferWindow)

            if let hr = metrics.pulse.rate.last?.value {
                hrBuffer.append((now, hr))
                hrBuffer.removeAll { $0.0 < cutoff }
            }
            if let rr = metrics.breathing.rate.last?.value {
                rrBuffer.append((now, rr))
                rrBuffer.removeAll { $0.0 < cutoff }
            }
            if let bp = metrics.bloodPressure.phasic.last?.value {
                bpBuffer.append((now, bp))
                bpBuffer.removeAll { $0.0 < cutoff }
            }
        }

    }

    private func submitSymptoms() {
        guard !symptoms.isEmpty else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        let url = URL(string: "https://hack-canada2026-dashboard.vercel.app/api/triage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build payload matching the API format
        let seatNumber = context.queryParameters["seatNumber"].flatMap(Int.init) ?? 1
        let hrValue = median(of: hrBuffer).map { Int($0) } ?? -1
        let rrValue = median(of: rrBuffer).map { Int($0) } ?? -1
        let bpValue = median(of: bpBuffer).map { Int($0) } ?? -1
        let bloodPressureString = "\(bpValue)"
        let healthCard = healthCardNumber.isEmpty ? "unknown" : healthCardNumber

        let payload: [String: Any] = [
            "seatNumber": seatNumber,
            "heartRate": hrValue,
            "respiratoryRate": rrValue,
            "bloodPressure": bloodPressureString,
            "symptoms": symptoms,
            "healthCardNumber": healthCard
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Submitting payload: \(jsonString)")
            }
        } catch {
            errorMessage = "Failed to format data"
            isSubmitting = false
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSubmitting = false
                
                if let error = error {
                    print("Network error submitting symptoms: \(error)")
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        print("Symptoms submitted successfully")
                        submitted = true
                    } else {
                        print("Server returned error status code: \(httpResponse.statusCode)")
                        var errorDisplay = "Server returned error: \(httpResponse.statusCode)"
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("Server response: \(responseString)")
                            errorDisplay += "\nDetails: \(responseString)"
                        }
                        errorMessage = errorDisplay
                    }
                } else {
                    print("Unknown network response format")
                    errorMessage = "Server returned unknown error"
                }
            }
        }.resume()
    }

    // Median over a rolling buffer of (Date, Float) samples.
    private func median(of buffer: [(Date, Float)]) -> Float? {
        let values = buffer.map { $0.1 }
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    // MARK: - Mock Vitals

    private func startMockVitals() {
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let now = Date()
            let cutoff = now.addingTimeInterval(-bufferWindow)

            let hr = Float.random(in: 60...100)
            let rr = Float.random(in: 12...20)
            let bp = Float.random(in: 90...140)

            hrBuffer.append((now, hr))
            hrBuffer.removeAll { $0.0 < cutoff }

            rrBuffer.append((now, rr))
            rrBuffer.removeAll { $0.0 < cutoff }

            bpBuffer.append((now, bp))
            bpBuffer.removeAll { $0.0 < cutoff }
        }
    }

    private func stopMockVitals() {
        mockTimer?.invalidate()
        mockTimer = nil
    }

    // MARK: - Health Card OCR (runs on camera feed)

    private func startOCRScanning() {
        // Don't scan if we already have a number
        guard healthCardNumber.isEmpty else { return }
        ocrTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard healthCardNumber.isEmpty else {
                stopOCRScanning()
                return
            }
            if let image = Self.useMockVitals ? cameraManager.latestFrame : vitalsProcessor.imageOutput {
                runOCROnFrame(image)
            }
        }
    }

    private func stopOCRScanning() {
        ocrTimer?.invalidate()
        ocrTimer = nil
    }

    private func runOCROnFrame(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            let texts = observations.compactMap { $0.topCandidates(1).first?.string }

            DispatchQueue.main.async {
                ocrDebugTexts = texts
            }

            let combined = texts.joined(separator: " ")

            guard let regex = try? NSRegularExpression(pattern: Self.ohipPattern, options: []) else { return }
            let range = NSRange(combined.startIndex..., in: combined)
            guard let match = regex.firstMatch(in: combined, options: [], range: range) else { return }

            guard let g1Range = Range(match.range(at: 1), in: combined),
                  let g2Range = Range(match.range(at: 2), in: combined),
                  let g3Range = Range(match.range(at: 3), in: combined) else { return }

            var formatted = "\(combined[g1Range])-\(combined[g2Range])-\(combined[g3Range])"

            if match.range(at: 4).location != NSNotFound,
               let vcRange = Range(match.range(at: 4), in: combined) {
                formatted += "-\(combined[vcRange].uppercased())"
            }

            DispatchQueue.main.async {
                healthCardNumber = formatted
                stopOCRScanning()
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    // MARK: - Dictation

    private func startDictation() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized, let recognizer = speechRecognizer, recognizer.isAvailable else {
                    errorMessage = "Speech recognition is not available."
                    return
                }
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    recognitionRequest = request

                    recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                        if let result = result {
                            let text = result.bestTranscription.formattedString
                            if !text.isEmpty {
                                symptoms = text
                            }
                        }
                        if error != nil || (result?.isFinal ?? false) {
                            stopDictation()
                        }
                    }

                    let inputNode = audioEngine.inputNode
                    let format = inputNode.outputFormat(forBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        request.append(buffer)
                    }

                    audioEngine.prepare()
                    try audioEngine.start()
                    isDictating = true
                } catch {
                    errorMessage = "Dictation failed to start: \(error.localizedDescription)"
                    stopDictation()
                }
            }
        }
    }

    private func stopDictation() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isDictating = false
    }
}
