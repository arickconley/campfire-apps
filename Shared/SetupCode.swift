import Foundation

struct SetupCode {
    var url: String
    var token: String
}

func parseSetupCode(_ raw: String) -> SetupCode? {
    struct Card: Decodable {
        var url: String
        var token: String
    }
    guard let data = raw.data(using: .utf8),
          let card = try? JSONDecoder().decode(Card.self, from: data) else {
        return nil
    }
    let url = card.url.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = card.token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !url.isEmpty, !token.isEmpty else { return nil }
    return SetupCode(url: url, token: token)
}
