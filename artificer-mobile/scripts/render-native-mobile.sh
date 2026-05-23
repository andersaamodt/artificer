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
import android.graphics.drawable.GradientDrawable;
import android.content.SharedPreferences;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
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
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import org.json.JSONArray;
import org.json.JSONObject;

public final class MainActivity extends Activity {
    private LinearLayout root;
    private SharedPreferences prefs;
    private String endpoint = "";
    private String token = "";
    private JSONArray projects = new JSONArray();
    private HashMap<String, JSONArray> sessionsByProject = new HashMap<>();
    private HashMap<String, String> folderErrors = new HashMap<>();
    private HashSet<String> expandedProjectIds = new HashSet<>();
    private HashSet<String> loadingProjectIds = new HashSet<>();
    private JSONObject runtime = new JSONObject();
    private JSONObject selectedProject;
    private JSONObject selectedSession;
    private JSONObject sessionDetail;
    private TextView title;
    private TextView status;
    private String query = "";
    private String lastUpdated = "";
    private boolean connected = false;
    private boolean loadingHome = false;
    private int bg = Color.rgb(247, 244, 237);
    private int ink = Color.rgb(31, 35, 36);
    private int line = Color.rgb(212, 205, 193);
    private int accent = Color.rgb(29, 109, 115);
    private int rootPadX;
    private int rootPadTop;
    private int rootPadBottom;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("artificer-mobile", MODE_PRIVATE);
        endpoint = prefs.getString("endpoint", "");
        token = prefs.getString("token", "");
        if (endpoint.trim().length() > 0 && token.trim().length() > 0) {
            loadProjects();
        } else {
            showConnect();
        }
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
        view.setTextSize(16);
        view.setAllCaps(false);
        view.setMinHeight(dp(44));
        view.setMinWidth(dp(96));
        view.setPadding(dp(16), 0, dp(16), 0);
        view.setTextColor(Color.WHITE);
        view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setBackground(rounded(accent, 0, dp(10)));
        return view;
    }

    private EditText input(String hint, String value) {
        EditText view = new EditText(this);
        view.setHint(hint);
        view.setText(value);
        view.setTextSize(16);
        view.setTextColor(ink);
        view.setHintTextColor(Color.rgb(116, 108, 96));
        view.setSingleLine(false);
        view.setMinLines(1);
        view.setMinHeight(dp(48));
        view.setPadding(dp(12), 0, dp(12), 0);
        view.setBackground(rounded(Color.rgb(255, 253, 247), line, dp(10)));
        view.setImeOptions(EditorInfo.IME_ACTION_DONE);
        return view;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private GradientDrawable rounded(int color, int strokeColor, int radius) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(radius);
        if (strokeColor != 0) shape.setStroke(1, strokeColor);
        return shape;
    }

    private TextView contextWindow() {
        String model = runtime.optString("default_model", "");
        int count = runtime.optInt("installed_model_count", 0);
        String first = model.length() > 0 ? model : (connected ? "Connected" : "Not connected");
        String second = count > 0 ? count + " models" : (lastUpdated.length() > 0 ? lastUpdated : "Bridge");
        TextView view = text(first + "\n" + second, 12, Typeface.NORMAL);
        view.setGravity(Gravity.RIGHT | Gravity.CENTER_VERTICAL);
        view.setLines(2);
        view.setMaxWidth(dp(180));
        view.setEllipsize(TextUtils.TruncateAt.END);
        view.setTextColor(Color.rgb(38, 68, 70));
        view.setPadding(dp(10), dp(7), dp(10), dp(7));
        view.setBackground(rounded(Color.rgb(232, 241, 239), Color.rgb(179, 211, 207), dp(10)));
        return view;
    }

    private void applyRootInsets() {
        rootPadX = dp(22);
        rootPadTop = dp(22);
        rootPadBottom = dp(16);
        root.setPadding(rootPadX, rootPadTop, rootPadX, rootPadBottom);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(
                rootPadX + insets.getSystemWindowInsetLeft(),
                rootPadTop + insets.getSystemWindowInsetTop(),
                rootPadX + insets.getSystemWindowInsetRight(),
                rootPadBottom + insets.getSystemWindowInsetBottom()
            );
            return insets;
        });
        root.requestApplyInsets();
    }

    private void base(String screenTitle) {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(bg);
        applyRootInsets();
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        title = text(screenTitle, 24, Typeface.BOLD);
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        header.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        header.addView(contextWindow(), new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        status = text("", 13, Typeface.NORMAL);
        status.setTextColor(Color.rgb(100, 92, 82));
        root.addView(header, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(status, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);
        root.requestApplyInsets();
    }

    private void setStatus(String value) {
        if (status == null) return;
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
        if (stream == null) throw new Exception("Bridge request failed");
        BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
        StringBuilder out = new StringBuilder();
        String lineValue;
        while ((lineValue = reader.readLine()) != null) out.append(lineValue);
        reader.close();
        return out.toString();
    }

    private void showConnect() {
        base("Artificer Mobile");
        TextView hint = text("Pair this phone with the Mobile tab in Artificer Preferences.", 16, Typeface.NORMAL);
        hint.setTextColor(Color.rgb(83, 78, 71));
        hint.setPadding(0, dp(16), 0, dp(10));
        root.addView(hint);
        TextView steps = text("1. Enable Mobile bridge\n2. Copy the bridge URL\n3. Copy the pairing token", 15, Typeface.NORMAL);
        steps.setTextColor(Color.rgb(83, 78, 71));
        steps.setPadding(dp(14), dp(12), dp(14), dp(12));
        steps.setBackground(rounded(Color.rgb(239, 235, 226), line, dp(10)));
        root.addView(steps, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        EditText endpointField = input("http://192.168.1.20:8765", endpoint);
        EditText tokenField = input("Pairing token", token);
        LinearLayout.LayoutParams fieldParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        fieldParams.setMargins(0, dp(12), 0, 0);
        root.addView(endpointField, fieldParams);
        LinearLayout.LayoutParams tokenParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        tokenParams.setMargins(0, dp(10), 0, 0);
        root.addView(tokenField, tokenParams);
        Button connect = button("Connect");
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        buttonParams.setMargins(0, dp(14), 0, 0);
        root.addView(connect, buttonParams);
        connect.setOnClickListener(v -> {
            endpoint = endpointField.getText().toString().trim();
            token = tokenField.getText().toString().trim();
            if (endpoint.length() == 0 || token.length() == 0) {
                setStatus("Bridge URL and pairing token are required.");
                return;
            }
            prefs.edit().putString("endpoint", endpoint).putString("token", token).apply();
            loadProjects();
        });
    }

    private void loadProjects() {
        if (endpoint.trim().length() == 0 || token.trim().length() == 0) {
            showConnect();
            setStatus("Bridge URL and pairing token are required.");
            return;
        }
        loadingHome = true;
        if (status == null) base("Artificer");
        setStatus("Loading Artificer...");
        new Thread(() -> {
            try {
                JSONObject health = new JSONObject(request("GET", "/health", null));
                JSONObject list = new JSONObject(request("GET", "/projects", null));
                runtime = health.optJSONObject("runtime") == null ? new JSONObject() : health.optJSONObject("runtime");
                projects = list.optJSONArray("projects");
                if (projects == null) projects = new JSONArray();
                connected = true;
                lastUpdated = new SimpleDateFormat("h:mm a", Locale.US).format(new Date());
                loadingHome = false;
                folderErrors.clear();
                runOnUiThread(this::showHome);
            } catch (Exception ex) {
                loadingHome = false;
                runOnUiThread(() -> {
                    showConnect();
                    setStatus(ex.getMessage());
                });
            }
        }).start();
    }

    private void showHome() {
        base("Artificer");
        setStatus(loadingHome ? "Refreshing..." : (lastUpdated.length() > 0 ? "Updated " + lastUpdated : "Connected"));
        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.HORIZONTAL);
        controls.setGravity(Gravity.CENTER_VERTICAL);
        EditText search = input("Search folders and chats", query);
        search.setSingleLine(true);
        search.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                query = s.toString();
                renderTree();
            }
            public void afterTextChanged(Editable s) {}
        });
        Button refresh = button("Refresh");
        refresh.setOnClickListener(v -> loadProjects());
        controls.addView(search, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        LinearLayout.LayoutParams refreshParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        refreshParams.setMargins(dp(10), 0, 0, 0);
        controls.addView(refresh, refreshParams);
        LinearLayout.LayoutParams controlsParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        controlsParams.setMargins(0, dp(12), 0, dp(8));
        root.addView(controls, controlsParams);
        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setId(1001);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list);
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        renderTree();
    }

    private void renderTree() {
        LinearLayout list = (LinearLayout)findViewById(1001);
        if (list == null) return;
        list.removeAllViews();
        if (projects.length() == 0) {
            emptyState(list, "No folders", "No existing Artificer workspaces were returned by the bridge.");
            return;
        }
        int visible = 0;
        for (int i = 0; i < projects.length(); i++) {
            JSONObject project = projects.optJSONObject(i);
            if (project == null) continue;
            if (!matchesProject(project)) continue;
            visible++;
            addFolderRow(list, project);
            String projectId = project.optString("id", "");
            if (expandedProjectIds.contains(projectId) || (query.trim().length() > 0 && sessionsByProject.containsKey(projectId))) {
                if (loadingProjectIds.contains(projectId)) {
                    noteRow(list, "Loading chats...");
                } else if (folderErrors.containsKey(projectId)) {
                    noteRow(list, "Could not load chats. Tap folder to retry.");
                } else {
                    JSONArray sessions = sessionsByProject.get(projectId);
                    if (sessions == null) {
                        noteRow(list, "Tap folder again if chats do not appear.");
                    } else if (sessions.length() == 0) {
                        noteRow(list, "No chats in this folder.");
                    } else {
                        int shown = 0;
                        for (int j = 0; j < sessions.length(); j++) {
                            JSONObject session = sessions.optJSONObject(j);
                            if (session == null || !matchesSession(session, project)) continue;
                            shown++;
                            addChatRow(list, project, session);
                        }
                        if (shown == 0) noteRow(list, "No chats match the search.");
                    }
                }
            }
        }
        if (visible == 0) {
            emptyState(list, "No matches", "No folder or loaded chat matches the current search.");
        }
    }

    private void emptyState(LinearLayout list, String heading, String detail) {
        TextView view = text(heading + "\n" + detail, 15, Typeface.NORMAL);
        view.setTextColor(Color.rgb(83, 78, 71));
        view.setPadding(dp(14), dp(18), dp(14), dp(18));
        view.setGravity(Gravity.CENTER);
        view.setBackground(rounded(Color.rgb(239, 235, 226), line, dp(10)));
        list.addView(view, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    private void noteRow(LinearLayout list, String value) {
        TextView view = text("    " + value, 14, Typeface.NORMAL);
        view.setTextColor(Color.rgb(100, 92, 82));
        view.setPadding(dp(12), dp(8), dp(12), dp(8));
        list.addView(view);
    }

    private boolean matchesProject(JSONObject project) {
        String q = query.trim().toLowerCase(Locale.US);
        if (q.length() == 0) return true;
        if (project.optString("name", "").toLowerCase(Locale.US).contains(q)) return true;
        JSONArray sessions = sessionsByProject.get(project.optString("id", ""));
        if (sessions == null) return false;
        for (int i = 0; i < sessions.length(); i++) {
            if (matchesSession(sessions.optJSONObject(i), project)) return true;
        }
        return false;
    }

    private boolean matchesSession(JSONObject session, JSONObject project) {
        if (session == null) return false;
        String q = query.trim().toLowerCase(Locale.US);
        if (q.length() == 0) return true;
        return session.optString("title", session.optString("id", "")).toLowerCase(Locale.US).contains(q)
            || project.optString("name", "").toLowerCase(Locale.US).contains(q);
    }

    private void addFolderRow(LinearLayout list, JSONObject project) {
        String projectId = project.optString("id", "");
        boolean expanded = expandedProjectIds.contains(projectId);
        String label = (expanded ? "v " : "> ") + project.optString("name", projectId);
        int count = project.optInt("session_count", -1);
        if (count >= 0) label += "  " + count + " chats";
        TextView row = text(label, 17, Typeface.BOLD);
        row.setPadding(dp(12), dp(13), dp(12), dp(10));
        row.setBackground(rounded(Color.rgb(250, 248, 242), line, dp(10)));
        row.setOnClickListener(v -> toggleProject(project));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, dp(8), 0, dp(2));
        list.addView(row, params);
    }

    private void addChatRow(LinearLayout list, JSONObject project, JSONObject session) {
        String title = session.optString("title", session.optString("id", "Chat"));
        String detail = sessionDetailLine(session);
        TextView row = text("    " + title + (detail.length() > 0 ? "\n      " + detail : ""), 15, Typeface.NORMAL);
        row.setPadding(dp(12), dp(11), dp(12), dp(11));
        row.setBackground(rounded(Color.rgb(255, 253, 247), 0, dp(8)));
        row.setOnClickListener(v -> {
            selectedProject = project;
            selectedSession = session;
            loadSession();
        });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(dp(12), dp(2), 0, dp(2));
        list.addView(row, params);
    }

    private String sessionDetailLine(JSONObject session) {
        StringBuilder detail = new StringBuilder();
        String modelName = session.optString("model", "");
        if (modelName.length() > 0) detail.append(modelName);
        String updated = formatUpdated(session.optLong("updated", 0));
        if (updated.length() > 0) {
            if (detail.length() > 0) detail.append(" - ");
            detail.append(updated);
        }
        String queue = queueText(session);
        if (queue.length() > 0) {
            if (detail.length() > 0) detail.append(" - ");
            detail.append(queue);
        }
        return detail.toString();
    }

    private String formatUpdated(long updated) {
        if (updated <= 0) return "";
        long millis = updated < 100000000000L ? updated * 1000L : updated;
        return new SimpleDateFormat("MMM d, h:mm a", Locale.US).format(new Date(millis));
    }

    private String queueText(JSONObject session) {
        JSONObject queue = session.optJSONObject("queue");
        if (queue == null) return "";
        int running = queue.optInt("running", 0);
        int pending = queue.optInt("pending", 0);
        int done = queue.optInt("done", 0);
        if (running > 0) return "running " + running;
        if (pending > 0) return "queued " + pending;
        if (done > 0) return "done " + done;
        return "";
    }

    private void toggleProject(JSONObject project) {
        String projectId = project.optString("id", "");
        if (expandedProjectIds.contains(projectId)) {
            if (folderErrors.containsKey(projectId)) {
                loadSessions(projectId);
                return;
            }
            expandedProjectIds.remove(projectId);
            renderTree();
            return;
        }
        expandedProjectIds.add(projectId);
        if (!sessionsByProject.containsKey(projectId) || folderErrors.containsKey(projectId)) {
            selectedProject = project;
            loadSessions(projectId);
        } else {
            renderTree();
        }
    }

    private void loadSessions(String workspaceId) {
        loadingProjectIds.add(workspaceId);
        folderErrors.remove(workspaceId);
        renderTree();
        new Thread(() -> {
            try {
                JSONObject list = new JSONObject(request("GET", "/sessions?workspace_id=" + enc(workspaceId), null));
                JSONArray sessions = list.optJSONArray("sessions");
                if (sessions == null) sessions = new JSONArray();
                sessionsByProject.put(workspaceId, sessions);
                loadingProjectIds.remove(workspaceId);
                runOnUiThread(this::renderTree);
            } catch (Exception ex) {
                loadingProjectIds.remove(workspaceId);
                folderErrors.put(workspaceId, ex.getMessage());
                setStatus(ex.getMessage());
                runOnUiThread(this::renderTree);
            }
        }).start();
    }

    private void slideIn(int direction) {
        root.post(() -> {
            int width = root.getWidth();
            if (width <= 0) return;
            root.setTranslationX(direction * width);
            root.animate().translationX(0).setDuration(180).start();
        });
    }

    private String enc(String value) {
        try { return java.net.URLEncoder.encode(value, "UTF-8"); } catch (Exception ex) { return ""; }
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
        Button back = button("Folders");
        back.setOnClickListener(v -> {
            showHome();
            slideIn(-1);
        });
        root.addView(back, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        String chatDetail = sessionDetailLine(selectedSession);
        if (chatDetail.length() > 0) noteRow(root, chatDetail);
        ScrollView scroll = new ScrollView(this);
        LinearLayout messages = new LinearLayout(this);
        messages.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(messages);
        JSONArray items = sessionDetail == null ? new JSONArray() : sessionDetail.optJSONArray("messages");
        if (items == null) items = new JSONArray();
        if (items.length() == 0) {
            emptyState(messages, "No messages", "This chat has no visible transcript yet.");
        }
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) continue;
            TextView bubble = text(item.optString("role", "message") + "\n" + item.optString("content", ""), 15, Typeface.NORMAL);
            bubble.setPadding(dp(12), dp(11), dp(12), dp(11));
            bubble.setBackground(rounded(Color.rgb(255, 253, 247), line, dp(10)));
            LinearLayout.LayoutParams bubbleParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            bubbleParams.setMargins(0, dp(4), 0, dp(6));
            messages.addView(bubble, bubbleParams);
        }
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        EditText composer = input("Message Artificer", "");
        Button send = button("Send");
        LinearLayout compose = new LinearLayout(this);
        compose.setOrientation(LinearLayout.HORIZONTAL);
        compose.addView(composer, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        LinearLayout.LayoutParams sendParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        sendParams.setMargins(dp(10), 0, 0, 0);
        compose.addView(send, sendParams);
        LinearLayout.LayoutParams composeParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        composeParams.setMargins(0, dp(10), 0, 0);
        root.addView(compose, composeParams);
        send.setOnClickListener(v -> sendMessage(composer.getText().toString()));
        slideIn(1);
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
      GENERATE_INFOPLIST_FILE: YES
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

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = (try? container.decode(String.self, forKey: .role)) ?? "message"
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
    }
}

struct SessionDetail: Codable {
    let id: String
    let title: String
    let model: String
    let updated: Int
    let queue: QueueState
    let messages: [BridgeMessage]

    enum CodingKeys: String, CodingKey {
        case id, title, model, updated, queue, messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        title = (try? container.decode(String.self, forKey: .title)) ?? id
        model = (try? container.decode(String.self, forKey: .model)) ?? ""
        updated = (try? container.decode(Int.self, forKey: .updated)) ?? 0
        queue = (try? container.decode(QueueState.self, forKey: .queue)) ?? .empty
        messages = (try? container.decode([BridgeMessage].self, forKey: .messages)) ?? []
    }
}

@MainActor
final class BridgeModel: ObservableObject {
    @AppStorage("bridgeEndpoint") var endpoint = ""
    @AppStorage("bridgeToken") var token = ""
    @Published var projects: [BridgeProject] = []
    @Published var sessionsByProject: [String: [BridgeSession]] = [:]
    @Published var expandedProjectIDs: Set<String> = []
    @Published var loadingProjectIDs: Set<String> = []
    @Published var folderErrors: [String: String] = [:]
    @Published var selectedProject: BridgeProject?
    @Published var selectedSession: BridgeSession?
    @Published var detail: SessionDetail?
    @Published var runtime: RuntimeHealth?
    @Published var status = "Not connected"
    @Published var draft = ""
    @Published var query = ""
    @Published var isRefreshing = false
    @Published var isSending = false
    @Published var lastUpdated = ""

    func connect() async {
        await refresh()
    }

    func autoConnectIfPossible() async {
        guard projects.isEmpty, !isRefreshing, hasPairingDetails else { return }
        await refresh()
    }

    func refresh() async {
        guard hasPairingDetails else {
            status = "Bridge URL and pairing token are required."
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            status = "Loading Artificer..."
            let healthPayload = try await get("/health")
            runtime = (try? JSONDecoder().decode(HealthResponse.self, from: healthPayload).runtime)
            let payload = try await get("/projects")
            projects = (try? JSONDecoder().decode(ProjectList.self, from: payload).projects) ?? []
            projects = projects.filter(\.pathExists)
            sessionsByProject = sessionsByProject.filter { key, _ in projects.contains { $0.id == key } }
            expandedProjectIDs = expandedProjectIDs.filter { id in projects.contains { $0.id == id } }
            folderErrors = folderErrors.filter { key, _ in projects.contains { $0.id == key } }
            lastUpdated = Self.timeFormatter.string(from: Date())
            status = projects.isEmpty ? "No folders returned" : "\(projects.count) folders"
        } catch {
            status = error.localizedDescription
        }
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
        folderErrors[project.id] = nil
        do {
            let payload = try await get("/sessions?workspace_id=\(project.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
            let sessions = (try? JSONDecoder().decode(SessionList.self, from: payload).sessions) ?? []
            sessionsByProject[project.id] = sessions
            status = "\(sessions.count) chats in \(project.name)"
        } catch {
            folderErrors[project.id] = error.localizedDescription
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
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true
        defer { isSending = false }
        do {
            status = "Sending..."
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

    func queueColor(_ session: BridgeSession) -> Color {
        if session.queue.running > 0 { return .green }
        if session.queue.pending > 0 { return .orange }
        if session.queue.done > 0 { return .blue }
        return .secondary
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

    private var hasPairingDetails: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct HealthResponse: Codable {
    let runtime: RuntimeHealth

    enum CodingKeys: String, CodingKey {
        case runtime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtime = (try? container.decode(RuntimeHealth.self, forKey: .runtime)) ?? RuntimeHealth()
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
            .task { await model.autoConnectIfPossible() }
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
        .padding(.top, 26)
        .padding(.bottom, 10)
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
                .font(.body)
                .textFieldStyle(.roundedBorder)
            SecureField("Pairing token", text: $model.token)
                .font(.body)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(model.projects.isEmpty ? "Connect" : "Refresh") { Task { await model.refresh() } }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
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
        .frame(maxWidth: 158, alignment: .trailing)
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
            } else if let error = model.folderErrors[project.id] {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Could not load chats")
                        .font(.caption.bold())
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("Retry") { Task { await model.ensureSessions(project) } }
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
                        .foregroundStyle(model.queueColor(session))
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
                            .foregroundStyle(model.queueColor(session))
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
                .refreshable { await model.open(session) }
            composer
        }
        .navigationTitle(session.title.isEmpty ? "Chat" : session.title)
        .task {
            model.selectedProject = project
            await model.open(session)
        }
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
                .font(.body)
            Button {
                Task { await model.send() }
            } label: {
                if model.isSending {
                    ProgressView()
                } else {
                    Text("Send")
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.body.weight(.semibold))
            .controlSize(.regular)
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
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
