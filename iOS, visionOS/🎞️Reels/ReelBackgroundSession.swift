import Foundation

// Manages a background URLSession for reel imports.
// Upload tasks survive app suspension — iOS networking daemon keeps the connection
// alive and wakes the app when the response arrives.
final class ReelBackgroundSession: NSObject {
    static let shared = ReelBackgroundSession()
    static let sessionIdentifier = "com.riskcreatives.luvly.reel-import"

    private var urlSession: URLSession!
    private var taskData: [Int: Data] = [:]
    private var completions: [Int: (Result<(URLResponse, Data), Error>) -> Void] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // Staged uploads must live in a location iOS preserves across suspension.
    // tmp/ can be cleaned between task creation and upload start; Caches/ survives.
    private static var uploadStagingDir: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("reel-uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func scheduleUpload(
        request: URLRequest,
        body: Data,
        jobID: UUID,
        completion: @escaping (Result<(URLResponse, Data), Error>) -> Void
    ) throws {
        let tempURL = Self.uploadStagingDir.appendingPathComponent(jobID.uuidString + ".json")
        try body.write(to: tempURL)

        var req = request
        req.httpBody = nil
        let task = urlSession.uploadTask(with: req, fromFile: tempURL)
        task.taskDescription = jobID.uuidString
        completions[task.taskIdentifier] = completion
        task.resume()
    }
}

extension ReelBackgroundSession: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        taskData[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let data = taskData.removeValue(forKey: id) ?? Data()
        let completion = completions.removeValue(forKey: id)

        // Clean up staged upload file now that iOS no longer needs it.
        if let jobIDString = task.taskDescription {
            let stagedURL = Self.uploadStagingDir.appendingPathComponent(jobIDString + ".json")
            try? FileManager.default.removeItem(at: stagedURL)
        }

        if let error {
            completion?(.failure(error))
            return
        }
        // task.response is reliably populated at completion time — more robust than
        // tracking it via didReceive(response:completionHandler:) which background
        // upload sessions may not call consistently.
        guard let response = task.response else {
            completion?(.failure(URLError(.badServerResponse)))
            return
        }
        completion?(.success((response, data)))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
