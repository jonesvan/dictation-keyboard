import SwiftUI
import UIKit

struct SetupView: View {
    @AppStorage("onDeviceOnly") private var onDeviceOnly = false
    @State private var permissionGranted = DictationEngine.hasAuthorization

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    HStack {
                        Text("Microphone & Speech Recognition")
                        Spacer()
                        Image(systemName: permissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(permissionGranted ? .green : .red)
                    }
                    Button("Request Access") {
                        DictationEngine.requestAuthorization { granted in
                            permissionGranted = granted
                        }
                    }
                }

                Section("Enable the Keyboard") {
                    Label("Settings → General → Keyboard → Keyboards → Add New Keyboard → koyō", systemImage: "1.circle")
                    Label("Tap koyō and enable Allow Full Access", systemImage: "2.circle")
                    Label("In any text field, switch keyboards with the globe key", systemImage: "3.circle")
                }

                Section("Recognition") {
                    Toggle("On-device only", isOn: $onDeviceOnly)
                    Text(onDeviceOnly
                         ? "Transcription stays on the device. Requires the on-device speech model to be downloaded."
                         : "Uses Apple's higher-quality speech service. Audio leaves the device for transcription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Open Keyboard Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
            .navigationTitle("koyō")
        }
    }
}
