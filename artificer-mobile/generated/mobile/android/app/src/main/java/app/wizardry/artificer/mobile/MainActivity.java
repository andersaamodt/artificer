package app.wizardry.artificer.mobile;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
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
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
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
    private String connectionMode = "ip";
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
    private boolean checkingUpdate = false;
    private boolean downloadingUpdate = false;
    private boolean updateDownloaded = false;
    private String updateStatus = "";
    private String updateTag = "";
    private String updateAssetName = "";
    private String updateAssetUrl = "";
    private String updateReleaseUrl = "";
    private String updateApkPath = "";
    private TextView updatePill;
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
        connectionMode = prefs.getString("connection_mode", "ip");
        updateTag = prefs.getString("update_tag", "");
        updateAssetName = prefs.getString("update_asset_name", "");
        updateAssetUrl = prefs.getString("update_asset_url", "");
        updateReleaseUrl = prefs.getString("update_release_url", "");
        updateApkPath = prefs.getString("update_apk_path", "");
        updateDownloaded = updateApkPath.length() > 0 && new File(updateApkPath).isFile();
        checkForUpdate(true);
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

    private TextView updatePill() {
        TextView view = text("Update", 13, Typeface.BOLD);
        view.setTextColor(Color.WHITE);
        view.setGravity(Gravity.CENTER);
        view.setPadding(dp(12), dp(7), dp(12), dp(7));
        view.setMinWidth(dp(78));
        view.setBackground(rounded(Color.rgb(28, 104, 219), 0, dp(100)));
        view.setVisibility(updateDownloaded ? View.VISIBLE : View.GONE);
        view.setOnClickListener(v -> installDownloadedUpdate());
        return view;
    }

    private void refreshUpdatePill() {
        if (updatePill == null) return;
        updatePill.setVisibility(updateDownloaded ? View.VISIBLE : View.GONE);
        updatePill.setText(updateDownloaded ? "Update" : "");
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
        updatePill = updatePill();
        LinearLayout.LayoutParams updateParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        updateParams.setMargins(dp(8), 0, dp(8), 0);
        header.addView(updatePill, updateParams);
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

    private void checkForUpdate(boolean autoDownload) {
        if (checkingUpdate) return;
        checkingUpdate = true;
        updateStatus = "Checking for update...";
        new Thread(() -> {
            try {
                JSONObject release = latestRelease();
                String tag = release.optString("tag_name", "");
                String htmlUrl = release.optString("html_url", "");
                JSONObject asset = selectAndroidApkAsset(release.optJSONArray("assets"));
                if (tag.length() == 0 || asset == null || !isNewerRelease(tag)) {
                    updateDownloaded = false;
                    updateApkPath = "";
                    prefs.edit()
                        .remove("update_tag")
                        .remove("update_asset_name")
                        .remove("update_asset_url")
                        .remove("update_release_url")
                        .remove("update_apk_path")
                        .apply();
                    checkingUpdate = false;
                    runOnUiThread(this::refreshUpdatePill);
                    return;
                }
                String assetName = asset.optString("name", "");
                String assetUrl = asset.optString("browser_download_url", "");
                validateGithubUpdateAsset(assetName, assetUrl);
                updateTag = tag;
                updateAssetName = assetName;
                updateAssetUrl = assetUrl;
                updateReleaseUrl = htmlUrl;
                updateDownloaded = updateApkPath.length() > 0 && new File(updateApkPath).isFile() && assetName.equals(new File(updateApkPath).getName());
                prefs.edit()
                    .putString("update_tag", updateTag)
                    .putString("update_asset_name", updateAssetName)
                    .putString("update_asset_url", updateAssetUrl)
                    .putString("update_release_url", updateReleaseUrl)
                    .apply();
                if (!updateDownloaded && autoDownload) {
                    downloadUpdateApk(assetName, assetUrl);
                }
                checkingUpdate = false;
                runOnUiThread(this::refreshUpdatePill);
            } catch (Exception ex) {
                checkingUpdate = false;
                downloadingUpdate = false;
                updateStatus = ex.getMessage();
            }
        }).start();
    }

    private JSONObject latestRelease() throws Exception {
        HttpURLConnection conn = (HttpURLConnection)new URL("https://api.github.com/repos/andersaamodt/artificer/releases/latest").openConnection();
        conn.setRequestMethod("GET");
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(20000);
        conn.setRequestProperty("Accept", "application/vnd.github+json");
        InputStream stream = conn.getResponseCode() >= 400 ? conn.getErrorStream() : conn.getInputStream();
        if (stream == null) throw new Exception("GitHub latest release could not be loaded.");
        BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
        StringBuilder out = new StringBuilder();
        String lineValue;
        while ((lineValue = reader.readLine()) != null) out.append(lineValue);
        reader.close();
        if (conn.getResponseCode() >= 400) throw new Exception("GitHub latest release could not be loaded.");
        return new JSONObject(out.toString());
    }

    private JSONObject selectAndroidApkAsset(JSONArray assets) {
        if (assets == null) return null;
        for (int i = 0; i < assets.length(); i++) {
            JSONObject asset = assets.optJSONObject(i);
            if (asset == null) continue;
            String lower = asset.optString("name", "").toLowerCase(Locale.US);
            if (lower.endsWith(".apk") && lower.contains("artificer-mobile")) return asset;
        }
        return null;
    }

    private boolean isNewerRelease(String tag) {
        String current = currentVersionName();
        return tag.length() > 0 && !tag.equals(current) && !tag.equals("v" + current);
    }

    private String currentVersionName() {
        try {
            PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            return info.versionName == null ? "" : info.versionName;
        } catch (Exception ex) {
            return "";
        }
    }

    private void validateGithubUpdateAsset(String name, String url) throws Exception {
        if (name.length() == 0 || name.contains("/") || name.contains("\\") || name.contains("\n") || name.contains("\r") || !name.toLowerCase(Locale.US).endsWith(".apk")) {
            throw new Exception("GitHub release asset name is not safe to install.");
        }
        String prefix = "https://github.com/andersaamodt/artificer/releases/download/";
        if (!url.startsWith(prefix) || url.contains("\n") || url.contains("\r")) {
            throw new Exception("GitHub release asset URL is not safe to download.");
        }
    }

    private void downloadUpdateApk(String assetName, String assetUrl) throws Exception {
        if (downloadingUpdate) return;
        downloadingUpdate = true;
        updateStatus = "Downloading update...";
        File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (dir == null) dir = new File(getCacheDir(), "updates");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new Exception("Update download folder could not be created.");
        File target = new File(dir, assetName);
        File part = new File(dir, assetName + ".part");
        HttpURLConnection conn = (HttpURLConnection)new URL(assetUrl).openConnection();
        conn.setConnectTimeout(10000);
        conn.setReadTimeout(30000);
        conn.setRequestProperty("Accept", "application/octet-stream");
        if (conn.getResponseCode() >= 400) throw new Exception("Update APK could not be downloaded.");
        InputStream input = conn.getInputStream();
        FileOutputStream output = new FileOutputStream(part);
        byte[] buffer = new byte[65536];
        int read;
        while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
        output.close();
        input.close();
        if (target.exists() && !target.delete()) throw new Exception("Old update APK could not be replaced.");
        if (!part.renameTo(target)) throw new Exception("Update APK could not be staged.");
        updateApkPath = target.getAbsolutePath();
        updateDownloaded = true;
        downloadingUpdate = false;
        updateStatus = "Update downloaded.";
        prefs.edit().putString("update_apk_path", updateApkPath).apply();
    }

    private void installDownloadedUpdate() {
        if (updateApkPath.length() == 0 || !new File(updateApkPath).isFile()) {
            updateDownloaded = false;
            refreshUpdatePill();
            setStatus("The update is no longer downloaded.");
            checkForUpdate(true);
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !getPackageManager().canRequestPackageInstalls()) {
            Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName()));
            startActivity(settings);
            setStatus("Enable this source, then tap Update again.");
            return;
        }
        try {
            installWithPackageInstaller(new File(updateApkPath));
        } catch (Exception ex) {
            setStatus(ex.getMessage());
        }
    }

    private void installWithPackageInstaller(File apk) throws Exception {
        PackageInstaller installer = getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        params.setAppPackageName(getPackageName());
        int sessionId = installer.createSession(params);
        PackageInstaller.Session session = installer.openSession(sessionId);
        FileInputStream input = new FileInputStream(apk);
        OutputStream output = session.openWrite("artificer-mobile-update", 0, apk.length());
        byte[] buffer = new byte[65536];
        int read;
        while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
        session.fsync(output);
        output.close();
        input.close();
        Intent callback = new Intent(this, SelfUpdateReceiver.class);
        callback.setAction("app.wizardry.artificer.mobile.UPDATE_COMMITTED");
        PendingIntent pending = PendingIntent.getBroadcast(
            this,
            sessionId,
            callback,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        session.commit(pending.getIntentSender());
        session.close();
    }

    private void showConnect() {
        base("Artificer Mobile");
        TextView hint = text("Pair this phone with the Mobile tab in Artificer Preferences.", 16, Typeface.NORMAL);
        hint.setTextColor(Color.rgb(83, 78, 71));
        hint.setPadding(0, dp(16), 0, dp(10));
        root.addView(hint);
        TextView steps = text("1. Enable Mobile bridge\n2. Choose IP or Tor in Artificer Preferences\n3. Copy the matching URL and pairing token", 15, Typeface.NORMAL);
        steps.setTextColor(Color.rgb(83, 78, 71));
        steps.setPadding(dp(14), dp(12), dp(14), dp(12));
        steps.setBackground(rounded(Color.rgb(239, 235, 226), line, dp(10)));
        root.addView(steps, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        RadioGroup modeGroup = new RadioGroup(this);
        modeGroup.setOrientation(RadioGroup.HORIZONTAL);
        modeGroup.setPadding(0, dp(12), 0, 0);
        RadioButton ipMode = new RadioButton(this);
        ipMode.setText("IP");
        ipMode.setTextColor(ink);
        ipMode.setId(View.generateViewId());
        RadioButton torMode = new RadioButton(this);
        torMode.setText("Tor");
        torMode.setTextColor(ink);
        torMode.setId(View.generateViewId());
        modeGroup.addView(ipMode);
        modeGroup.addView(torMode);
        modeGroup.check("tor".equals(connectionMode) ? torMode.getId() : ipMode.getId());
        root.addView(modeGroup);
        TextView modeHelp = text("", 14, Typeface.NORMAL);
        modeHelp.setTextColor(Color.rgb(83, 78, 71));
        modeHelp.setPadding(0, dp(6), 0, 0);
        root.addView(modeHelp);
        EditText endpointField = input("tor".equals(connectionMode) ? "http://your-address.onion" : "http://192.168.1.20:8765", endpoint);
        Runnable syncModeHelp = () -> {
            boolean torSelected = modeGroup.getCheckedRadioButtonId() == torMode.getId();
            modeHelp.setText(torSelected
                ? "Use the Tor URL from Artificer Preferences. Route this phone through Tor before connecting."
                : "Use the IP URL from Artificer Preferences while this phone is on the same network.");
            endpointField.setHint(torSelected ? "http://your-address.onion" : "http://192.168.1.20:8765");
        };
        modeGroup.setOnCheckedChangeListener((group, checkedId) -> syncModeHelp.run());
        syncModeHelp.run();
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
            connectionMode = modeGroup.getCheckedRadioButtonId() == torMode.getId() ? "tor" : "ip";
            endpoint = endpointField.getText().toString().trim();
            token = tokenField.getText().toString().trim();
            if (endpoint.length() == 0 || token.length() == 0) {
                setStatus("Bridge URL and pairing token are required.");
                return;
            }
            prefs.edit().putString("connection_mode", connectionMode).putString("endpoint", endpoint).putString("token", token).apply();
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

    public static final class SelfUpdateReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (!Intent.ACTION_MY_PACKAGE_REPLACED.equals(intent.getAction())) return;
            Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
            if (launch == null) return;
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            context.startActivity(launch);
        }
    }
}
