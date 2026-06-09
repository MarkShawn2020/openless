import SwiftUI
import OpenLessShared

/// Flow 式语音输入界面：大麦克风按钮（轻点开始 / 再次点击完成）、录音波形、实时转写、插入。
/// 「插入」把文本写入 App Group（键盘切回后自动插入）+ 复制到剪贴板兜底，并给出明确确认。
struct DictationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dictator = SpeechDictator()
    @State private var inserted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if inserted {
                confirmation
            } else {
                transcriptArea
                Spacer(minLength: 0)
                controls
            }
        }
        .background(Color(.systemBackground))
        .onAppear { dictator.requestAuthorization() }
        .onDisappear { dictator.stop() }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("语音输入").font(.headline)
            Spacer()
            Color.clear.frame(width: 22, height: 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var transcriptArea: some View {
        ScrollView {
            Text(dictator.transcript.isEmpty ? "开口说话，文字会实时出现在这里…" : dictator.transcript)
                .font(.system(size: 22))
                .foregroundStyle(dictator.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if let e = dictator.error {
                Text(e).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20)
            }
            micButton
            Text(dictator.phase == .recording ? "再次点击以完成" : "轻点一下开始说话")
                .font(.subheadline).foregroundStyle(.secondary)
            if !dictator.engineLabel.isEmpty {
                Text("识别引擎：\(dictator.engineLabel)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if dictator.phase == .finished && !dictator.transcript.isEmpty {
                HStack(spacing: 12) {
                    Button("重录") { dictator.reset() }.buttonStyle(.bordered)
                    Button("插入到输入框") { insert() }.buttonStyle(.borderedProminent)
                }
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 28)
        .padding(.top, 8)
    }

    private var micButton: some View {
        Button(action: dictator.toggle) {
            ZStack {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 220, height: 66)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                if dictator.phase == .recording {
                    WaveBars(level: dictator.level).frame(width: 130, height: 34)
                } else {
                    Label("语音输入", systemImage: "mic.fill").font(.headline).foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var confirmation: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("已识别").font(.title2.bold())
            Text(dictator.transcript)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Text("切回刚才的 App，文字会自动插入到光标处\n（也已复制到剪贴板）")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 28)
            Spacer()
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func insert() {
        let text = dictator.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { dismiss(); return }
        Handoff.setPendingInsert(text)
        UIPasteboard.general.string = text
        withAnimation { inserted = true }
    }
}

/// 录音时的白色波形条，随音量 `level` 起伏。
struct WaveBars: View {
    var level: CGFloat
    private let pattern: [CGFloat] = [0.35, 0.6, 0.9, 1.0, 0.9, 0.6, 0.35]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(pattern.indices, id: \.self) { i in
                Capsule().fill(Color.white).frame(width: 6, height: barHeight(pattern[i]))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func barHeight(_ p: CGFloat) -> CGFloat {
        8 + 26 * p * (0.25 + 0.75 * level)
    }
}
