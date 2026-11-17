#!/bin/bash
# Full Xcode: XCTest via SwiftPM. Command Line Tools: the same methods with a
# minimal assertion adapter (no accessibility grants or running app required).
set -euo pipefail
cd "$(dirname "$0")/.."
if printf 'import XCTest\n' | swiftc -typecheck - >/dev/null 2>&1; then
    exec swift test "$@"
fi
if [ "$#" -gt 0 ]; then
    echo "Test filters require full Xcode (swift test)." >&2
    exit 2
fi
echo 'XCTest is unavailable in Command Line Tools; running standalone regression checks.'
swift build
WORK=$(mktemp -d "${TMPDIR:-/tmp}/barbutler-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
python3 - "$WORK/Runner.swift" <<'PY'
import pathlib, re, sys
calls = []
for path in sorted(pathlib.Path('Tests/BarButlerTests').glob('*.swift')):
    text = path.read_text()
    name = re.search(r'final class (\w+): XCTestCase', text).group(1)
    methods = re.findall(r'    func (test\w+)\(\)( throws)?', text)
    for method, throwing in methods:
        prefix = 'try ' if throwing else ''
        calls.append(f'        {prefix}run("{method}") {{ {prefix}{name}().{method}() }}')
pathlib.Path(sys.argv[1]).write_text('''import Foundation
@main enum RegressionRunner {
    static func run(_ name: String, _ body: () throws -> Void) rethrows {
        try body()
        print("PASS: \\(name)")
    }
    static func main() throws {
''' + '\n'.join(calls) + f'\n        print("{len(calls)} regression checks passed.")\n' + '    }\n}\n')
PY
FRAMEWORK=$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' -print -quit)
# Compile application sources without the executable entry point. This also
# type-checks every UI source on the local SDK, not just the pure policy files.
SOURCES=()
for FILE in Sources/BarButler/*.swift; do
    [ "$FILE" = Sources/BarButler/main.swift ] || SOURCES+=("$FILE")
done
swiftc -D BARBUTLER_STANDALONE_TESTS -parse-as-library -module-name BarButler \
    -target "$(uname -m)-apple-macosx13.0" \
    -F "$(dirname "$FRAMEWORK")" -framework Sparkle -framework Carbon -framework ServiceManagement \
    -Xlinker -rpath -Xlinker "$(pwd)/$(dirname "$FRAMEWORK")" \
    "${SOURCES[@]}" Tests/BarButlerTests/*.swift scripts/testing/StandaloneAssertions.swift "$WORK/Runner.swift" \
    -o "$WORK/BarButlerChecks"
"$WORK/BarButlerChecks"
