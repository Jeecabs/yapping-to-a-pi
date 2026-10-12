/// A short line the floating bar shows after a dictation: where the text landed, or why it didn't.
struct BarNotice: Equatable {
    enum Kind: Equatable { case landed, problem }
    let text: String
    let kind: Kind

    var duration: Duration { kind == .landed ? .seconds(1.6) : .seconds(5) }
}
