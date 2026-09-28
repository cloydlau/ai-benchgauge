import Testing

/// Keeps guard/catch failures at their call site while recording a real test issue.
func recordFailure(_ message: String = "Unexpected result", sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}
