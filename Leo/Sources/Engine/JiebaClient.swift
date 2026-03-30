import Foundation

// MARK: - Errors

enum JiebaError: Error {
    case unavailable
    case communicationFailed(String)
    case invalidResponse
}

// MARK: - JiebaClient

/// Communicates with a persistent Python Jieba segmentation daemon via Unix domain socket.
/// Falls back gracefully if Python/Jieba is unavailable — the caller must check `isAvailable`.
///
/// The daemon is a short Python script launched as a subprocess. It:
///   1. Binds a UNIX domain socket at `/tmp/leo-jieba.sock`
///   2. Accepts one connection at a time
///   3. Reads a newline-terminated JSON request: `{"text": "..."}`
///   4. Responds with a newline-terminated JSON response: `{"tokens": [...]}`
actor JiebaClient {

    // MARK: - Singleton

    static let shared = JiebaClient()

    // MARK: - State

    private let socketPath = "/tmp/leo-jieba.sock"
    private var daemonProcess: Process?
    private var socketFD: Int32 = -1
    private(set) var isAvailable = false

    // MARK: - Init

    private init() {}

    // MARK: - Lifecycle

    /// Launch the daemon and verify connectivity. Safe to call multiple times — no-op if already available.
    /// Call once at app start with `Task { await JiebaClient.shared.start() }`.
    func start() async {
        guard !isAvailable else { return }
        guard pythonAndJiebaAvailable() else {
            NSLog("[JiebaClient] python3+jieba not found — NLTagger will be used as Layer 1")
            return
        }

        cleanupSocket()
        launchDaemon()

        // Poll for up to 2 seconds (20 x 100ms) for the daemon to bind and listen.
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
            if tryConnect() {
                isAvailable = true
                NSLog("[JiebaClient] daemon connected — Jieba is now Layer 1")
                return
            }
        }

        NSLog("[JiebaClient] daemon did not start in time — NLTagger fallback active")
    }

    /// Segment Chinese text using the running Jieba daemon.
    /// Throws `JiebaError.unavailable` when the daemon is not running.
    func segment(_ text: String) async throws -> [String] {
        guard isAvailable else { throw JiebaError.unavailable }
        guard socketFD >= 0 else {
            isAvailable = false
            throw JiebaError.unavailable
        }

        // Build newline-terminated JSON request.
        let requestDict: [String: String] = ["text": text]
        let requestData: Data
        do {
            requestData = try JSONSerialization.data(withJSONObject: requestDict)
        } catch {
            throw JiebaError.communicationFailed("JSON encode failed: \(error)")
        }
        var payload = requestData
        payload.append(UInt8(ascii: "\n"))

        // Send.
        let sendResult = payload.withUnsafeBytes { ptr -> Int in
            Darwin.send(socketFD, ptr.baseAddress!, ptr.count, 0)
        }
        guard sendResult == payload.count else {
            isAvailable = false
            close(socketFD)
            socketFD = -1
            throw JiebaError.communicationFailed("send() returned \(sendResult), expected \(payload.count)")
        }

        // Receive until newline (daemon sends one newline-terminated JSON line per request).
        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var attempts = 0
        let maxAttempts = 100
        while attempts < maxAttempts {
            let bytesRead = Darwin.recv(socketFD, &buffer, buffer.count, 0)
            if bytesRead <= 0 { break }
            responseData.append(contentsOf: buffer.prefix(bytesRead))
            if responseData.contains(UInt8(ascii: "\n")) { break }
            attempts += 1
        }

        // Strip trailing newline and parse.
        if let newlineIndex = responseData.firstIndex(of: UInt8(ascii: "\n")) {
            responseData = responseData[responseData.startIndex..<newlineIndex]
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let tokens = json["tokens"] as? [String]
        else {
            throw JiebaError.invalidResponse
        }

        return tokens
    }

    // MARK: - Private Helpers

    /// Returns true if `python3 -c "import jieba"` exits cleanly.
    private func pythonAndJiebaAvailable() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", "-c", "import jieba"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return false
        }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    /// Remove the socket file if it already exists (from a previous crashed session).
    private func cleanupSocket() {
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    /// Launch the Python daemon as a detached subprocess.
    /// The daemon binds the socket, initialises jieba (once), then loops accepting connections.
    private func launchDaemon() {
        // Build the daemon source separately to avoid embedding escape sequences that
        // confuse the Swift string parser.
        let daemonSource = buildDaemonSource()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", "-c", daemonSource]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            daemonProcess = proc
            NSLog("[JiebaClient] daemon process started (pid \(proc.processIdentifier))")
        } catch {
            NSLog("[JiebaClient] Failed to launch daemon: \(error)")
        }
    }

    /// Returns the Python source for the Jieba daemon.
    private func buildDaemonSource() -> String {
        // Written as an array of lines then joined, so the Swift string literals stay clean.
        let lines: [String] = [
            "import socket, json, jieba, os, sys",
            "sock_path = '/tmp/leo-jieba.sock'",
            "if os.path.exists(sock_path): os.remove(sock_path)",
            "srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)",
            "srv.bind(sock_path)",
            "srv.listen(1)",
            "jieba.initialize()",
            "sys.stdout.flush()",
            "while True:",
            "    conn, _ = srv.accept()",
            "    buf = b''",
            "    while True:",
            "        chunk = conn.recv(4096)",
            "        if not chunk: break",
            "        buf += chunk",
            "        while b'\\n' in buf:",
            "            line, buf = buf.split(b'\\n', 1)",
            "            if not line: continue",
            "            try:",
            "                req = json.loads(line.decode('utf-8'))",
            "                tokens = list(jieba.cut(req.get('text', ''), cut_all=False))",
            "                resp = json.dumps({'tokens': tokens}, ensure_ascii=False).encode('utf-8') + b'\\n'",
            "                conn.sendall(resp)",
            "            except Exception as e:",
            "                err = json.dumps({'tokens': [], 'error': str(e)}).encode('utf-8') + b'\\n'",
            "                conn.sendall(err)",
            "    conn.close()",
        ]
        return lines.joined(separator: "\n")
    }

    /// Attempt a POSIX connect to the Unix domain socket. Returns true on success.
    private func tryConnect() -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        // Apply 500ms receive/send timeout so reads never block forever.
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy socket path into sun_path (fixed-size C array).
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            pathBytes.withUnsafeBytes { src in
                let copyLen = min(src.count, ptr.count - 1)
                ptr.copyMemory(from: UnsafeRawBufferPointer(start: src.baseAddress, count: copyLen))
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            close(fd)
            return false
        }

        // Connection established — store the fd for subsequent send/recv calls.
        if socketFD >= 0 { close(socketFD) }
        socketFD = fd
        return true
    }
}
