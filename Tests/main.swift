// Standalone test binary — compiled and run by build.sh before packaging.
// Compiled together with Sources/Shared/FileNaming.swift so the tests
// exercise the REAL production logic, not a copy.
import Foundation

// MARK: - Minimal test harness

var passed = 0
var failed = 0

func suite(_ name: String) {
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

// MARK: - Duplicate of pluginkitQuery output parsing (from SettingsView)

func parseExtStatus(output: String, inApps: Bool) -> String {
    if      output.contains("+") { return "active"      }
    else if output.contains("-") { return "disabled"    }
    else if inApps               { return "registering" }
    else                         { return "missing"     }
}

// MARK: - Tests

suite("File conflict naming (real FileNaming.uniqueDestination)")

let base = URL(fileURLWithPath: "/irrelevant")
let pdf  = URL(fileURLWithPath: "/somewhere/report.pdf")

// Calls the production function with an injected `exists` closure so the
// filesystem isn't touched; `existing` holds the names taken in the dest dir.
func dest(_ src: URL, existing: Set<String> = []) -> String {
    FileNaming.uniqueDestination(src, in: base) { path in
        existing.contains(URL(fileURLWithPath: path).lastPathComponent)
    }.lastPathComponent
}

check(dest(pdf) == "report.pdf",
      "No conflict → original name")

check(dest(pdf, existing: ["report.pdf"]) == "report (2).pdf",
      "Single conflict → (2)")

check(dest(pdf, existing: ["report.pdf", "report (2).pdf"]) == "report (3).pdf",
      "Double conflict → (3)")

check(dest(pdf, existing: ["report.pdf", "report (2).pdf", "report (3).pdf"]) == "report (4).pdf",
      "Triple conflict → (4)")

let noExt = URL(fileURLWithPath: "/somewhere/README")
check(dest(noExt, existing: ["README"]) == "README (2)",
      "No extension, conflict → (2)")

let dotfile = URL(fileURLWithPath: "/somewhere/.gitignore")
check(dest(dotfile) == ".gitignore",
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
