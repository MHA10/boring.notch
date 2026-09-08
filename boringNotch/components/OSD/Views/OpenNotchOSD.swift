//
//  OpenNotchOSD.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-23.
//

import SwiftUI
import Defaults

struct OpenNotchOSD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var accent: Color?
    @Default(.showOpenNotchOSDPercentage) var showPercentage
    @Default(.notchGlassStrength) var glassStrength
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            OSDIconView(eventType: type, icon: icon, value: value, accent: accent)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 20, alignment: .center)
            
            // Slider or Status Text
            if type != .mic {
                 DraggableProgressBar(value: $value, onChange: { newVal in
                     updateSystemValue(newVal)
                 }, accentColor: accent, compact: true)
                    .frame(maxWidth: .infinity)
            } else {
                Text(value > 0 ? "Unmuted" : "Muted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            
            // Percentage Text
            if type != .mic && showPercentage {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Liquid Glass on macOS 26+ (Tahoe); falls back to the solid black
        // capsule on macOS 14–15 where .glassEffect() doesn't exist yet.
        .osdGlassCapsule(strength: glassStrength)
    }
    
    func updateSystemValue(_ newVal: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newVal))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newVal))
        default:
            break
        }
    }
}

/// Applies the notch OSD's background: Apple's Liquid Glass material on
/// macOS 26+, or the original solid black capsule on earlier systems.
/// Wrapped in `#available` so the app still compiles for its macOS 14 target.
private extension View {
    @ViewBuilder
    func osdGlassCapsule(strength: Double) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(.black.opacity(strength)), in: Capsule())
        } else {
            self.background(
                Capsule()
                    .fill(Color.black)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

#Preview {
    OpenNotchOSD(type: .constant(.volume), value: .constant(0.5), icon: .constant(""), accent: .constant(nil))
        .environmentObject(BoringViewModel())
        .padding()
        .background(Color.gray)
}
