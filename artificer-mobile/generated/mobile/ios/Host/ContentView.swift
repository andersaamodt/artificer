import Foundation
import SwiftUI

struct RuntimeHealth: Codable {
    let defaultModel: String
    let installedModelCount: Int

    enum CodingKeys: String, CodingKey {
        case defaultModel = "default_model"
        case installedModelCount = "installed_model_count"
    }

    init(defaultModel: String = "", installedModelCount: Int = 0) {
        self.defaultModel = defaultModel
        self.installedModelCount = installedModelCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultModel = (try? container.decode(String.self, forKey: .defaultModel)) ?? ""
        installedModelCount = (try? container.decode(Int.self, forKey: .installedModelCount)) ?? 0
    }
}

struct QueueState: Codable {
    let pending: Int
    let running: Int
    let done: Int

    enum CodingKeys: String, CodingKey {
        case pending, running, done
    }

    static let empty = QueueState(pending: 0, running: 0, done: 0)

    init(pending: Int = 0, running: Int = 0, done: Int = 0) {
        self.pending = pending
        self.running = running
        self.done = done
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pending = (try? container.decode(Int.self, forKey: .pending)) ?? 0
        running = (try? container.decode(Int.self, forKey: .running)) ?? 0
        done = (try? container.decode(Int.self, forKey: .done)) ?? 0
    }
}

struct BridgeProject: Identifiable, Codable {
    let id: String
    let name: String
    let path: String
    let pathExists: Bool
    let sessionCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, path
        case pathExists = "path_exists"
        case sessionCount = "session_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? id
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        pathExists = (try? container.decode(Bool.self, forKey: .pathExists)) ?? true
        sessionCount = (try? container.decode(Int.self, forKey: .sessionCount)) ?? 0
    }
}

struct BridgeSession: Identifiable, Codable {
    let id: String
    let workspaceID: String
    let title: String
    let model: String
    let updated: Int
    let queue: QueueState

    init(id: String, workspaceID: String = "", title: String, model: String = "", updated: Int = 0, queue: QueueState = .empty) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.model = model
        self.updated = updated
        self.queue = queue
    }

    enum CodingKeys: String, CodingKey {
        case id, title, model, updated, queue
        case workspaceID = "workspace_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        workspaceID = (try? container.decode(String.self, forKey: .workspaceID)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? id
        model = (try? container.decode(String.self, forKey: .model)) ?? ""
        updated = (try? container.decode(Int.self, forKey: .updated)) ?? 0
        queue = (try? container.decode(QueueState.self, forKey: .queue)) ?? .empty
    }
}

struct BridgeMessage: Identifiable, Codable {
    var id: String { "\(role)-\(content.hashValue)-\(content.count)" }
    let role: String
    let content: String
}

struct SessionDetail: Codable {
    let id: String
    let title: String
    let model: String
    let updated: Int
    let queue: QueueState
    let messages: [BridgeMessage]
}

@MainActor
final class BridgeModel: ObservableObject {
    @AppStorage("bridgeEndpoint") var endpoint = ""
    @AppStorage("bridgeToken") var token = ""
    @Published var projects: [BridgeProject] = []
    @Published var sessionsByProject: [String: [BridgeSession]] = [:]
    @Published var expandedProjectIDs: Set<String> = []
    @Published var loadingProjectIDs: Set<String> = []
    @Published var selectedProject: BridgeProject?
    @Published var selectedSession: BridgeSession?
    @Published var detail: SessionDetail?
    @Published var runtime: RuntimeHealth?
    @Published var status = "Not connected"
    @Published var draft = ""
    @Published var query = ""
    @Published var isRefreshing = false
    @Published var lastUpdated = ""

    func connect() async {
        await refresh()
    }

    func refresh() async {
        do {
            isRefreshing = true
            status = "Loading Artificer..."
            let healthPayload = try await get("/health")
            runtime = (try? JSONDecoder().decode(HealthResponse.self, from: healthPayload).runtime)
            let payload = try await get("/projects")
            projects = (try? JSONDecoder().decode(ProjectList.self, from: payload).projects) ?? []
            projects = projects.filter(\.pathExists)
            sessionsByProject = sessionsByProject.filter { key, _ in projects.contains { $0.id == key } }
            expandedProjectIDs = expandedProjectIDs.filter { id in projects.contains { $0.id == id } }
            lastUpdated = Self.timeFormatter.string(from: Date())
            status = projects.isEmpty ? "No folders returned" : "\(projects.count) folders"
        } catch {
            status = error.localizedDescription
        }
        isRefreshing = false
    }

    func setExpanded(_ project: BridgeProject, expanded: Bool) async {
        if expanded {
            expandedProjectIDs.insert(project.id)
            await ensureSessions(project)
        } else {
            expandedProjectIDs.remove(project.id)
        }
    }

    func ensureSessions(_ project: BridgeProject) async {
        guard sessionsByProject[project.id] == nil, !loadingProjectIDs.contains(project.id) else { return }
        loadingProjectIDs.insert(project.id)
        do {
            let payload = try await get("/sessions?workspace_id=\(project.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
            let sessions = (try? JSONDecoder().decode(SessionList.self, from: payload).sessions) ?? []
            sessionsByProject[project.id] = sessions
            status = "\(sessions.count) chats in \(project.name)"
        } catch {
            status = error.localizedDescription
        }
        loadingProjectIDs.remove(project.id)
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

    func visibleProjects() -> [BridgeProject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return projects }
        return projects.filter { project in
            if project.name.lowercased().contains(needle) { return true }
            if project.path.lowercased().contains(needle) { return true }
            return (sessionsByProject[project.id] ?? []).contains { $0.title.lowercased().contains(needle) }
        }
    }

    func visibleSessions(for project: BridgeProject) -> [BridgeSession] {
        let sessions = sessionsByProject[project.id] ?? []
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return sessions }
        if project.name.lowercased().contains(needle) { return sessions }
        if project.path.lowercased().contains(needle) { return sessions }
        return sessions.filter {
            $0.title.lowercased().contains(needle)
            || $0.model.lowercased().contains(needle)
        }
    }

    func queueLabel(_ session: BridgeSession) -> String {
        if session.queue.running > 0 { return "running \(session.queue.running)" }
        if session.queue.pending > 0 { return "queued \(session.queue.pending)" }
        if session.queue.done > 0 { return "done \(session.queue.done)" }
        return ""
    }

    func detailLine(_ session: BridgeSession) -> String {
        var parts: [String] = []
        if !session.model.isEmpty { parts.append(session.model) }
        if session.updated > 0 {
            parts.append(Self.detailDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.updated))))
        }
        let queue = queueLabel(session)
        if !queue.isEmpty { parts.append(queue) }
        return parts.joined(separator: " - ")
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct HealthResponse: Codable { let runtime: RuntimeHealth }
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
            VStack(spacing: 0) {
                header
                List {
                    bridgeSection
                    folderSection
                }
                .searchable(text: $model.query, prompt: "Search folders and chats")
                .refreshable { await model.refresh() }
                .safeAreaInset(edge: .bottom) {
                    StatusBar(text: model.status)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Artificer")
                    .font(.title2.bold())
                Text(model.lastUpdated.isEmpty ? "Mobile bridge" : "Updated \(model.lastUpdated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ContextWindow(model: model)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var bridgeSection: some View {
        Section("Bridge") {
            if model.projects.isEmpty {
                Text("Pair this phone with the Mobile tab in Artificer Preferences.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextField("Bridge URL", text: $model.endpoint)
                .textContentType(.URL)
            SecureField("Pairing token", text: $model.token)
            HStack {
                Button(model.projects.isEmpty ? "Connect" : "Refresh") { Task { await model.refresh() } }
                    .disabled(model.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.isRefreshing {
                    ProgressView()
                }
            }
        }
    }

    private var folderSection: some View {
        Section("Folders") {
            let projects = model.visibleProjects()
            if projects.isEmpty {
                EmptyState(title: model.projects.isEmpty ? "No folders" : "No matches", detail: model.projects.isEmpty ? "No existing Artificer folders were returned by the bridge." : "No loaded folder or chat matches this search.")
            } else {
                ForEach(projects) { project in
                    ProjectDisclosure(model: model, project: project)
                }
            }
        }
    }
}

struct ContextWindow: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(model.runtime?.defaultModel ?? (model.projects.isEmpty ? "Not connected" : "Connected"))
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(model.runtime.map { "\($0.installedModelCount) models" } ?? "Bridge")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.teal.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ProjectDisclosure: View {
    @ObservedObject var model: BridgeModel
    let project: BridgeProject

    var isExpanded: Binding<Bool> {
        Binding(
            get: {
                model.expandedProjectIDs.contains(project.id)
                || (!model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.sessionsByProject[project.id] != nil)
            },
            set: { expanded in Task { await model.setExpanded(project, expanded: expanded) } }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            let sessions = model.visibleSessions(for: project)
            if model.loadingProjectIDs.contains(project.id) {
                HStack {
                    ProgressView()
                    Text("Loading chats...")
                }
            } else if model.sessionsByProject[project.id] == nil {
                Button("Load chats") { Task { await model.ensureSessions(project) } }
            } else if sessions.isEmpty {
                EmptyState(title: "No chats", detail: "This folder has no chats matching the current view.")
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        ChatView(model: model, project: project, session: session)
                    } label: {
                        ChatRow(model: model, session: session)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                Text(project.name)
                Spacer()
                Text("\(project.sessionCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .task {
            if model.expandedProjectIDs.contains(project.id) {
                await model.ensureSessions(project)
            }
        }
    }
}

struct ChatRow: View {
    @ObservedObject var model: BridgeModel
    let session: BridgeSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? session.id : session.title)
                    .lineLimit(1)
                let detail = model.detailLine(session)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(session.queue.running > 0 ? .green : .orange)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}

struct ChatView: View {
    @ObservedObject var model: BridgeModel
    let project: BridgeProject
    let session: BridgeSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let queue = model.queueLabel(session)
                    if !queue.isEmpty {
                        Text(queue)
                            .font(.caption2)
                            .foregroundStyle(session.queue.running > 0 ? .green : .orange)
                    }
                    if !session.model.isEmpty {
                        Text(session.model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ContextWindow(model: model)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            messageList
            composer
        }
        .navigationTitle(session.title.isEmpty ? "Chat" : session.title)
        .task {
            model.selectedProject = project
            await model.open(session)
        }
        .refreshable { await model.open(session) }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                let messages = model.detail?.messages ?? []
                if messages.isEmpty {
                    EmptyState(title: "No messages", detail: "This chat has no visible transcript yet.")
                } else {
                    ForEach(messages) { message in
                        messageBubble(message)
                    }
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
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.bar)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct StatusBar: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
    }
}
