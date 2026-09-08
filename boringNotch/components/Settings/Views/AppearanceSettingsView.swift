//
//  AppearanceSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.sliderColor) var sliderColor
    @Default(.notchGlassStrength) var glassStrength

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

    private var realtimeAudioWaveformSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
            }

            if #available(macOS 26.0, *) {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Glass strength")
                            Spacer()
                            Text(glassStrength, format: .percent.precision(.fractionLength(0)))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $glassStrength, in: 0...1)
                    }
                } header: {
                    Text("Liquid Glass")
                } footer: {
                    Text("How much the notch's glass is tinted. Lower = more see-through (wallpaper shows through); higher = more solid black. Open the notch to preview live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults.Toggle(key: .realtimeAudioWaveform) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real-time audio waveform")
                        Group {
                            if realtimeAudioWaveformSupported {
                                Text("Uses Accelerate FFT on the playing app's audio. Requires audio capture permission and uses slightly more CPU.")
                            } else {
                                Text("Requires macOS 14.2 or later. Update macOS to enable real-time audio waveform.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .disabled(!realtimeAudioWaveformSupported)
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Player tinting")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
            } header: {
                Text("Media")
            }
            Section {
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
                Defaults.Toggle(key: .enableClipboardHistory) {
                    Text("Clipboard history")
                }
            } header: {
                HStack {
                    Text("Additional features")
                }
            } footer: {
                Text("Keeps your last 30 copied text snippets in a notch tab. Items a password manager marks secret are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }
}
