import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractURL()
    }

    private func extractURL() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
              }) else {
            finish(success: false)
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
            guard let url = item as? URL else {
                self?.finish(success: false)
                return
            }
            self?.postToKnowledgeBase(url: url.absoluteString)
        }
    }

    private func postToKnowledgeBase(url urlString: String) {
        let defaults = UserDefaults(suiteName: "group.com.amakaflow.companion") ?? .standard
        let token = defaults.string(forKey: "auth_token")
        let testAuth = defaults.string(forKey: "test_auth_secret")
        let testUserId = defaults.string(forKey: "test_user_id")
        let envRaw = defaults.string(forKey: "app_environment") ?? "staging"

        let baseURL: String
        switch envRaw {
        case "development": baseURL = "http://localhost:8005"
        case "production":  baseURL = "https://chat-api.amakaflow.com"
        default:            baseURL = "https://chat-api.staging.amakaflow.com"
        }

        guard testAuth?.isEmpty == false || token?.isEmpty == false else {
            finish(success: false)
            return
        }

        guard let endpoint = URL(string: "\(baseURL)/api/knowledge/ingest") else {
            finish(success: false)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let testAuth, !testAuth.isEmpty {
            request.setValue(testAuth, forHTTPHeaderField: "X-Test-Auth")
            request.setValue(testUserId ?? "", forHTTPHeaderField: "X-Test-User-Id")
        } else if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["source_type": "url", "source_url": urlString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let error {
                    self?.finish(success: false)
                    return
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.finish(success: (200..<300).contains(statusCode))
            }
        }.resume()
    }

    private func finish(success: Bool) {
        if success {
            extensionContext?.completeRequest(returningItems: [])
        } else {
            extensionContext?.cancelRequest(withError:
                NSError(domain: "com.amakaflow.share", code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to capture URL"]))
        }
    }
}
