import SwiftUI

/// 根容器：主界面 = 设置页（含「语音输入」入口）。键盘的麦克风通过 openless://dictate 跳到这里发起语音。
struct RootView: View {
    @State private var showDictation = false

    var body: some View {
        NavigationStack {
            SettingsView(onDictate: { showDictation = true })
        }
        .fullScreenCover(isPresented: $showDictation) {
            DictationView()
        }
        .onOpenURL { url in
            switch url.host {
            case "dictate": showDictation = true
            default: break  // settings：本就是主界面
            }
        }
    }
}

#Preview {
    RootView()
}
