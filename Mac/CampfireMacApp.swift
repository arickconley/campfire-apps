import SwiftUI

@main
struct CampfireMacApp: App {
    @State private var store = PostsStore()
    @State private var bridge = EditorBridge()

    var body: some Scene {
        Window("Campfire", id: "editor") {
            MacRootView()
                .environment(store)
                .environment(bridge)
                .frame(minWidth: 780, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .commands {
            FormatCommands(bridge: bridge)
        }

        Settings {
            MacSettingsView()
                .environment(store)
                .environment(bridge)
        }
    }
}

private struct FormatCommands: Commands {
    var bridge: EditorBridge

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Post") { bridge.requestNew += 1 }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(bridge.busy)
        }
        CommandMenu("Format") {
            Group {
                Button("Bold") { bridge.session?.toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { bridge.session?.toggleItalic() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Strikethrough") { bridge.session?.toggleStrike() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Divider()
                Button("Body") { bridge.session?.applyBlock(nil) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Button("Heading") { bridge.session?.applyBlock("h1") }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Subheading") { bridge.session?.applyBlock("h2") }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Small Heading") { bridge.session?.applyBlock("h3") }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Quote") { bridge.session?.applyBlock("quote") }
                Button("Code") { bridge.session?.applyBlock("code") }
                Divider()
                Button("Bullet List") { bridge.session?.toggleBullet() }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { bridge.session?.toggleNumber() }
                    .keyboardShortcut("7", modifiers: [.command, .shift])
                Divider()
                Button("Link…") { bridge.session?.beginLink() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Image…") { bridge.session?.beginImage() }
                Button("Divider") { bridge.session?.applyBlock("hr") }
            }
            .disabled(bridge.busy || !bridge.canSave)
        }
    }
}
