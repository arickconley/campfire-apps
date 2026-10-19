import SwiftUI

struct AppearanceSettings: View {
    @Bindable private var appearance = AppAppearance.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearance.mode) {
                    ForEach(AppAppearance.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Palette", selection: $appearance.theme) {
                    ForEach(AppAppearance.Theme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                LabeledContent("Accent color") {
                    HStack(spacing: 6) {
                        ForEach(AppAppearance.Accent.allCases, id: \.self) { accent in
                            Button {
                                appearance.accent = accent
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(light: accent.colors.0, dark: accent.colors.1))
                                        .frame(width: 20, height: 20)
                                        .padding(4)
                                        .overlay {
                                            Circle().strokeBorder(appearance.accent == accent ? Ink.ink : .clear, lineWidth: 2)
                                        }
                                    Text(accent.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(Ink.ink)
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.rawValue)
                            .accessibilityValue(appearance.accent == accent ? "Selected" : "")
                            .accessibilityAddTraits(appearance.accent == accent ? .isSelected : [])
                        }
                    }
                }
                Text("Choose System to follow your device’s light or dark appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Writing") {
                Picker("Editor font", selection: $appearance.typeface) {
                    ForEach(AppAppearance.Typeface.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("Text size")
                    Slider(value: $appearance.fontSize, in: 16...28, step: 1)
                        .accessibilityLabel("Editor text size")
                        .accessibilityValue("\(Int(appearance.fontSize)) points")
                    Text("\(Int(appearance.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("A little space to think", systemImage: "flame")
                        .font(.system(size: 24, weight: .semibold, design: appearance.typeface.design))
                        .foregroundStyle(Ink.ink)
                    Text("Collect a thought. Give it a little warmth. Make it your own.")
                        .font(.system(size: appearance.fontSize, design: appearance.typeface.design))
                        .foregroundStyle(Ink.ink)
                    Text("DRAFT · JUST FOR YOU")
                        .font(.caption.monospaced())
                        .foregroundStyle(Ink.ember)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.paper, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.rule))
                Text("Appearance changes stay on this device. Your published posts keep their blog’s styling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Preview")
            }
            Button("Restore Appearance Defaults") { appearance.reset() }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
