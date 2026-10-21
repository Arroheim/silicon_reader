import Foundation

/// reader-check — runs the reader's engines over real documents.
///
///   reader-check --file doc.pdf              check one file, print one JSON line
///   reader-check --batch DIR [--jobs N] [--timeout S] [--report out.jsonl]
///                                            check every PDF/DjVu under DIR,
///                                            each in its own process
let usage = """
    Usage:
      reader-check --file <document> [--all-pages]
      reader-check --batch <folder> [--jobs N] [--timeout seconds] [--report path.jsonl] [--all-pages]

    Opens documents with the same engines as Silicon Reader and checks the first,
    middle and last page (size, render, text, links) plus the outline. --all-pages
    also renders every page at low resolution. In batch mode every file runs in
    its own process, so crashes and hangs are reported per file. Exit status is 1
    if any document failed, crashed or timed out.
    """

func value(after flag: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

let arguments = CommandLine.arguments
if arguments.contains("--help") || arguments.contains("-h") || arguments.count < 3 {
    print(usage)
    exit(arguments.count < 3 && !arguments.contains("--help") && !arguments.contains("-h") ? 64 : 0)
}

if let path = value(after: "--file") {
    let result = FileCheck.run(URL(fileURLWithPath: path), allPages: arguments.contains("--all-pages"))
    let data = (try? JSONEncoder().encode(result)) ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

if let folder = value(after: "--batch") {
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let options = BatchCheck.Options(
        folder: URL(fileURLWithPath: folder),
        jobs: value(after: "--jobs").flatMap(Int.init) ?? max(1, cores / 2),
        timeout: value(after: "--timeout").flatMap(Double.init) ?? 120,
        report: URL(fileURLWithPath: value(after: "--report") ?? "build/check/report.jsonl"),
        allPages: arguments.contains("--all-pages"))
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    exit(BatchCheck(options: options, executable: executable).run())
}

print(usage)
exit(64)
