import Foundation

/// Offline review of actual fictional demo output; no scripts, remote assets or audio.
enum PracticeDemoReview {
    static func render(_ data: Data) throws -> String {
        guard let session = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let turns = session["turns"] as? [[String: Any]], turns.count >= 8 else {
            throw NSError(domain: "PracticeDemoReview", code: 1, userInfo: [NSLocalizedDescriptionKey: "The engine has not saved all eight demo turns yet. Wait a moment and try again."])
        }
        func escape(_ value: Any?) -> String {
            String(describing: value ?? "").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
        }
        let conversation = turns.map { turn in
            let speaker = turn["me"] as? Bool == true ? "SE" : "Customer"
            let question = (turn["coachQ"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return "<article><strong>" + speaker + "</strong><p>" + escape(turn["text"]) + "</p>" + (question.map { "<aside>Suggested follow-up: " + escape($0) + "</aside>" } ?? "") + "</article>"
        }.joined()
        let notes = (session["notes"] as? [[String: Any]] ?? []).map { "<li>" + escape($0["quote"]) + (( $0["tentative"] as? Bool == true) ? " <em>— uncertain</em>" : "") + "</li>" }.joined()
        let coverage = (session["coverageDetails"] as? [[String: Any]] ?? []).map { "<article><strong>" + escape($0["name"]) + " · " + escape($0["status"]) + "</strong><p>" + escape($0["quote"]) + "</p><small>" + escape($0["remaining"]) + "</small></article>" }.joined()
        var answerHTML = "<p>No answer was saved in this snapshot. This review does not perform searches.</p>"
        if let answer = session["liveAnswer"] as? [String: Any] {
            let sources = (answer["sources"] as? [String] ?? []).compactMap { source -> String? in
                guard let url = URL(string: source), url.scheme == "https", url.host != nil else { return nil }
                return "<li><a rel=\"noreferrer\" href=\"" + escape(source) + "\">" + escape(source) + "</a></li>"
            }.joined()
            answerHTML = "<h3>" + escape(answer["q"]) + "</h3><p>" + escape(answer["answer"]) + "</p><ul>" + sources + "</ul><small>Saved suggestion; not proof it was delivered on the call. Opening a source requires internet access.</small>"
        }
        return """
        <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>SalesPilot · Demo review</title><style>body{font:17px/1.6 system-ui;margin:40px auto;padding:0 24px;max-width:980px;color:#203044;background:#f6f8fc}h1,h2{color:#163754}article{background:white;border:1px solid #dde4ef;border-radius:12px;padding:20px;margin:16px 0}aside{border-left:4px solid #087b87;padding:12px;background:#eef8f8}p,li{white-space:pre-wrap;overflow-wrap:anywhere}a{color:#176599;overflow-wrap:anywhere}small,em{color:#526176}@media print{body{background:white;margin:0;max-width:none}article{break-inside:avoid}}</style><h1>SalesPilot</h1><p><strong>Saved demonstration · \(turns.count) turns</strong></p><p>This is an offline review of actual prepared-demo output. Customer voices were generated and transcribed locally. It is not a live call, video recording, human microphone test or meeting-capture acceptance.</p><h2>Discovery conversation</h2>\(conversation)<h2>Captured notes</h2><ul>\(notes)</ul><h2>Methodology evidence</h2>\(coverage)<h2>Saved product answer</h2>\(answerHTML)</html>
        """
    }
}
