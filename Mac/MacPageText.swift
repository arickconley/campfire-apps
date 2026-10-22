import SwiftUI

struct MacPageText: View {
    var session: MacEditorSession

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Menu("Format") {
                    Button("Bold") { session.toggleBold() }
                    Button("Italic") { session.toggleItalic() }
                    Button("Strikethrough") { session.toggleStrike() }
                    Divider()
                    Button("Body") { session.applyBlock(nil) }
                    Button("Heading") { session.applyBlock("h1") }
                    Button("Subheading") { session.applyBlock("h2") }
                    Button("Small Heading") { session.applyBlock("h3") }
                    Button("Quote") { session.applyBlock("quote") }
                    Button("Code") { session.applyBlock("code") }
                    Divider()
                    Button("Bullet List") { session.toggleBullet() }
                    Button("Numbered List") { session.toggleNumber() }
                }
                Menu("Insert") {
                    Button("Link…") { session.beginLink() }
                    Button("Image…") { session.beginImage() }
                    Button("Divider") { session.applyBlock("hr") }
                }
                Spacer()
            }
            MacText(session: session, revision: session.revision, appearanceRevision: AppAppearance.shared.revision)
                .accessibilityLabel("Page body")
        }
        .sheet(item: Binding(get: { session.prompt }, set: { session.prompt = $0 })) { insert in
            MacInsertSheet(insert: insert) { address, extra in
                if insert.kind == .link {
                    session.commitLink(insert, url: address, label: extra)
                } else {
                    session.commitImage(insert, url: address, caption: extra)
                }
            }
        }
    }
}
