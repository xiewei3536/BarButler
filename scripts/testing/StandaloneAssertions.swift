// Command Line Tools ships Swift but not XCTest.framework. This tiny assertion
// adapter runs the SAME test methods locally; full Xcode/CI uses real XCTest.
#if BARBUTLER_STANDALONE_TESTS
import Foundation

class XCTestCase { }

private func check(_ passed: Bool, _ message: String, file: StaticString, line: UInt) {
    guard !passed else { return }
    fputs("FAIL: \(file):\(line): \(message)\n", stderr)
    exit(1)
}

func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(value(), "expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(!value(), "expected false", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T,
                                 file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try lhs(), b = try rhs()
        check(a == b, "\(a) != \(b)", file: file, line: line)
    } catch { check(false, "unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    check(value() == nil, "expected nil", file: file, line: line)
}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else {
        check(false, "unexpected nil", file: file, line: line)
        throw NSError(domain: "BarButlerChecks", code: 1)
    }
    return value
}
#endif
