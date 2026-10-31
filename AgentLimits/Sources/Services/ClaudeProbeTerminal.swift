import AppKit
import Darwin
import Foundation

extension ClaudeStatusProbe {
    /// The primary side of the pseudo-terminal plus everything read from it. It is drained during every
    /// wait, including the final ones: a child whose output is not read blocks once the terminal buffer
    /// fills, and a blocked Claude Code could not finish saving a renewed token.
    final class Terminal {
        let child: Child
        private let primary: Int32
        private var output: [UInt8] = []
        private var lastOutput = Date()
        private var lastInput = Date()

        private init(child: Child, primary: Int32) {
            self.child = child
            self.primary = primary
        }

        static func start(executable: String, workingDirectory: URL, environment: [String: String]) -> Terminal? {
            var primary: Int32 = -1
            var secondary: Int32 = -1
            var size = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
            guard openpty(&primary, &secondary, nil, nil, &size) == 0 else { return nil }
            defer { Darwin.close(secondary) }
            guard fcntl(primary, F_SETFL, fcntl(primary, F_GETFL) | O_NONBLOCK) != -1,
                  let child = Child.spawn(
                      executable: executable,
                      workingDirectory: workingDirectory,
                      terminal: secondary,
                      environment: environment
                  )
            else {
                Darwin.close(primary)
                return nil
            }
            return Terminal(child: child, primary: primary)
        }

        // Decoded as a whole so multi-byte glyphs like `❯` stay intact; a glyph cut off at the end of the
        // latest read becomes U+FFFD instead of discarding the whole screen, as the failable init would.
        // swiftlint:disable:next optional_data_string_conversion
        var screen: String { String(decoding: output, as: UTF8.self) }

        /// True when neither side has written anything for `seconds`.
        func idle(for seconds: TimeInterval) -> Bool {
            Date().timeIntervalSince(max(lastOutput, lastInput)) >= seconds
        }

        func pump(for seconds: TimeInterval) {
            let until = Date().addingTimeInterval(seconds)
            var buffer = [UInt8](repeating: 0, count: 8192)
            repeat {
                let count = read(primary, &buffer, buffer.count)
                if count > 0 {
                    output.append(contentsOf: buffer.prefix(count))
                    if output.count > 131_072 { output.removeFirst(output.count - 65_536) }
                    lastOutput = Date()
                } else {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            } while Date() < until
        }

        func pump(until done: () -> Bool, upTo seconds: TimeInterval) {
            let until = Date().addingTimeInterval(seconds)
            while !done(), Date() < until {
                pump(for: 0.05)
            }
        }

        func send(_ text: String) {
            let bytes = Array(text.utf8)
            let until = Date().addingTimeInterval(1)
            bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < bytes.count, Date() < until {
                    let written = write(primary, base.advanced(by: offset), bytes.count - offset)
                    if written > 0 {
                        offset += written
                    } else if written < 0, errno == EINTR || errno == EAGAIN {
                        Thread.sleep(forTimeInterval: 0.02)
                    } else {
                        return
                    }
                }
            }
            lastInput = Date()
        }

        func close() {
            Darwin.close(primary)
        }
    }

    // MARK: - Child process

    /// The child runs in its own session so it and anything it starts can be signalled as one group.
    final class Child {
        let pid: pid_t
        private var exited = false

        private init(pid: pid_t) {
            self.pid = pid
        }

        func hasExited() -> Bool {
            if exited { return true }
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) {
                exited = true
                LiveProbes.remove(pid)
            }
            return exited
        }

        /// SIGTERM to the whole group, a grace period while the terminal keeps being drained, and only
        /// then SIGKILL. Interrupting a refresh between redeeming the token and saving it would log the
        /// user out, so SIGKILL is the very last resort.
        func terminate(grace: TimeInterval, draining terminal: Terminal) {
            if !hasExited() {
                killpg(pid, SIGTERM)
                terminal.pump(until: { hasExited() }, upTo: grace)
            }
            if !hasExited() {
                killpg(pid, SIGKILL)
                var status: Int32 = 0
                waitpid(pid, &status, 0)
                exited = true
                LiveProbes.remove(pid)
            }
            // Helpers the CLI started may outlive it; they share its process group.
            if killpg(pid, 0) == 0 {
                killpg(pid, SIGTERM)
            }
        }

        static func spawn(
            executable: String,
            workingDirectory: URL,
            terminal: Int32,
            environment: [String: String]
        ) -> Child? {
            var attributes: posix_spawnattr_t?
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }
            // A new session, no descriptor of this app leaks into the child besides the terminal, and the
            // child starts with default signal handling so SIGTERM reaches it even if this app blocks it.
            var noSignals = sigset_t()
            sigemptyset(&noSignals)
            var allSignals = sigset_t()
            sigfillset(&allSignals)
            posix_spawnattr_setsigmask(&attributes, &noSignals)
            posix_spawnattr_setsigdefault(&attributes, &allSignals)
            posix_spawnattr_setflags(
                &attributes,
                Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
            )

            var actions: posix_spawn_file_actions_t?
            posix_spawn_file_actions_init(&actions)
            defer { posix_spawn_file_actions_destroy(&actions) }
            for target in Int32(0)...2 {
                posix_spawn_file_actions_adddup2(&actions, terminal, target)
            }
            // The non-`_np` variant needs macOS 26; the app supports 14.
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path)

            let argv = ([executable] + arguments).map { strdup($0) } + [nil]
            let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
            defer {
                argv.forEach { free($0) }
                envp.forEach { free($0) }
            }

            var pid: pid_t = 0
            guard posix_spawn(&pid, executable, &actions, &attributes, argv, envp) == 0 else { return nil }
            LiveProbes.add(pid)
            return Child(pid: pid)
        }
    }

    /// Probes still running when the app quits get SIGTERM and a short wait, instead of being left
    /// behind: having no controlling terminal, they would not get SIGHUP when the app's side closes.
    enum LiveProbes {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var pids: Set<pid_t> = []
        nonisolated(unsafe) private static var observer: NSObjectProtocol?

        static func add(_ pid: pid_t) {
            lock.withLock {
                pids.insert(pid)
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(
                        forName: NSApplication.willTerminateNotification, object: nil, queue: nil
                    ) { _ in
                        terminateAll()
                    }
                }
            }
        }

        static func remove(_ pid: pid_t) {
            _ = lock.withLock { pids.remove(pid) }
        }

        private static func terminateAll() {
            let running = lock.withLock { pids }
            guard !running.isEmpty else { return }
            running.forEach { killpg($0, SIGTERM) }
            // `waitpid`, not `kill(pid, 0)`: an exited but unreaped probe would still look alive. Reaping
            // here is safe, `Child.hasExited` treats ECHILD as exited.
            var alive = running
            let until = Date().addingTimeInterval(3)
            while !alive.isEmpty, Date() < until {
                alive = alive.filter { pid in
                    var status: Int32 = 0
                    return waitpid(pid, &status, WNOHANG) == 0
                }
                if !alive.isEmpty { Thread.sleep(forTimeInterval: 0.1) }
            }
        }
    }
}
