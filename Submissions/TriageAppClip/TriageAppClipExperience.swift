import SwiftUI
import SmartSpectraSwiftSDK
import Speech
import Vision
import AVFoundation

struct TriageAppClipExperience: ClipExperience {
    // Set to true to bypass Presage SDK and use random vitals (saves API credits)
    private static let useMockVitals = false
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

    // Stages
    enum TriageStage {
        case faceScan
        case healthCard
        case symptoms
    }
    @State private var currentStage: TriageStage = .faceScan
    @State private var firstVitalReceivedTime: Date? = nil

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
        // Custom colors for the design
        let headerGreen = Color(red: 0.78, green: 0.89, blue: 0.55)
        let headerTextDarkBlue = Color(red: 0.19, green: 0.33, blue: 0.45)
        let paleBluePill = Color(red: 0.71, green: 0.83, blue: 0.92)
        let paleTealPill = Color(red: 0.70, green: 0.87, blue: 0.82)
        let paleGreenPill = Color(red: 0.78, green: 0.89, blue: 0.55)
        let dictationBg = Color(red: 0.62, green: 0.75, blue: 0.88)
        let buttonDarkBlue = Color(red: 0.19, green: 0.28, blue: 0.45)
        let textFieldGray = Color(red: 0.92, green: 0.92, blue: 0.92)

        VStack(spacing: 0) {
            // Header Logo Area
            ZStack(alignment: .bottom) {
                headerGreen
                    .ignoresSafeArea(.all, edges: .top)
                
                Text("Welcome")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(headerTextDarkBlue)
                    .padding(.bottom, 16)
            }
            .frame(height: 70)

            ScrollView {
                VStack(spacing: 20) {
                    if submitted {
                        ClipSuccessOverlay(message: "Symptoms received! Please wait for a nurse.")
                            .padding(.top, 40)
                    } else {
                        // Title for current stage
                        if currentStage == .faceScan {
                            Text("**Step 1:** Hold still and scan your face")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                        } else if currentStage == .healthCard {
                            Text("**Step 2:** Scan the front of your\nOntario Health Card")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                        } else if currentStage == .symptoms {
                            Text("**Step 3:** Describe your symptoms")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                        }

                        // Live camera preview needed during face scan and health card scan
                        if currentStage == .faceScan || currentStage == .healthCard {
                            if Self.useMockVitals {
                                CameraPreviewView(cameraManager: cameraManager)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 240)
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
                                    .transition(.opacity)
                            } else if let cameraImage = vitalsProcessor.imageOutput {
                                Image(uiImage: cameraImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal, 24)
                                    .transition(.opacity)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray5))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 240)
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
                                    .transition(.opacity)
                            }
                        }

                        if currentStage == .faceScan {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Results:")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.primary)

                                let hrMedian = median(of: hrBuffer)
                                let rrMedian = median(of: rrBuffer)
                                let bpMedian = median(of: bpBuffer)

                                HStack(spacing: 12) {
                                    if hrMedian == nil && rrMedian == nil && bpMedian == nil {
                                        Text(vitalsProcessor.statusHint.isEmpty ? "Waiting for face..." : vitalsProcessor.statusHint)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    } else {
                                        if let hr = hrMedian {
                                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                                Text("\(Int(hr))")
                                                    .font(.system(size: 16, weight: .bold))
                                                Text("bpm")
                                                    .font(.system(size: 14))
                                            }
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(paleBluePill, in: Capsule())
                                        }
                                        if let rr = rrMedian {
                                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                                Text("\(Int(rr))")
                                                    .font(.system(size: 16, weight: .bold))
                                                Text("/min")
                                                    .font(.system(size: 14))
                                            }
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(paleTealPill, in: Capsule())
                                        }
                                        if let bp = bpMedian {
                                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                                Text("\(Int(bp))")
                                                    .font(.system(size: 16, weight: .bold))
                                                Text(" mm Hg")
                                                    .font(.system(size: 14))
                                            }
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(paleGreenPill, in: Capsule())
                                        }
                                    }
                                    Spacer()
                                }
                                
                                if firstVitalReceivedTime != nil {
                                    ProgressView()
                                        .padding(.top, 16)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .padding(.horizontal, 24)
                            .transition(.slide)

                        } else if currentStage == .healthCard {
                            VStack(alignment: .center, spacing: 16) {
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

                                if !healthCardNumber.isEmpty {
                                    Label("Card detected: \(healthCardNumber)", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }

                                Button {
                                    withAnimation {
                                        currentStage = .symptoms
                                        stopOCRScanning()
                                    }
                                } label: {
                                    Text(healthCardNumber.isEmpty ? "I don't have my\nhealth card" : "Next")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 16)
                                        .frame(maxWidth: .infinity)
                                        .background(buttonDarkBlue, in: RoundedRectangle(cornerRadius: 16))
                                }
                                .padding(.horizontal, 24)
                            }
                            .transition(.slide)

                        } else if currentStage == .symptoms {
                            VStack(spacing: 24) {
                                // Text area with dictation inside
                                ZStack(alignment: .topTrailing) {
                                    ZStack(alignment: .topLeading) {
                                        if #available(iOS 16.0, *) {
                                            TextEditor(text: $symptoms)
                                                .font(.system(size: 18))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 16)
                                                .frame(height: 200)
                                                .scrollContentBackground(.hidden)
                                                .background(textFieldGray)
                                                .cornerRadius(16)
                                        } else {
                                            TextEditor(text: $symptoms)
                                                .font(.system(size: 18))
                                                .padding(12)
                                                .frame(height: 200)
                                                .background(textFieldGray)
                                                .cornerRadius(16)
                                        }
                                        
                                        if symptoms.isEmpty {
                                            Text("Type...")
                                                .font(.system(size: 18))
                                                .foregroundColor(Color(white: 0.6))
                                                .padding(.horizontal, 20)
                                                .padding(.vertical, 24)
                                                .allowsHitTesting(false)
                                        }
                                    }

                                    Button {
                                        isDictating ? stopDictation() : startDictation()
                                    } label: {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(isDictating ? .white : headerTextDarkBlue)
                                            .frame(width: 32, height: 32)
                                            .background(isDictating ? Color.red : dictationBg, in: Circle())
                                    }
                                    .padding(16)
                                    .accessibilityLabel(isDictating ? "Stop dictation" : "Start dictation")
                                }
                                .padding(.horizontal, 24)

                                if let errorMessage = errorMessage {
                                    Text(errorMessage)
                                        .foregroundColor(.red)
                                        .font(.footnote)
                                        .padding(.horizontal, 24)
                                }

                                VStack(spacing: 8) {
                                    Button {
                                        submitSymptoms()
                                    } label: {
                                        Text(isSubmitting ? "Submitting..." : "Submit")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 16)
                                            .background(buttonDarkBlue, in: Capsule())
                                    }
                                    .disabled(symptoms.isEmpty || isSubmitting)
                                    .padding(.horizontal, 24)

                                    Text("Please wait for further assistance\nfrom a healthcare professional")
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(white: 0.4))
                                }
                            }
                            .transition(.slide)
                        }
                    }
                }
                .padding(.bottom, 32)
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
            
            checkFaceScanProgress()
        }
    }
    
    // MARK: - Face Scan Progress Check
    
    private func checkFaceScanProgress() {
        guard currentStage == .faceScan else { return }
        
        // Ensure we actually have data before we start the clock
        if !hrBuffer.isEmpty || !rrBuffer.isEmpty || !bpBuffer.isEmpty {
            if firstVitalReceivedTime == nil {
                firstVitalReceivedTime = Date()
            } else if let startTime = firstVitalReceivedTime, Date().timeIntervalSince(startTime) >= 5.0 {
                withAnimation {
                    currentStage = .healthCard
                }
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
            
            checkFaceScanProgress()
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
        let finalCGImage: CGImage?
        
        if let cg = image.cgImage {
            finalCGImage = cg
        } else if let ci = image.ciImage {
            let context = CIContext()
            finalCGImage = context.createCGImage(ci, from: ci.extent)
        } else {
            UIGraphicsBeginImageContext(image.size)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let drawnImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            finalCGImage = drawnImage?.cgImage
        }
        
        guard let cgImage = finalCGImage else { return }

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
                withAnimation {
                    healthCardNumber = formatted
                }
                stopOCRScanning()
                
                // Auto-advance to next stage
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if self.currentStage == .healthCard {
                        withAnimation {
                            self.currentStage = .symptoms
                        }
                    }
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let orientation: CGImagePropertyOrientation = !Self.useMockVitals ? .upMirrored : .up
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
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
