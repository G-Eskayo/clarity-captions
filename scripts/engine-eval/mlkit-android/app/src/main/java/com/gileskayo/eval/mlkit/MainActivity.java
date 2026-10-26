// ML Kit on-device translation harness (#159). Reads the test sets pushed to the app's external files dir
// (files/sets/*.jsonl), downloads the language model through ML Kit's own model manager (app-controlled, no system
// UI), translates one line at a time and appends #145-format result lines to files/results/mlkit.jsonl (resumable).
// Writes files/done.json with the download time and the bytes the model added to the app's data directory.
package com.gileskayo.eval.mlkit;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.widget.TextView;

import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.common.model.DownloadConditions;
import com.google.mlkit.nl.translate.TranslateLanguage;
import com.google.mlkit.nl.translate.Translation;
import com.google.mlkit.nl.translate.Translator;
import com.google.mlkit.nl.translate.TranslatorOptions;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class MainActivity extends Activity {
    private static final String TAG = "MLKitEval";
    private static final String[] SETS = {"flores", "flores-caption", "speech", "speech-caption", "edacc-lines"};

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView view = new TextView(this);
        view.setText("running");
        setContentView(view);
        String target = getIntent().getStringExtra("target");
        int repeats = getIntent().getIntExtra("repeats", 2);
        new Thread(() -> {
            File root = getFilesDir();
            JSONObject summary = new JSONObject();
            try {
                summary = run(root, target == null ? "es" : target, repeats);
            } catch (Exception e) {
                Log.e(TAG, "failed", e);
                try { summary.put("error", e.toString()); } catch (Exception ignored) { }
            }
            write(new File(root, "done.json"), summary.toString());
            finishAndRemoveTask();
        }).start();
    }

    private JSONObject run(File root, String target, int repeats) throws Exception {
        String lang = TranslateLanguage.fromLanguageTag(target);
        Translator translator = Translation.getClient(new TranslatorOptions.Builder()
                .setSourceLanguage(TranslateLanguage.ENGLISH).setTargetLanguage(lang).build());
        File data = getDataDir();
        long before = bytes(data);
        long t0 = SystemClock.elapsedRealtime();
        Tasks.await(translator.downloadModelIfNeeded(new DownloadConditions.Builder().build()));
        double downloadSeconds = (SystemClock.elapsedRealtime() - t0) / 1000.0;
        long after = bytes(data);

        File results = new File(root, "results/mlkit.jsonl");
        results.getParentFile().mkdirs();
        Set<String> done = new HashSet<>();
        if (results.exists()) {
            for (String line : readLines(results)) {
                try {
                    JSONObject d = new JSONObject(line);
                    done.add(d.getString("clip_id") + "#" + d.getInt("repeat"));
                } catch (Exception ignored) { } // truncated last line
            }
        }
        Tasks.await(translator.translate("warm up"));
        int count = 0, errors = 0;
        String model = "mlkit-en-" + target;
        String version = "com.google.mlkit:translate:17.0.3, Android " + Build.VERSION.RELEASE + " emulator "
                + Build.SUPPORTED_ABIS[0];
        try (Writer out = new OutputStreamWriter(new FileOutputStream(results, true), StandardCharsets.UTF_8)) {
            if (results.length() > 0) out.write("\n"); // a crash mid-write leaves a partial line; start fresh
            for (String name : SETS) {
                File f = new File(root, "sets/" + name + ".jsonl");
                if (!f.exists()) continue;
                List<String> rows = readLines(f);
                int reps = name.equals("edacc-lines") ? repeats : 1;
                for (int rep = 1; rep <= reps; rep++) {
                    for (String raw : rows) {
                        JSONObject row = new JSONObject(raw);
                        String id = row.getString("id");
                        if (done.contains(id + "#" + rep)) continue;
                        long s = System.nanoTime();
                        String hyp;
                        try {
                            hyp = Tasks.await(translator.translate(row.getString("source")));
                        } catch (Exception e) {
                            errors++;
                            Log.e(TAG, "line " + id, e);
                            continue;
                        }
                        double secs = (System.nanoTime() - s) / 1e9;
                        JSONObject r = new JSONObject();
                        r.put("clip_id", id).put("shard", 0).put("accent", name).put("engine", "mlkit")
                                .put("model", model).put("engine_version", version).put("repeat", rep)
                                .put("hypothesis", hyp == null ? "" : hyp).put("audio_seconds", 0)
                                .put("processing_seconds", secs).put("batch_size", 1).put("host", "android-emulator")
                                .put("finished_at", java.time.Instant.now().toString());
                        out.write(r.toString() + "\n");
                        out.flush();
                        count++;
                    }
                }
            }
        }
        JSONObject summary = new JSONObject();
        summary.put("target", target).put("lines", count).put("errors", errors)
                .put("download_seconds", downloadSeconds).put("model_bytes_added", after - before)
                .put("model_files", list(data));
        return summary;
    }

    private static List<String> readLines(File f) throws Exception {
        List<String> out = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(f), StandardCharsets.UTF_8))) {
            for (String l; (l = r.readLine()) != null; ) if (!l.trim().isEmpty()) out.add(l);
        }
        return out;
    }

    private static long bytes(File f) {
        if (f.isFile()) return f.length();
        long t = 0;
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) t += bytes(k);
        return t;
    }

    private static JSONArray list(File dir) {
        JSONArray a = new JSONArray();
        walk(dir, dir, a);
        return a;
    }

    private static void walk(File base, File f, JSONArray a) {
        if (f.isFile()) {
            if (f.length() > 1_000_000) a.put(f.getPath().substring(base.getPath().length()) + " " + f.length());
            return;
        }
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) walk(base, k, a);
    }

    private static void write(File f, String s) {
        try (Writer w = new OutputStreamWriter(new FileOutputStream(f), StandardCharsets.UTF_8)) {
            w.write(s);
        } catch (Exception e) {
            Log.e(TAG, "write " + f, e);
        }
    }
}
