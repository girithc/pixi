//
//  SettingsView.swift
//  pixi
//
//  Created by Girith Choudhary on 6/22/26.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var permissions = Permissions()
    @ObservedObject private var settings = AppSettings.shared

    // API keys — loaded from / saved to Keychain.
    @State private var fireworksKey = ""
    @State private var openaiKey = ""

    private let ttsOptions = ["Disabled"]
    private let sttOptions = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
    private let visionLlmOptions = FireworksModels.visionOptions
    private let llmOptions = FireworksModels.reasoningOptions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Permissions") {
                    permissionRow("Screen Capture",
                                  "Allow Pixi to capture the screen.",
                                  isOn: permissions.screenCapture,
                                  onEnable: permissions.requestScreenCapture)
                    permissionRow("Computer Use",
                                  "Allow Pixi to take actions on the screen.",
                                  isOn: permissions.computerUse,
                                  onEnable: permissions.requestComputerUse)
                    permissionRow("Listen",
                                  "Allow Pixi to listen to your voice.",
                                  isOn: permissions.listening,
                                  onEnable: permissions.requestListening)
                }

                section("Model") {
                    pickerRow("TTS", "Text-to-speech output.",
                              selection: .constant("Disabled"), options: ttsOptions, disabled: true)
                    pickerRow("STT", "Speech-to-text input.",
                              selection: $settings.stt, options: sttOptions)
                    pickerRow("Vision LLM", "Vision model.",
                              selection: $settings.visionLlm, options: visionLlmOptions)
                    pickerRow("Reasoning LLM", "Reasoning model.",
                              selection: $settings.llm, options: llmOptions)
                }

                section("API Keys") {
                    secretRow("Fireworks AI",
                              "Used for Vision + Reasoning LLMs.",
                              placeholder: "fw_…",
                              text: $fireworksKey,
                              account: KeychainStore.Account.fireworks)
                    secretRow("OpenAI",
                              "Used for STT (gpt-4o-transcribe).",
                              placeholder: "sk-…",
                              text: $openaiKey,
                              account: KeychainStore.Account.openai)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.clear)
        .onAppear {
            permissions.start()
            fireworksKey = KeychainStore.get(KeychainStore.Account.fireworks) ?? ""
            openaiKey = KeychainStore.get(KeychainStore.Account.openai) ?? ""
        }
        .onDisappear { permissions.stop() }
    }

    /// Reusable grouped section: header + rows, open concept (no card/list).
    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(_ title: String, _ subtitle: String,
                               isOn: Bool, onEnable: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in if on { onEnable() } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func pickerRow(_ title: String, _ subtitle: String,
                           selection: Binding<String>, options: [String],
                           disabled: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.large)
            .labelsHidden()
            .fixedSize()
            .disabled(disabled)
        }
        .padding(.vertical, 4)
        .opacity(disabled ? 0.5 : 1)
    }

    private func secretRow(_ title: String, _ subtitle: String,
                           placeholder: String, text: Binding<String>,
                           account: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(maxWidth: 260)
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.isEmpty {
                        KeychainStore.clear(account)
                    } else {
                        KeychainStore.set(newValue, for: account)
                    }
                }
        }
        .padding(.vertical, 4)
    }
}
