import Foundation

public enum DemoRepository {
  public static func bunRewrite() -> (RepositorySnapshot, DiffLoader) {
    let featured = [
      ("src/js_parser/p.rs", 9_765),
      ("src/sys/lib.rs", 9_211),
      ("src/css/properties/properties_generated.rs", 7_968),
      ("src/runtime/webcore/Blob.rs", 7_126),
      ("src/runtime/bake/DevServer.rs", 7_069),
      ("src/jsc/VirtualMachine.rs", 6_640),
      ("src/runtime/dns_jsc/dns.rs", 6_026),
      ("src/parsers/yaml.rs", 5_699),
      ("src/runtime/jsc_hooks.rs", 5_160),
      ("src/runtime/napi/napi_body.rs", 4_354),
      ("src/runtime/cli/pack_command.rs", 4_298),
      ("src/js_parser/lexer.rs", 4_155),
      ("Cargo.lock", 4_035),
      ("scripts/build/rust.ts", 761),
      ("build.zig", 0),
    ]
    var files = featured.enumerated().map { index, value in
      ChangedFile(
        id: index,
        path: value.0,
        kind: value.0 == "build.zig" ? .deleted : .added,
        additions: value.1,
        deletions: value.0 == "build.zig" ? 1_172 : 0)
    }
    for index in files.count..<2_188 {
      let group: String
      switch index % 6 {
      case 0: group = "src/runtime"
      case 1: group = "src/bun_core"
      case 2: group = "src/install"
      case 3: group = "src/bundler"
      case 4: group = "src/tests"
      default: group = "scripts/migration"
      }
      let kind: FileChangeKind =
        if index % 19 == 0 { .renamed } else if index % 13 == 0 { .modified } else { .added }
      let additions = kind == .added ? 80 + (index * 37) % 820 : 4 + (index * 11) % 190
      let deletions = kind == .modified ? 1 + (index * 7) % 64 : 0
      files.append(
        ChangedFile(
          id: index,
          path: String(format: "%@/module_%04d.rs", group, index),
          kind: kind,
          additions: additions,
          deletions: deletions))
    }

    let snapshot = RepositorySnapshot(
      title: "Bun #30412",
      subtitle: "Rewrite Bun in Rust",
      branch: "rust",
      files: files,
      additions: 1_009_257,
      deletions: 4_024,
      commits: 100,
      isDemonstration: true)
    let loader: DiffLoader = { file in
      try await Task.sleep(for: .milliseconds(35))
      return syntheticDiff(for: file)
    }
    return (snapshot, loader)
  }

  private static func syntheticDiff(for file: ChangedFile) -> [DiffLine] {
    let oldPath = file.kind == .added ? "/dev/null" : "a/\(file.path)"
    let lineCount = min(180, max(28, file.additions / 40))
    var lines = [
      DiffLine("diff --git a/\(file.path) b/\(file.path)"),
      DiffLine("index 0000000..cafe042 100644"),
      DiffLine("--- \(oldPath)"),
      DiffLine("+++ b/\(file.path)"),
      DiffLine("@@ -1,8 +1,\(lineCount) @@"),
    ]
    for index in 0..<lineCount {
      if file.kind == .modified, index % 13 == 0 {
        lines.append(DiffLine("-    legacy_allocator.release(slot_\(index));"))
        lines.append(DiffLine("+    allocator.release(SlotId::new(\(index)))?;"))
      } else if index % 11 == 0 {
        lines.append(DiffLine(" "))
      } else if index % 7 == 0 {
        lines.append(DiffLine("+    // SAFETY: ownership transfers at the FFI boundary."))
      } else {
        lines.append(
          DiffLine("+    let value_\(index) = RuntimeValue::from_raw(source.read(\(index)))?;"))
      }
    }
    if file.kind == .deleted {
      lines = [
        DiffLine("diff --git a/\(file.path) b/\(file.path)"),
        DiffLine("deleted file mode 100644"),
        DiffLine("--- a/\(file.path)"),
        DiffLine("+++ /dev/null"),
        DiffLine("@@ -1,6 +0,0 @@"),
        DiffLine("-const std = @import(\"std\");"),
        DiffLine("-pub fn build(b: *std.Build) void {"),
        DiffLine("-    const target = b.standardTargetOptions(.{});"),
        DiffLine("-    _ = target;"),
        DiffLine("-}"),
      ]
    }
    return lines
  }
}
