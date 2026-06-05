import Foundation

/// Fuzzy free-text Guide search.
///
/// The query is split on whitespace into tokens; a channel matches only when
/// **every** token matches at least one of its fields (title or any resolved
/// tag name) — tokens may match different fields. Each token is scored against a
/// field with a three-tier hybrid, strongest first:
///
/// 1. **Contiguous substring** — the classic exact match (highest scoring).
/// 2. **Subsequence** — characters in order but not adjacent ("nrwy" → "Norway"),
///    scored by tightness (the minimal window that contains them).
/// 3. **Bounded typo** — Damerau-Levenshtein within a length-scaled budget, for
///    transpositions/substitutions that break subsequence order ("norwya").
///
/// `score` returns `nil` when any token fails to match anywhere (the AND gate),
/// otherwise the summed per-token best score. Higher is better; callers rank by
/// it while a query is active. Because results are ranked, the subsequence tier
/// can be permissive — weak matches sink to the bottom rather than masquerading
/// as good ones.
enum ChannelSearch {
    /// Relevance weight applied to a token's score per field. Matches in
    /// higher-signal fields rank above the same match in noisier ones. A field's
    /// weight scales its tier score but not the match/no-match decision, so a
    /// token found only in a low-weight field still keeps the channel in results
    /// (it just ranks lower). Add new fields here as the model grows — e.g. a
    /// future video `description` would slot in around `0.35`.
    private enum FieldWeight {
        static let title = 1.0
        static let tag = 0.9
    }

    /// A channel's searchable fields paired with their relevance weights.
    private static func weightedFields(_ channel: Channel, tagsByID: [String: Tag]) -> [(text: [Character], weight: Double)] {
        var fields: [(text: [Character], weight: Double)] = [(fold(channel.title), FieldWeight.title)]
        for tagID in channel.tagIDs {
            if let name = tagsByID[tagID]?.name {
                fields.append((fold(name), FieldWeight.tag))
            }
        }
        return fields
    }

    /// Aggregate fuzzy score for `channel` against `query`, or `nil` if it does
    /// not match every token. An empty/whitespace query scores `0` (matches all).
    static func score(_ channel: Channel, query: String, tagsByID: [String: Tag]) -> Double? {
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }
        guard !tokens.isEmpty else { return 0 }

        let fields = weightedFields(channel, tagsByID: tagsByID)

        var total = 0.0
        for token in tokens {
            var best: Double? = nil
            for field in fields {
                if let s = tokenScore(token, field.text) {
                    let weighted = s * field.weight
                    best = max(best ?? weighted, weighted)
                }
            }
            guard let b = best else { return nil }   // token matched no field → reject
            total += b
        }
        return total
    }

    // MARK: - Token scoring

    /// Best score of `token` against one `field`, or `nil` if no tier matches.
    private static func tokenScore(_ token: [Character], _ field: [Character]) -> Double? {
        if token.isEmpty { return 1.0 }
        if let s = contiguousScore(token, field) { return s }
        if let s = subsequenceScore(token, field) { return s }
        return typoScore(token, field)
    }

    /// Tier 1 — exact contiguous occurrence. Band ~[1.0, 1.5]: a bonus when the
    /// match starts on a word boundary and when it spans the whole field.
    private static func contiguousScore(_ t: [Character], _ f: [Character]) -> Double? {
        guard !t.isEmpty, t.count <= f.count else { return nil }
        var best: Double? = nil
        for start in 0...(f.count - t.count) {
            var matched = true
            for k in 0..<t.count where f[start + k] != t[k] { matched = false; break }
            guard matched else { continue }
            var s = 1.0
            if isWordBoundary(f, start) { s += 0.25 }
            if t.count == f.count { s += 0.25 }
            best = max(best ?? s, s)
        }
        return best
    }

    /// Tier 2 — characters in order but not adjacent. Scored by tightness
    /// (`token.count / minimal-window-length`) so "nrwy" in "norway" beats a
    /// scattered match like "rain" in "relaxing and intense". Band ~(0, 0.75].
    private static func subsequenceScore(_ t: [Character], _ f: [Character]) -> Double? {
        guard let window = minWindowSubsequence(t, f) else { return nil }
        let tightness = Double(t.count) / Double(window.length)
        var s = 0.6 * tightness
        if isWordBoundary(f, window.start) { s += 0.15 }
        return s
    }

    /// Tier 3 — bounded Damerau-Levenshtein over windows of `f`, for typos that
    /// break ordering. Budget scales with token length; very short tokens get no
    /// typo tolerance (avoids noise). Band ~(0, 0.45].
    private static func typoScore(_ t: [Character], _ f: [Character]) -> Double? {
        let n = t.count
        let budget = n <= 3 ? 0 : (n <= 6 ? 1 : 2)
        guard budget > 0, !f.isEmpty else { return nil }

        let lo = max(1, n - budget)
        let hi = n + budget
        var bestDist = budget + 1
        var start = 0
        while start < f.count {
            let maxLen = min(hi, f.count - start)
            if maxLen >= lo {
                for len in lo...maxLen {
                    let window = Array(f[start..<(start + len)])
                    let d = damerauLevenshtein(t, window, max: budget)
                    if d < bestDist { bestDist = d }
                    if bestDist == 0 { break }
                }
            }
            if bestDist == 0 { break }
            start += 1
        }
        guard bestDist <= budget else { return nil }
        let quality = 1.0 - Double(bestDist) / Double(budget + 1)
        return 0.45 * quality
    }

    // MARK: - Primitives

    private static func fold(_ s: String) -> [Character] {
        Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    private static func isWordBoundary(_ f: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        let prev = f[i - 1]
        return !(prev.isLetter || prev.isNumber)
    }

    /// Smallest `(length, start)` window of `f` that contains `t` as a
    /// subsequence, or `nil` if `t` is not a subsequence of `f`. For each start
    /// where `f` begins matching `t[0]`, it greedily completes to the earliest
    /// end (the tightest window for that start); the global minimum wins.
    private static func minWindowSubsequence(_ t: [Character], _ f: [Character]) -> (length: Int, start: Int)? {
        let n = t.count, m = f.count
        guard n > 0, n <= m else { return nil }
        var best: (length: Int, start: Int)? = nil
        var i = 0
        while i <= m - n {
            guard f[i] == t[0] else { i += 1; continue }
            var ti = 0, fi = i
            while fi < m {
                if f[fi] == t[ti] {
                    ti += 1
                    if ti == n { break }
                }
                fi += 1
            }
            if ti == n {
                let length = fi - i + 1
                if best == nil || length < best!.length { best = (length, i) }
                i += 1
            } else {
                // Could not complete from here, so no later start can either.
                break
            }
        }
        return best
    }

    /// Optimal-string-alignment (Damerau-Levenshtein with adjacent transpositions)
    /// distance, short-circuiting to `max + 1` once every cell in a row exceeds
    /// `max`.
    private static func damerauLevenshtein(_ a: [Character], _ b: [Character], max maxDist: Int) -> Int {
        let n = a.count, m = b.count
        if abs(n - m) > maxDist { return maxDist + 1 }
        if n == 0 { return m }
        if m == 0 { return n }

        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var curr = [Int](repeating: 0, count: m + 1)

        for i in 1...n {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, prev2[j - 2] + 1)
                }
                curr[j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > maxDist { return maxDist + 1 }
            swap(&prev2, &prev)
            swap(&prev, &curr)
        }
        return prev[m]
    }
}
