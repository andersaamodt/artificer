#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
ir_path="$project_dir/app-blueprint/mobile.ir.yaml"
schema_path="$project_dir/schemas/native-mobile-ir-v1.json"
generated_root="$project_dir/generated/mobile"
android_dir="$generated_root/android"
ios_dir="$generated_root/ios"
version_file="$project_dir/VERSION"

"$script_dir/validate-native-mobile-ir.sh" "$ir_path" "$schema_path" >/dev/null

app_name=$(jq -r '.app.name' "$ir_path")
app_id=$(jq -r '.app.id' "$ir_path")
package_part=$(printf '%s' "$app_id" | tr '-' '_')
android_package="app.wizardry.artificer.mobile"
ios_bundle="app.wizardry.artificer.mobile"
app_version=0.1.0
if [ -f "$version_file" ]; then
  app_version=$(tr -d ' \t\r\n' <"$version_file")
fi
version_code=$(printf '%s' "$app_version" | cksum | awk '{ print $1 }')
[ -n "$version_code" ] || version_code=1

rm -rf "$android_dir" "$ios_dir"
mkdir -p "$android_dir/app/src/main/java/app/wizardry/artificer/mobile" "$android_dir/app/src/main/res/values" "$ios_dir/Host"

cat >"$android_dir/settings.gradle" <<GRADLE
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "$app_id-native-mobile"
include ':app'
GRADLE

cat >"$android_dir/build.gradle" <<'GRADLE'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
GRADLE

cat >"$android_dir/app/build.gradle" <<GRADLE
plugins { id 'com.android.application' }

android {
    namespace '$android_package'
    compileSdk 35

    defaultConfig {
        applicationId '$android_package'
        minSdk 23
        targetSdk 35
        versionCode $version_code
        versionName '$app_version'
    }
}
GRADLE

cat >"$android_dir/app/src/main/AndroidManifest.xml" <<XML
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:theme="@style/AppTheme" android:label="$app_name" android:allowBackup="false" android:supportsRtl="true" android:usesCleartextTraffic="true">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
XML

cat >"$android_dir/app/src/main/res/values/styles.xml" <<'XML'
<resources>
    <style name="AppTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:fontFamily">sans</item>
        <item name="android:windowLightStatusBar">true</item>
        <item name="android:statusBarColor">#F7F4ED</item>
        <item name="android:navigationBarColor">#F7F4ED</item>
        <item name="android:colorAccent">#1D6D73</item>
    </style>
</resources>
XML

cat >"$android_dir/app/src/main/java/app/wizardry/artificer/mobile/MainActivity.java" <<'JAVA'
package app.wizardry.artificer.mobile;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.graphics.Typeface;
import android.content.SharedPreferences;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import org.json.JSONArray;
import org.json.JSONObject;

public final class MainActivity extends Activity {
    private LinearLayout root;
    private SharedPreferences prefs;
    private String endpoint = "";
    private String token = "";
    private JSONArray projects = new JSONArray();
    private JSONArray sessions = new JSONArray();
    private JSONObject selectedProject;
    private JSONObject selectedSession;
    private JSONObject sessionDetail;
    private TextView title;
    private TextView status;
    private int bg = Color.rgb(247, 244, 237);
    private int ink = Color.rgb(31, 35, 36);
    private int line = Color.rgb(212, 205, 193);
    private int accent = Color.rgb(29, 109, 115);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("artificer-mobile", MODE_PRIVATE);
        endpoint = prefs.getString("endpoint", "");
        token = prefs.getString("token", "");
        showConnect();
    }

    private TextView text(String value, int sp, int style) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(ink);
        view.setTypeface(Typeface.DEFAULT, style);
        view.setIncludeFontPadding(true);
        return view;
    }

    private Button button(String label) {
        Button view = new Button(this);
        view.setText(label);
        view.setAllCaps(false);
        return view;
    }

    private EditText input(String hint, String value) {
        EditText view = new EditText(this);
        view.setHint(hint);
        view.setText(value);
        view.setSingleLine(false);
        view.setMinLines(1);
        view.setImeOptions(EditorInfo.IME_ACTION_DONE);
        return view;
    }

    private void base(String screenTitle) {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(22, 18, 22, 14);
        root.setBackgroundColor(bg);
        title = text(screenTitle, 22, Typeface.BOLD);
        status = text("", 12, Typeface.NORMAL);
        status.setTextColor(Color.rgb(100, 92, 82));
        root.addView(title, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(status, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);
    }

    private void setStatus(String value) {
        runOnUiThread(() -> status.setText(value));
    }

    private String request(String method, String path, JSONObject body) throws Exception {
        String base = endpoint.endsWith("/") ? endpoint.substring(0, endpoint.length() - 1) : endpoint;
        HttpURLConnection conn = (HttpURLConnection)new URL(base + path).openConnection();
        conn.setRequestMethod(method);
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(20000);
        conn.setRequestProperty("X-Artificer-Mobile-Token", token);
        if (body != null) {
            byte[] bytes = body.toString().getBytes("UTF-8");
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            conn.setRequestProperty("Content-Length", String.valueOf(bytes.length));
            OutputStream output = conn.getOutputStream();
            output.write(bytes);
            output.close();
        }
        InputStream stream = conn.getResponseCode() >= 400 ? conn.getErrorStream() : conn.getInputStream();
        BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
        StringBuilder out = new StringBuilder();
        String lineValue;
        while ((lineValue = reader.readLine()) != null) out.append(lineValue);
        reader.close();
        return out.toString();
    }

    private void showConnect() {
        base("Artificer Mobile");
        TextView hint = text("Connect to the Mobile bridge shown in Artificer Preferences.", 14, Typeface.NORMAL);
        hint.setTextColor(Color.rgb(83, 78, 71));
        root.addView(hint);
        EditText endpointField = input("http://192.168.1.20:8765", endpoint);
        EditText tokenField = input("Pairing token", token);
        root.addView(endpointField);
        root.addView(tokenField);
        Button connect = button("Connect");
        root.addView(connect, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        connect.setOnClickListener(v -> {
            endpoint = endpointField.getText().toString().trim();
            token = tokenField.getText().toString().trim();
            prefs.edit().putString("endpoint", endpoint).putString("token", token).apply();
            loadProjects();
        });
    }

    private void loadProjects() {
        setStatus("Loading Artificer...");
        new Thread(() -> {
            try {
                JSONObject health = new JSONObject(request("GET", "/health", null));
                JSONObject list = new JSONObject(request("GET", "/projects", null));
                projects = list.optJSONArray("projects");
                if (projects == null) projects = new JSONArray();
                runOnUiThread(() -> showProjects(health));
            } catch (Exception ex) {
                runOnUiThread(() -> {
                    showConnect();
                    setStatus(ex.getMessage());
                });
            }
        }).start();
    }

    private void showProjects(JSONObject health) {
        base("Artificer");
        String model = health.optJSONObject("runtime") == null ? "" : health.optJSONObject("runtime").optString("default_model", "");
        setStatus(model.length() > 0 ? "Model: " + model : "Bridge connected");
        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list);
        for (int i = 0; i < projects.length(); i++) {
            JSONObject project = projects.optJSONObject(i);
            if (project == null) continue;
            Button row = button(project.optString("name", project.optString("id", "Workspace")));
            row.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
            row.setOnClickListener(v -> {
                selectedProject = project;
                loadSessions(project.optString("id", ""));
            });
            list.addView(row, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
    }

    private void loadSessions(String workspaceId) {
        setStatus("Loading chats...");
        new Thread(() -> {
            try {
                JSONObject list = new JSONObject(request("GET", "/sessions?workspace_id=" + enc(workspaceId), null));
                sessions = list.optJSONArray("sessions");
                if (sessions == null) sessions = new JSONArray();
                runOnUiThread(this::showSessions);
            } catch (Exception ex) {
                setStatus(ex.getMessage());
            }
        }).start();
    }

    private String enc(String value) {
        try { return java.net.URLEncoder.encode(value, "UTF-8"); } catch (Exception ex) { return ""; }
    }

    private void showSessions() {
        base(selectedProject.optString("name", "Chats"));
        Button back = button("Back");
        back.setOnClickListener(v -> showProjects(new JSONObject()));
        root.addView(back, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list);
        for (int i = 0; i < sessions.length(); i++) {
            JSONObject session = sessions.optJSONObject(i);
            if (session == null) continue;
            Button row = button(session.optString("title", session.optString("id", "Chat")));
            row.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL);
            row.setOnClickListener(v -> {
                selectedSession = session;
                loadSession();
            });
            list.addView(row, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
    }

    private void loadSession() {
        setStatus("Loading thread...");
        String workspaceId = selectedProject.optString("id", "");
        String conversationId = selectedSession.optString("id", "");
        new Thread(() -> {
            try {
                sessionDetail = new JSONObject(request("GET", "/session?workspace_id=" + enc(workspaceId) + "&conversation_id=" + enc(conversationId), null)).optJSONObject("session");
                runOnUiThread(this::showChat);
            } catch (Exception ex) {
                setStatus(ex.getMessage());
            }
        }).start();
    }

    private void showChat() {
        base(selectedSession.optString("title", "Chat"));
        Button back = button("Chats");
        back.setOnClickListener(v -> showSessions());
        root.addView(back, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        ScrollView scroll = new ScrollView(this);
        LinearLayout messages = new LinearLayout(this);
        messages.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(messages);
        JSONArray items = sessionDetail == null ? new JSONArray() : sessionDetail.optJSONArray("messages");
        if (items == null) items = new JSONArray();
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) continue;
            TextView bubble = text(item.optString("role", "message") + "\n" + item.optString("content", ""), 14, Typeface.NORMAL);
            bubble.setPadding(12, 10, 12, 10);
            messages.addView(bubble, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        EditText composer = input("Message Artificer", "");
        Button send = button("Send");
        LinearLayout compose = new LinearLayout(this);
        compose.setOrientation(LinearLayout.HORIZONTAL);
        compose.addView(composer, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        compose.addView(send, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(compose);
        send.setOnClickListener(v -> sendMessage(composer.getText().toString()));
    }

    private void sendMessage(String prompt) {
        if (prompt.trim().isEmpty()) return;
        setStatus("Sending...");
        new Thread(() -> {
            try {
                JSONObject body = new JSONObject();
                body.put("workspace_id", selectedProject.optString("id", ""));
                body.put("conversation_id", selectedSession.optString("id", ""));
                body.put("prompt", prompt);
                body.put("run_after", true);
                request("POST", "/message", body);
                loadSession();
            } catch (Exception ex) {
                setStatus(ex.getMessage());
            }
        }).start();
    }
}
JAVA

cat >"$ios_dir/project.yml" <<YAML
name: $app_id-native-mobile
options:
  bundleIdPrefix: app.wizardry.artificer
targets:
  ArtificerMobile:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - Host
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: $ios_bundle
      INFOPLIST_KEY_CFBundleDisplayName: "$app_name"
      CURRENT_PROJECT_VERSION: "$version_code"
      MARKETING_VERSION: "$app_version"
YAML

cat >"$ios_dir/Host/App.swift" <<'SWIFT'
import SwiftUI

@main
struct ArtificerMobileApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
SWIFT

cat >"$ios_dir/Host/ContentView.swift" <<'SWIFT'
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
SWIFT

cat >"$generated_root/README.md" <<README
# $app_name Native Mobile Build

Generated from \`app-blueprint/mobile.ir.yaml\`.

- Android output is a plain Gradle Android project with no Play Services dependency.
- iOS output is a SwiftUI project generated through XcodeGen.
- The app is a thin client for the Artificer Mobile bridge exposed by desktop Preferences.
README

printf 'status=ok\n'
printf 'ir=%s\n' "$ir_path"
printf 'android=%s\n' "$android_dir"
printf 'ios=%s\n' "$ios_dir"
