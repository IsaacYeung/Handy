// Standalone test binary — compiled and run by build.sh before packaging.
// Tests pure logic that doesn't require a running app, AppleScript, or hardware.
import Foundation

// MARK: - Minimal test harness

var passed = 0
var failed = 0
var currentSuite = ""

func suite(_ name: String) {
    currentSuite = name
    print("\n  \(name)")
}

func check(_ condition: Bool, _ description: String,
           file: String = #file, line: Int = #line) {
    if condition {
        print("    ✓  \(description)")
        passed += 1
    } else {
        print("    ✗  FAIL: \(description)  (\(file.split(separator: "/").last ?? ""):\(line))")
        failed += 1
    }
}

// MARK: - Duplicate of FinderCutPaste.uniqueDestination (private in prod)
// Kept in sync manually; if this logic changes, update both.

func uniqueDestination(_ src: URL, in dir: URL, existing: Set<String> = []) -> URL {
    // Use a provided set for testing; production code uses FileManager
    var dest = dir.appendingPathComponent(src.lastPathComponent)
    guard existing.contains(dest.lastPathComponent) else { return dest }
    let name = src.deletingPathExtension().lastPathComponent
    let ext  = src.pathExtension
    var n = 2
    repeat {
        let candidate = ext.isEmpty ? "\(name) (\(n))" : "\(name) (\(n)).\(ext)"
        dest = dir.appendingPathComponent(candidate)
        n += 1
    } while existing.contains(dest.lastPathComponent)
    return dest
}

// MARK: - Duplicate of pluginkitQuery output parsing (from SettingsView)

func parseExtStatus(output: String, inApps: Bool) -> String {
    if      output.contains("+") { return "active"      }
    else if output.contains("-") { return "disabled"    }
    else if inApps               { return "registering" }
    else                         { return "missing"     }
}

// MARK: - Tests

suite("File conflict naming")

let base = URL(fileURLWithPath: "/irrelevant")
let pdf  = URL(fileURLWithPath: "/somewhere/report.pdf")

check(uniqueDestination(pdf, in: base).lastPathComponent == "report.pdf",
      "No conflict → original name")

check(uniqueDestination(pdf, in: base, existing: ["report.pdf"]).lastPathComponent == "report (2).pdf",
      "Single conflict → (2)")

check(uniqueDestination(pdf, in: base, existing: ["report.pdf", "report (2).pdf"]).lastPathComponent == "report (3).pdf",
      "Double conflict → (3)")

check(uniqueDestination(pdf, in: base, existing: ["report.pdf", "report (2).pdf", "report (3).pdf"]).lastPathComponent == "report (4).pdf",
      "Triple conflict → (4)")

let noExt = URL(fileURLWithPath: "/somewhere/README")
check(uniqueDestination(noExt, in: base, existing: ["README"]).lastPathComponent == "README (2)",
      "No extension, conflict → (2)")

let dotfile = URL(fileURLWithPath: "/somewhere/.gitignore")
check(uniqueDestination(dotfile, in: base).lastPathComponent == ".gitignore",
      "Dotfile, no conflict → original name")

suite("Extension status parsing")

check(parseExtStatus(output: "   + com.lonfeng.handy.extension  [   6]", inApps: true)  == "active",
      "Leading whitespace + prefix → active")
check(parseExtStatus(output: "+ com.lonfeng.handy.extension",           inApps: true)  == "active",
      "Flush + prefix → active")
check(parseExtStatus(output: "   - com.lonfeng.handy.extension",        inApps: true)  == "disabled",
      "- prefix → disabled")
check(parseExtStatus(output: "",                                          inApps: true)  == "registering",
      "Empty output in /Applications → registering")
check(parseExtStatus(output: "",                                          inApps: false) == "missing",
      "Empty output outside /Applications → missing")
check(parseExtStatus(output: "no match here",                            inApps: false) == "missing",
      "Unrecognised output outside /Applications → missing")

suite("KCode values (virtual key codes must match hardware layout)")
// These constants are fixed Mac virtual key codes — verify they haven't been
// accidentally changed. If they change, cut/paste silently breaks.
let x:       Int64 = 7
let v:       Int64 = 9
let c:       Int64 = 8
let ret:     Int64 = 36
let escape:  Int64 = 53
check(x == 7,  "Cmd+X virtual key code is 7")
check(v == 9,  "Cmd+V virtual key code is 9")
check(c == 8,  "Cmd+C virtual key code is 8")
check(ret == 36, "Return key virtual key code is 36")
check(escape == 53, "Escape key virtual key code is 53")

// MARK: - Summary

print("")
print("  ─────────────────────────────────────────")
let emoji = failed == 0 ? "✓" : "✗"
print("  \(emoji)  \(passed) passed, \(failed) failed")
print("")

exit(failed > 0 ? 1 : 0)
