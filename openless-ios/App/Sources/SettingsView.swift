import SwiftUI
import OpenLessShared

/// 主界面 = 设置页（无营销文案，直接给可编辑配置）。Key 写入 Keychain，顶部「保存」回报结果。
struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var flash: String?
    var onDictate: () -> Void = {}

    private let asrProviders = ["volcengine", "bailian", "whisper"]
    private let llmProviders = ["openai", "ark", "gemini"]

    var body: some View {
        Form {
            Section {
                Button(action: onDictate) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("语音输入").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                Button(action: openSystemKeyboardSettings) {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("启用 OpenLess 键盘")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
            }

            Section("润色") {
                Picker("默认模式", selection: model.pref(\.defaultMode)) {
                    ForEach(PolishMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section("语音识别 (ASR)") {
                Picker("服务", selection: model.pref(\.activeAsrProvider)) {
                    ForEach(asrProviders, id: \.self) { Text(asrName($0)).tag($0) }
                }
                asrFields
            }

            Section("大模型润色 (LLM)") {
                Picker("服务", selection: model.pref(\.activeLlmProvider)) {
                    ForEach(llmProviders, id: \.self) { Text(llmName($0)).tag($0) }
                }
                llmFields
            }

            Section("语音保持") {
                Picker("免跳转保持", selection: model.pref(\.voiceHoldMinutes)) {
                    Text("每次跳转").tag(0)
                    Text("5 分钟").tag(5)
                    Text("30 分钟").tag(30)
                    Text("一直保持").tag(-1)
                }
            }
        }
        .navigationTitle("OpenLess")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: saveNow).bold()
            }
        }
        .overlay(alignment: .top) { flashBanner }
    }

    @ViewBuilder private var asrFields: some View {
        switch model.prefs.activeAsrProvider {
        case "volcengine":
            field("App Key", model.asr(\.appKey))
            secure("Access Token", model.asr(\.accessKey))
            field("Resource ID", model.asr(\.resourceId))
        case "bailian":
            secure("API Key", model.asr(\.apiKey))
            field("词汇表 ID", model.asr(\.vocabularyId))
        default:
            secure("API Key", model.asr(\.apiKey))
            field("Base URL", model.asr(\.baseURL))
            field("模型", model.asr(\.model))
        }
    }

    @ViewBuilder private var llmFields: some View {
        secure("API Key", model.llm(\.apiKey))
        field("Base URL", model.llm(\.baseURL))
        field("模型", model.llm(\.model))
    }

    // MARK: - 行控件

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("未设置", text: binding)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.secondary)
        }
    }

    private func secure(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            SecureField("未设置", text: binding).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var flashBanner: some View {
        if let flash {
            Text(flash)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - 动作

    private func saveNow() {
        do {
            try model.save()
            showFlash("已保存")
        } catch {
            showFlash("保存失败")
        }
    }

    private func showFlash(_ text: String) {
        withAnimation { flash = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { flash = nil }
        }
    }

    private func openSystemKeyboardSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func asrName(_ id: String) -> String {
        ["volcengine": "火山引擎", "bailian": "阿里百炼", "whisper": "Whisper / OpenAI 兼容"][id] ?? id
    }

    private func llmName(_ id: String) -> String {
        ["openai": "OpenAI 兼容", "ark": "火山方舟", "gemini": "Gemini"][id] ?? id
    }
}
