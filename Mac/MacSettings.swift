import SwiftUI

struct MacSettingsView: View {
    var body: some View {
        TabView {
            MacBlogsView()
                .tabItem { Label("Blogs", systemImage: "server.rack") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .padding(16)
        .frame(width: 640, height: 580)
        .background(Ink.paper)
        .containerBackground(Ink.paper, for: .window)
        .modifier(AppearanceStyle())
    }
}
