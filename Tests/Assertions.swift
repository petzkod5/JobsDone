import Testing

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ context: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, "\(context)", sourceLocation: sourceLocation)
}
func expect(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(condition, sourceLocation: sourceLocation)
}
