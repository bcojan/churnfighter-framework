import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(churnfighter_frameworkTests.allTests),
    ]
}
#endif
