import SwiftUI

/// Arena-only components. Duty screens and required system sheets stay unchanged.
enum ArenaMenuTheme {
    static let canvas = Color(red: 0.08, green: 0.06, blue: 0.16)
    static let panel = Color(red: 0.16, green: 0.12, blue: 0.26)
    static let accent = Color(red: 0.75, green: 0.57, blue: 0.94)
}

struct ArenaMenuScreen<Content: View>: View {
    let title: String
    let onClose: () -> Void
    var scrollContent = true
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            ArenaMenuTheme.canvas.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    ArenaInterfaceIcon(title.contains("设置") ? .settings : .home)
                        .frame(width: 23, height: 23).foregroundStyle(ArenaMenuTheme.accent)
                    Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
                    Spacer()
                    Button { ArenaSound.shared.menu(.uiBack); onClose() } label: {
                        ArenaVendorIcon(name: "cross").frame(width: 20, height: 20).frame(width: 44, height: 44)
                    }
                        .buttonStyle(ArenaMenuButtonStyle()).accessibilityLabel("关闭\(title)")
                }
                if scrollContent {
                    ScrollView { content.frame(maxWidth: 720).frame(maxWidth: .infinity) }
                } else {
                    content.frame(maxWidth: 720).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.padding(16)
        }
        .foregroundStyle(.white)
        .modifier(ArenaLandscape())
        .statusBarHidden()
    }
}

struct ArenaMenuCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(ArenaMenuTheme.panel)
                    ArenaInterfaceTexture(role: .panel, cap: 12)
                        .colorMultiply(ArenaMenuTheme.panel)
                }
            }
    }
}

struct ArenaMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .background {
                ArenaVendorButtonFace(pressed: configuration.isPressed)
                    .shadow(color: Color(red: 0.06, green: 0.04, blue: 0.12), radius: 0, y: configuration.isPressed ? 1 : 4)
            }
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color(red: 0.49, green: 0.38, blue: 0.66), lineWidth: 2))
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { ArenaSound.shared.menu(.uiClick) }
            }
    }
}

struct ArenaMenuToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle(); ArenaSound.shared.menu(.uiToggle) } label: {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    Text(isOn ? "开" : "关").font(.caption.bold())
                    ArenaInterfaceTexture(role: isOn ? .checkOn : .checkOff, cap: 0)
                        .frame(width: 28, height: 28)
                }.frame(minWidth: 54)
            }.frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityValue(isOn ? "开启" : "关闭")
    }
}

struct ArenaMenuSlider: View {
    let title: String
    @Binding var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text("\(Int(value * 100))%").monospacedDigit() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    ArenaInterfaceTexture(role: .sliderTrack, cap: 10).frame(height: 10)
                    ArenaInterfaceTexture(role: .sliderFill, cap: 10)
                        .frame(width: max(0, geo.size.width * value), height: 10)
                    ArenaInterfaceTexture(role: .sliderThumb, cap: 0).frame(width: 20, height: 27)
                        .offset(x: max(0, (geo.size.width - 20) * value))
                }.frame(height: 44).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        value = min(max(event.location.x / max(geo.size.width, 1), 0), 1)
                    })
            }.frame(height: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.05, 1)
            case .decrement: value = max(value - 0.05, 0)
            @unknown default: break
            }
        }
    }
}

struct ArenaAudioSettingsView: View {
    @AppStorage(ArenaSound.themeKey) private var themeAudio = true
    @AppStorage(ArenaSound.musicVolumeKey) private var music = UserDefaults.standard.object(forKey: ArenaSound.volumeKey) as? Double ?? 0.7
    @AppStorage(ArenaSound.effectsVolumeKey) private var effects = UserDefaults.standard.object(forKey: ArenaSound.volumeKey) as? Double ?? 0.7
    @AppStorage(ArenaSound.musicMuteKey) private var musicMuted = false
    @AppStorage(ArenaSound.effectsMuteKey) private var effectsMuted = false
    var body: some View {
        ArenaMenuCard {
            HStack(spacing: 8) {
                ArenaInterfaceIcon(effectsMuted ? .soundOff : .soundOn).frame(width: 24, height: 24)
                Text("声音").font(.title3.bold())
                Spacer()
                ArenaInterfaceIcon(musicMuted ? .musicOff : .musicOn).frame(width: 24, height: 24)
            }
            ArenaMenuToggle(title: "原创主题音乐", isOn: $themeAudio)
            Text("默认使用完整原创配乐，覆盖大厅、战斗和胜负结算；关闭后使用原有配乐与结算短音。")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            ArenaMenuToggle(title: "音乐静音", isOn: $musicMuted)
            ArenaMenuSlider(title: "音乐音量", value: $music)
            ArenaMenuToggle(title: "音效静音", isOn: $effectsMuted)
            ArenaMenuSlider(title: "音效音量", value: $effects)
            Button { ArenaSound.shared.resumeAudio() } label: {
                Label("恢复中断后的声音", systemImage: "play.circle").padding(12).frame(minHeight: 44)
            }.buttonStyle(ArenaMenuButtonStyle())
            HStack(alignment: .top, spacing: 8) {
                ArenaInterfaceIcon(.information).frame(width: 16, height: 16)
                Text("总静音仍由大厅扬声器按钮控制。耳机拔出后不会自动改用扬声器；确认后可在这里恢复。其他 App 播放音乐时，本游戏背景音乐让出。")
                    .fixedSize(horizontal: false, vertical: true)
            }.font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .onChange(of: themeAudio) { _ in ArenaSound.shared.themeChanged() }
        .onChange(of: music) { _ in ArenaSound.shared.volumeChanged() }
        .onChange(of: effects) { _ in ArenaSound.shared.volumeChanged() }
        .onChange(of: musicMuted) { _ in ArenaSound.shared.volumeChanged() }
        .onChange(of: effectsMuted) { _ in ArenaSound.shared.volumeChanged() }
    }
}
