import SwiftUI
import SmartSpectraSwiftSDK
internal import AVFoundation

struct TriageAppClipExperience: ClipExperience {
    static let urlPattern = "example.com/triage"
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

    // Rolling 5-second vitals buffers: (timestamp, value)
    @State private var hrBuffer: [(Date, Float)] = []
    @State private var rrBuffer: [(Date, Float)] = []
    @State private var bpBuffer: [(Date, Float)] = []
    private let bufferWindow: TimeInterval = 5.0

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
                        if let cameraImage = vitalsProcessor.imageOutput {
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
                            
                            TextField("Describe how you feel...", text: $symptoms)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(isSubmitting)
                                
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
            SmartSpectraSwiftSDK.shared.setApiKey("ShdNWcKc0D5alluayVgzv75yQxjWfOg3953qUs4M")

            sdk.setSmartSpectraMode(.continuous)
            sdk.setMeasurementDuration(30.0)
            sdk.setCameraPosition(.front)

            vitalsProcessor.startProcessing()
            vitalsProcessor.startRecording()
        }
        .onDisappear {
            vitalsProcessor.stopRecording()
            vitalsProcessor.stopProcessing()
        }
        .onChange(of: sdk.metricsBuffer) { metrics in
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
        
        // Include seat number and symptoms
        var payload: [String: Any] = [
            "symptoms": symptoms,
            "seatNumber": "Unknown"
        ]

        if let hr = median(of: hrBuffer) { payload["heartRate"] = Int(hr) }
        if let rr = median(of: rrBuffer) { payload["respiratoryRate"] = Int(rr) }
        if let bp = median(of: bpBuffer) { payload["bloodPressure"] = Int(bp) }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
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
}
