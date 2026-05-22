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
        TextView view = text(first + "\n" + second, 11, Typeface.NORMAL);
        view.setGravity(Gravity.RIGHT | Gravity.CENTER_VERTICAL);
        view.setLines(2);
        view.setMaxWidth(230);
        view.setEllipsize(TextUtils.TruncateAt.END);
        view.setTextColor(Color.rgb(38, 68, 70));
        view.setPadding(10, 6, 10, 6);
        view.setBackground(rounded(Color.rgb(232, 241, 239), Color.rgb(179, 211, 207), 14));
        return view;
    }

    private void base(String screenTitle) {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(22, 18, 22, 14);
        root.setBackgroundColor(bg);
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        title = text(screenTitle, 22, Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        header.addView(contextWindow(), new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        status = text("", 12, Typeface.NORMAL);
        status.setTextColor(Color.rgb(100, 92, 82));
        root.addView(header, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
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
        TextView hint = text("Pair this phone with the Mobile tab in Artificer Preferences.", 14, Typeface.NORMAL);
        hint.setTextColor(Color.rgb(83, 78, 71));
        hint.setPadding(0, 12, 0, 8);
        root.addView(hint);
        TextView steps = text("1. Enable Mobile bridge\n2. Copy the bridge URL\n3. Copy the pairing token", 13, Typeface.NORMAL);
        steps.setTextColor(Color.rgb(83, 78, 71));
        steps.setPadding(12, 10, 12, 10);
        steps.setBackground(rounded(Color.rgb(239, 235, 226), line, 12));
        root.addView(steps, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
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
        loadingHome = true;
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
        controls.addView(refresh, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(controls);
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
        TextView view = text(heading + "\n" + detail, 14, Typeface.NORMAL);
        view.setTextColor(Color.rgb(83, 78, 71));
        view.setPadding(14, 18, 14, 18);
        view.setGravity(Gravity.CENTER);
        view.setBackground(rounded(Color.rgb(239, 235, 226), line, 12));
        list.addView(view, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    private void noteRow(LinearLayout list, String value) {
        TextView view = text("    " + value, 13, Typeface.NORMAL);
        view.setTextColor(Color.rgb(100, 92, 82));
        view.setPadding(12, 8, 12, 8);
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
        if (count >= 0) label += "  " + count;
        TextView row = text(label, 16, Typeface.BOLD);
        row.setPadding(12, 12, 12, 8);
        row.setBackground(rounded(Color.rgb(250, 248, 242), line, 10));
        row.setOnClickListener(v -> toggleProject(project));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, 8, 0, 2);
        list.addView(row, params);
    }

    private void addChatRow(LinearLayout list, JSONObject project, JSONObject session) {
        String title = session.optString("title", session.optString("id", "Chat"));
        String detail = sessionDetailLine(session);
        TextView row = text("    " + title + (detail.length() > 0 ? "\n      " + detail : ""), 14, Typeface.NORMAL);
        row.setPadding(12, 10, 12, 10);
        row.setBackground(rounded(Color.rgb(255, 253, 247), 0, 8));
        row.setOnClickListener(v -> {
            selectedProject = project;
            selectedSession = session;
            loadSession();
        });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(12, 2, 0, 2);
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
            expandedProjectIds.remove(projectId);
            renderTree();
            return;
        }
        expandedProjectIds.add(projectId);
        if (!sessionsByProject.containsKey(projectId)) {
            selectedProject = project;
            loadSessions(projectId);
        } else {
            renderTree();
        }
    }

    private void loadSessions(String workspaceId) {
        loadingProjectIds.add(workspaceId);
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
                setStatus(ex.getMessage());
                runOnUiThread(this::renderTree);
            }
        }).start();
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
        back.setOnClickListener(v -> showHome());
        root.addView(back, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
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
            TextView bubble = text(item.optString("role", "message") + "\n" + item.optString("content", ""), 14, Typeface.NORMAL);
            bubble.setPadding(12, 10, 12, 10);
            bubble.setBackground(rounded(Color.rgb(255, 253, 247), line, 10));
            LinearLayout.LayoutParams bubbleParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            bubbleParams.setMargins(0, 4, 0, 6);
            messages.addView(bubble, bubbleParams);
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
