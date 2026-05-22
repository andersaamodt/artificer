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
