import AppKit

// 即使用户直接运行不同位置的 Forma 可执行文件，也只保留一个同 Bundle ID 的应用进程。
// 经 Launch Services 正常打开时，系统会把文件/重开事件转交给现有实例；此处覆盖手动重复启动。
#if DEBUG
let isVerificationRun = CommandLine.arguments.contains("--verify")
#else
let isVerificationRun = false
#endif
if !isVerificationRun, let bundleIdentifier = Bundle.main.bundleIdentifier,
    let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: {
        $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
    })
{
    existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
