import Foundation
import SwiftUI

struct BridgeProject: Identifiable, Codable {
    let id: String
    let name: String
}

struct BridgeSession: Identifiable, Codable {
    let id: String
    let title: String
}

struct BridgeMessage: Identifiable, Codable {
    var id: String { "\(role)-\(content.hashValue)" }
    let role: String
    let content: String
}

struct SessionDetail: Codable {
    let id: String
    let title: String
    let messages: [BridgeMessage]
}

@MainActor
final class BridgeModel: ObservableObject {
    @AppStorage("bridgeEndpoint") var endpoint = ""
    @AppStorage("bridgeToken") var token = ""
    @Published var projects: [BridgeProject] = []
    @Published var sessions: [BridgeSession] = []
    @Published var selectedProject: BridgeProject?
    @Published var selectedSession: BridgeSession?
    @Published var detail: SessionDetail?
    @Published var status = "Not connected"
    @Published var draft = ""

    func connect() async {
        do {
            status = "Loading Artificer..."
            let payload = try await get("/projects")
            projects = (try? JSONDecoder().decode(ProjectList.self, from: payload).projects) ?? []
            _ = try? await get("/health")
            status = "Connected"
        } catch {
            status = error.localizedDescription
        }
    }

    func open(_ project: BridgeProject) async {
        selectedProject = project
        selectedSession = nil
        detail = nil
        do {
            let payload = try await get("/sessions?workspace_id=\(project.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
            sessions = (try? JSONDecoder().decode(SessionList.self, from: payload).sessions) ?? []
            status = "\(sessions.count) chats"
        } catch {
            status = error.localizedDescription
        }
    }

    func open(_ session: BridgeSession) async {
        guard let project = selectedProject else { return }
        selectedSession = session
        do {
            let path = "/session?workspace_id=\(project.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&conversation_id=\(session.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            let payload = try await get(path)
            detail = (try? JSONDecoder().decode(SessionResponse.self, from: payload).session)
            status = "Loaded"
        } catch {
            status = error.localizedDescription
        }
    }

    func send() async {
        guard let project = selectedProject, let session = selectedSession else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        do {
            _ = try await post("/message", body: MessageRequest(workspace_id: project.id, conversation_id: session.id, prompt: text, run_after: true))
            await open(session)
        } catch {
            status = error.localizedDescription
        }
    }

    private func request(_ path: String, method: String, body: Data? = nil) throws -> URLRequest {
        let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "X-Artificer-Mobile-Token")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func get(_ path: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "GET"))
        try check(response, data: data)
        return data
    }

    private func post<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        let (payload, response) = try await URLSession.shared.data(for: request(path, method: "POST", body: data))
        try check(response, data: payload)
        return payload
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw NSError(domain: "ArtificerMobile", code: 1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Bridge request failed"])
        }
    }
}

struct ProjectList: Codable { let projects: [BridgeProject] }
struct SessionList: Codable { let sessions: [BridgeSession] }
struct SessionResponse: Codable { let session: SessionDetail }
struct MessageRequest: Codable {
    let workspace_id: String
    let conversation_id: String
    let prompt: String
    let run_after: Bool
}

struct ContentView: View {
    @StateObject private var model = BridgeModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Bridge") {
                    TextField("Bridge URL", text: $model.endpoint)
                    SecureField("Pairing token", text: $model.token)
                    Button("Connect") { Task { await model.connect() } }
                }
                Section("Workspaces") {
                    ForEach(model.projects) { project in
                        NavigationLink(project.name) {
                            SessionsView(model: model, project: project)
                        }
                    }
                }
            }
            .navigationTitle("Artificer")
            .safeAreaInset(edge: .bottom) {
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.bar)
            }
        }
    }
}

struct SessionsView: View {
    @ObservedObject var model: BridgeModel
    let project: BridgeProject

    var body: some View {
        List(model.sessions) { session in
            NavigationLink(session.title.isEmpty ? session.id : session.title) {
                ChatView(model: model, session: session)
            }
        }
        .navigationTitle(project.name)
        .task { await model.open(project) }
    }
}

struct ChatView: View {
    @ObservedObject var model: BridgeModel
    let session: BridgeSession

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .navigationTitle(session.title.isEmpty ? "Chat" : session.title)
        .task { await model.open(session) }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.detail?.messages ?? []) { message in
                    messageBubble(message)
                }
            }
            .padding()
        }
    }

    private func messageBubble(_ message: BridgeMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.content)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        HStack(alignment: .bottom) {
            TextField("Message Artificer", text: $model.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button("Send") { Task { await model.send() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }
}
