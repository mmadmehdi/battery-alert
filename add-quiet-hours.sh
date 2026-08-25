#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=================================="
echo "  آپدیت اپ هشدار باتری - نسخه 2.0"
echo "  (بازه‌های زمانی سکوت برای هشدار باتری/دما)"
echo "=================================="
echo ""

if [ ! -d ~/battery-alert/.git ]; then
  echo "پوشه پروژه پیدا نشد! اول اسکریپت ساخت اولیه را اجرا کن."
  exit 1
fi

cd ~/battery-alert

echo "در حال به‌روز کردن فایل‌های برنامه..."

# --- build.gradle: فقط شماره نسخه بالا می‌رود ---
cat > app/build.gradle << 'EOF_APPGRADLE'
plugins {
    id 'com.android.application'
}

android {
    namespace 'ir.batteryalert.app'
    compileSdk 34

    defaultConfig {
        applicationId "ir.batteryalert.app"
        minSdk 26
        targetSdk 33
        versionCode 11
        versionName "2.0"
    }

    signingConfigs {
        stable {
            storeFile file('debug.keystore')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
    }

    buildTypes {
        debug {
            if (file('debug.keystore').exists()) {
                signingConfig signingConfigs.stable
            }
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
EOF_APPGRADLE

# --- Manifest: بدون تغییر نسبت به نسخه قبل ---
cat > app/src/main/AndroidManifest.xml << 'EOF_MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />

    <application
        android:label="هشدار باتری"
        android:theme="@android:style/Theme.Material.Light">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <receiver
            android:name=".BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.ACTION_POWER_CONNECTED" />
                <action android:name="android.intent.action.ACTION_POWER_DISCONNECTED" />
            </intent-filter>
        </receiver>

        <service
            android:name=".BatteryService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="battery-level-monitoring" />
        </service>

    </application>
</manifest>
EOF_MANIFEST

# --- Checker.java: منطق اصلی دست‌نخورده؛ فقط یک چک اضافه برای «بازه سکوت» ---
cat > app/src/main/java/ir/batteryalert/app/Checker.java << 'EOF_CHECKER'
package ir.batteryalert.app;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.BatteryManager;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Calendar;

public class Checker {

    static final String CH_STATUS = "status";
    static final String CH_ALERT = "alert2";
    private static boolean channelsReady = false;

    static void ensureChannels(Context c) {
        if (channelsReady) return;
        NotificationManager nm = c.getSystemService(NotificationManager.class);

        NotificationChannel status = new NotificationChannel(
                CH_STATUS, "وضعیت باتری", NotificationManager.IMPORTANCE_MIN);
        status.setShowBadge(false);
        nm.createNotificationChannel(status);

        NotificationChannel alert = new NotificationChannel(
                CH_ALERT, "هشدار فوری باتری", NotificationManager.IMPORTANCE_HIGH);
        alert.enableVibration(true);
        alert.setVibrationPattern(new long[]{0, 600, 250, 600, 250, 600});
        alert.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build());
        nm.createNotificationChannel(alert);
        channelsReady = true;
    }

    /**
     * منطق اصلی (آستانه‌ها، تکرار، محاسبه درصد و دما) دقیقا مثل قبل است.
     * تنها تغییر نسبت به نسخه قبل: هر سه سوییچ حالا علاوه بر روشن/خاموش بودن
     * خودشان، چک می‌کنند که الان داخل یک «بازه سکوت» تعریف‌شده توسط کاربر
     * نیستند. این چک کاملا جدا و اضافه است.
     */
    static void checkFromIntent(Context c, Intent b) {
        ensureChannels(c);
        if (b == null) return;

        int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        if (level < 0 || scale <= 0) return;
        int percent = (int) (level * 100L / scale);
        boolean charging = b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;

        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();

        boolean enableHigh = p.getBoolean("enableHigh", true) && !isSuppressed(c, true);
        boolean enableLow = p.getBoolean("enableLow", true) && !isSuppressed(c, true);

        if (enableHigh && charging && percent >= p.getInt("high", 80)) {
            if (now - p.getLong("lastHigh", 0) > p.getInt("repHigh", 5) * 60000L) {
                p.edit().putLong("lastHigh", now).putLong("lastLow", 0).apply();
                alert(c, 2, "شارژر را جدا کن", "باتری به " + percent + "٪ رسید");
            }
        } else if (enableLow && !charging && percent <= p.getInt("low", 20)) {
            if (now - p.getLong("lastLow", 0) > p.getInt("repLow", 10) * 60000L) {
                p.edit().putLong("lastLow", now).putLong("lastHigh", 0).apply();
                alert(c, 3, "گوشی را به شارژ بزن", "باتری فقط " + percent + "٪ است");
            }
        } else {
            p.edit().putLong("lastHigh", 0).putLong("lastLow", 0).apply();
        }

        // --- بخش دما: همان دو سوییچ قبلی + همین چک بازه سکوت ---
        int tempTenths = b.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
        String tempText = "";
        if (tempTenths != Integer.MIN_VALUE) {
            double tempC = tempTenths / 10.0;
            tempText = "  |  دما: " + formatTemp(tempC) + "°C";

            boolean enableTemp = p.getBoolean("enableTemp", true) && !isSuppressed(c, false);
            boolean tempWhileCharging = p.getBoolean("tempWhileCharging", true);
            boolean tempActiveNow = enableTemp && (!charging || tempWhileCharging);

            int tempHigh = p.getInt("tempHigh", 45);
            if (tempActiveNow && tempC >= tempHigh) {
                if (now - p.getLong("lastTemp", 0) > p.getInt("repTemp", 5) * 60000L) {
                    p.edit().putLong("lastTemp", now).apply();
                    alert(c, 4, "دمای باتری بالا رفت", "دما به " + formatTemp(tempC) + "°C رسید");
                }
            } else if (!tempActiveNow || tempC < tempHigh) {
                p.edit().putLong("lastTemp", 0).apply();
            }
        }

        c.getSystemService(NotificationManager.class).notify(1, status(c,
                "باتری: " + percent + "٪" + tempText + "  |  هشدار در: "
                + p.getInt("high", 80) + "٪ و " + p.getInt("low", 20) + "٪"));

        scheduleRestartAlarm(c);
    }

    /**
     * آیا الان داخل یکی از بازه‌های سکوتی هستیم که کاربر برای این نوع هشدار
     * (باتری یا دما) تعریف کرده؟ بازه‌ها در تنظیمات به صورت JSON ذخیره می‌شوند.
     */
    static boolean isSuppressed(Context c, boolean forBattery) {
        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        String json = p.getString("quietPeriods", "[]");
        try {
            JSONArray arr = new JSONArray(json);
            Calendar cal = Calendar.getInstance();
            int nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE);
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                boolean matches = forBattery ? o.optBoolean("b", false) : o.optBoolean("t", false);
                if (!matches) continue;
                int s = o.optInt("s", 0);
                int e = o.optInt("e", 0);
                boolean inRange = (s <= e) ? (nowMin >= s && nowMin < e) : (nowMin >= s || nowMin < e);
                if (inRange) return true;
            }
        } catch (Exception ignored) {
        }
        return false;
    }

    private static String formatTemp(double tempC) {
        return String.valueOf(Math.round(tempC * 10.0) / 10.0);
    }

    /**
     * فقط زنگ خطر پشتیبان (نه بخشی از دریافت باتری): اگر سرویس اصلی به هر دلیلی
     * کشته شود، دوباره روشنش می‌کند. غیردقیق و هر ۳۰ دقیقه، همانند نسخه قبل.
     */
    static void scheduleRestartAlarm(Context c) {
        AlarmManager am = c.getSystemService(AlarmManager.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 10,
                new Intent(c, BootReceiver.class).setAction("ir.batteryalert.app.RESTART"),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long at = System.currentTimeMillis() + 30 * 60000L;
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
    }

    static Notification status(Context c, String text) {
        PendingIntent pi = PendingIntent.getActivity(
                c, 0, new Intent(c, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(c, CH_STATUS)
                .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
                .setContentTitle("هشدار باتری فعال است")
                .setContentText(text)
                .setOngoing(true)
                .setContentIntent(pi)
                .build();
    }

    static void alert(Context c, int id, String title, String text) {
        PendingIntent pi = PendingIntent.getActivity(
                c, 1, new Intent(c, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(c, CH_ALERT)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .setFullScreenIntent(pi, true)
                .build();
        c.getSystemService(NotificationManager.class).notify(id, n);
    }
}
EOF_CHECKER

# --- BatteryService.java: کاملا دست‌نخورده ---
cat > app/src/main/java/ir/batteryalert/app/BatteryService.java << 'EOF_SERVICE'
package ir.batteryalert.app;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.IBinder;

public class BatteryService extends Service {

    private BroadcastReceiver batteryReceiver;

    @Override
    public void onCreate() {
        super.onCreate();
        Checker.ensureChannels(this);
        startForeground(1, Checker.status(this, "در حال بررسی باتری..."));

        batteryReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                Checker.checkFromIntent(BatteryService.this, intent);
            }
        };
        Intent sticky = registerReceiver(batteryReceiver, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        Checker.checkFromIntent(this, sticky);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (batteryReceiver != null) {
            try {
                unregisterReceiver(batteryReceiver);
            } catch (Exception ignored) {
            }
        }
        Checker.scheduleRestartAlarm(this);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
EOF_SERVICE

# --- BootReceiver.java: بدون تغییر ---
cat > app/src/main/java/ir/batteryalert/app/BootReceiver.java << 'EOF_BOOT'
package ir.batteryalert.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent svc = new Intent(context, BatteryService.class);
        if (Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(svc);
        } else {
            context.startService(svc);
        }
    }
}
EOF_BOOT

# --- MainActivity.java: بخش جدید «بازه‌های سکوت» با قابلیت افزودن/حذف نامحدود ---
cat > app/src/main/java/ir/batteryalert/app/MainActivity.java << 'EOF_MAIN'
package ir.batteryalert.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.TimePickerDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

public class MainActivity extends Activity {

    private CheckBox enableHighBox, enableLowBox, enableTempBox, tempWhileChargingBox;
    private EditText highInput, lowInput;
    private EditText repHighInput, repLowInput;
    private EditText tempHighInput, repTempInput;
    private LinearLayout quietListContainer;
    private SharedPreferences prefs;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        prefs = getSharedPreferences("settings", MODE_PRIVATE);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

        TextView title = new TextView(this);
        title.setText("هشدار باتری");
        title.setTextSize(24);
        root.addView(title);

        enableHighBox = addCheck(root, "\nهشدار شارژ بالا فعال باشد", prefs.getBoolean("enableHigh", true));
        highInput = addField(root, "هشدار شارژ بالا (درصد) — موقع شارژ شدن:", prefs.getInt("high", 80));

        enableLowBox = addCheck(root, "\nهشدار شارژ پایین فعال باشد", prefs.getBoolean("enableLow", true));
        lowInput = addField(root, "هشدار شارژ پایین (درصد) — موقع خالی شدن:", prefs.getInt("low", 20));

        enableTempBox = addCheck(root, "\nهشدار دمای باتری فعال باشد", prefs.getBoolean("enableTemp", true));
        tempWhileChargingBox = addCheck(root, "هشدار دما در حالت شارژ هم فعال باشد", prefs.getBoolean("tempWhileCharging", true));
        tempHighInput = addField(root, "هشدار دمای باتری (سانتی‌گراد):", prefs.getInt("tempHigh", 45));

        Button settingsBtn = new Button(this);
        settingsBtn.setText("تنظیمات تکرار هشدار");
        root.addView(settingsBtn);

        LinearLayout adv = new LinearLayout(this);
        adv.setOrientation(LinearLayout.VERTICAL);
        adv.setVisibility(View.GONE);
        root.addView(adv);

        settingsBtn.setOnClickListener(v ->
                adv.setVisibility(adv.getVisibility() == View.GONE ? View.VISIBLE : View.GONE));

        repHighInput = addField(adv, "هشدار شارژ بالا هر چند دقیقه تکرار شود؟", prefs.getInt("repHigh", 5));
        repLowInput = addField(adv, "هشدار شارژ پایین هر چند دقیقه تکرار شود؟", prefs.getInt("repLow", 10));
        repTempInput = addField(adv, "هشدار دما هر چند دقیقه تکرار شود؟", prefs.getInt("repTemp", 5));

        Button save = new Button(this);
        save.setText("ذخیره و شروع");
        save.setOnClickListener(v -> {
            int high = clamp(parseOr(highInput, 80), 1, 100);
            int low = clamp(parseOr(lowInput, 20), 0, 99);
            if (low >= high) {
                Toast.makeText(this, "عدد پایین باید کمتر از عدد بالا باشد", Toast.LENGTH_LONG).show();
                return;
            }
            int tempHigh = clamp(parseOr(tempHighInput, 45), 30, 60);
            prefs.edit()
                    .putBoolean("enableHigh", enableHighBox.isChecked())
                    .putBoolean("enableLow", enableLowBox.isChecked())
                    .putBoolean("enableTemp", enableTempBox.isChecked())
                    .putBoolean("tempWhileCharging", tempWhileChargingBox.isChecked())
                    .putInt("high", high)
                    .putInt("low", low)
                    .putInt("tempHigh", tempHigh)
                    .putInt("repHigh", clamp(parseOr(repHighInput, 5), 1, 60))
                    .putInt("repLow", clamp(parseOr(repLowInput, 10), 1, 120))
                    .putInt("repTemp", clamp(parseOr(repTempInput, 5), 1, 60))
                    .apply();
            startBatteryService();
            Toast.makeText(this, "ذخیره شد، هشدار فعال است", Toast.LENGTH_SHORT).show();
        });
        root.addView(save);

        // --- بخش جدید: بازه‌های سکوت ---
        TextView quietTitle = new TextView(this);
        quietTitle.setText("\nبازه‌های سکوت (خاموش کردن هشدار در ساعات خاص)");
        quietTitle.setTextSize(18);
        root.addView(quietTitle);

        TextView quietHint = new TextView(this);
        quietHint.setText("هر بازه را جدا تعریف کن و مشخص کن در آن بازه کدام هشدار (باتری، دما یا هر دو) خاموش شود. هر تعداد بازه که بخواهی می‌توانی اضافه کنی.");
        root.addView(quietHint);

        quietListContainer = new LinearLayout(this);
        quietListContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(quietListContainer);

        Button addQuiet = new Button(this);
        addQuiet.setText("+ افزودن بازه‌ی جدید");
        addQuiet.setOnClickListener(v -> showAddQuietDialog());
        root.addView(addQuiet);

        renderQuietPeriods();

        Button battery = new Button(this);
        battery.setText("اجازه اجرای دائمی در پس‌زمینه");
        battery.setOnClickListener(v -> {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && pm.isIgnoringBatteryOptimizations(getPackageName())) {
                Toast.makeText(this, "قبلا فعال شده است", Toast.LENGTH_SHORT).show();
                return;
            }
            Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            i.setData(Uri.parse("package:" + getPackageName()));
            startActivity(i);
        });
        root.addView(battery);

        TextView hint = new TextView(this);
        hint.setText("\nهر سه هشدار (شارژ بالا، شارژ پایین، دما) کاملا مستقل از هم روشن یا خاموش می‌شوند.\n\nنکته مهم شیائومی: در صفحه برنامه‌های اخیر، این اپ را قفل کن تا سیستم آن را نبندد.");
        root.addView(hint);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                   != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }

        startBatteryService();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        startBatteryService();
    }

    private void startBatteryService() {
        Intent i = new Intent(this, BatteryService.class);
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(i);
        } else {
            startService(i);
        }
    }

    // ---------- بازه‌های سکوت ----------

    private JSONArray loadQuietPeriods() {
        try {
            return new JSONArray(prefs.getString("quietPeriods", "[]"));
        } catch (Exception e) {
            return new JSONArray();
        }
    }

    private void saveQuietPeriods(JSONArray arr) {
        prefs.edit().putString("quietPeriods", arr.toString()).apply();
    }

    private void renderQuietPeriods() {
        quietListContainer.removeAllViews();
        JSONArray arr = loadQuietPeriods();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            int s = o.optInt("s", 0);
            int e = o.optInt("e", 0);
            boolean b = o.optBoolean("b", false);
            boolean t = o.optBoolean("t", false);

            String what;
            if (b && t) what = "باتری و دما";
            else if (b) what = "باتری";
            else what = "دما";

            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);

            TextView text = new TextView(this);
            text.setText(String.format("از %02d:%02d تا %02d:%02d — خاموش: %s", s / 60, s % 60, e / 60, e % 60, what));
            text.setLayoutParams(new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1));
            row.addView(text);

            int index = i;
            Button remove = new Button(this);
            remove.setText("حذف");
            remove.setOnClickListener(v -> {
                JSONArray current = loadQuietPeriods();
                JSONArray updated = new JSONArray();
                for (int j = 0; j < current.length(); j++) {
                    if (j != index) updated.put(current.opt(j));
                }
                saveQuietPeriods(updated);
                renderQuietPeriods();
            });
            row.addView(remove);

            quietListContainer.addView(row);
        }
    }

    private void showAddQuietDialog() {
        LinearLayout dialogLayout = new LinearLayout(this);
        dialogLayout.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        dialogLayout.setPadding(pad, pad, pad, pad);

        Button startBtn = new Button(this);
        startBtn.setText("ساعت شروع: 00:00");
        startBtn.setTag(0);
        startBtn.setOnClickListener(v -> new TimePickerDialog(this, (view, hourOfDay, minute) -> {
            int minutes = hourOfDay * 60 + minute;
            startBtn.setTag(minutes);
            startBtn.setText(String.format("ساعت شروع: %02d:%02d", hourOfDay, minute));
        }, 0, 0, true).show());
        dialogLayout.addView(startBtn);

        Button endBtn = new Button(this);
        endBtn.setText("ساعت پایان: 00:00");
        endBtn.setTag(0);
        endBtn.setOnClickListener(v -> new TimePickerDialog(this, (view, hourOfDay, minute) -> {
            int minutes = hourOfDay * 60 + minute;
            endBtn.setTag(minutes);
            endBtn.setText(String.format("ساعت پایان: %02d:%02d", hourOfDay, minute));
        }, 0, 0, true).show());
        dialogLayout.addView(endBtn);

        CheckBox suppressBattery = new CheckBox(this);
        suppressBattery.setText("در این بازه هشدار باتری خاموش شود");
        dialogLayout.addView(suppressBattery);

        CheckBox suppressTemp = new CheckBox(this);
        suppressTemp.setText("در این بازه هشدار دما خاموش شود");
        dialogLayout.addView(suppressTemp);

        new AlertDialog.Builder(this)
                .setTitle("افزودن بازه‌ی سکوت")
                .setView(dialogLayout)
                .setPositiveButton("افزودن", (dialog, which) -> {
                    if (!suppressBattery.isChecked() && !suppressTemp.isChecked()) {
                        Toast.makeText(this, "حداقل یکی از باتری یا دما را انتخاب کن", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    int s = (int) startBtn.getTag();
                    int e = (int) endBtn.getTag();
                    try {
                        JSONObject o = new JSONObject();
                        o.put("s", s);
                        o.put("e", e);
                        o.put("b", suppressBattery.isChecked());
                        o.put("t", suppressTemp.isChecked());
                        JSONArray arr = loadQuietPeriods();
                        arr.put(o);
                        saveQuietPeriods(arr);
                        renderQuietPeriods();
                    } catch (Exception ignored) {
                    }
                })
                .setNegativeButton("انصراف", null)
                .show();
    }

    // ---------- ابزارهای عمومی فرم ----------

    private CheckBox addCheck(LinearLayout parent, String label, boolean value) {
        CheckBox cb = new CheckBox(this);
        cb.setText(label);
        cb.setChecked(value);
        parent.addView(cb);
        return cb;
    }

    private EditText addField(LinearLayout parent, String label, int value) {
        TextView t = new TextView(this);
        t.setText(label);
        parent.addView(t);
        EditText e = new EditText(this);
        e.setInputType(InputType.TYPE_CLASS_NUMBER);
        e.setText(String.valueOf(value));
        parent.addView(e);
        return e;
    }

    private int parseOr(EditText e, int def) {
        try {
            return Integer.parseInt(e.getText().toString().trim());
        } catch (Exception ex) {
            return def;
        }
    }

    private int clamp(int v, int min, int max) {
        if (v < min) return min;
        if (v > max) return max;
        return v;
    }
}
EOF_MAIN

echo "در حال ارسال به گیت‌هاب..."
git add -A
git commit -m "نسخه 2.0 - بازه‌های زمانی سکوت قابل تعریف نامحدود برای خاموش کردن جداگانه هشدار باتری/دما"
git push origin main

echo ""
echo "=================================="
echo "  تمام شد!"
echo "=================================="
echo ""
echo "خلاصه تغییرات این نسخه:"
echo ""
echo "- یک بخش جدید «بازه‌های سکوت» در صفحه اصلی اضافه شد."
echo "- با دکمه «+ افزودن بازه‌ی جدید» یک ساعت شروع، یک ساعت پایان، و اینکه در"
echo "  آن بازه هشدار باتری، هشدار دما، یا هر دو خاموش شوند را انتخاب می‌کنی."
echo "- هر تعداد بازه که بخواهی می‌توانی اضافه کنی؛ هرکدام مستقل از بقیه است و"
echo "  با دکمه «حذف» کنار هرکدام قابل پاک شدن است."
echo "- مثال دقیقا مطابق خواسته‌ات: می‌توانی ۱ تا ۲ را فقط باتری، ۲ تا ۳ را فقط"
echo "  دما، و ۴ تا ۵ را هم باتری هم دما تعریف کنی — همزمان و بدون تداخل."
echo "- منطق اصلی آستانه‌ها و نحوه دریافت باتری/دما دقیقا مثل قبل دست‌نخورده"
echo "  ماند؛ فقط یک شرط اضافه («الان داخل بازه سکوت هستیم یا نه؟») به هر سه"
echo "  سوییچ قبلی اضافه شده."
echo ""
echo "۱) صبر کن تیک سبز بیاید:"
echo "   https://github.com/mmadmehdi/battery-alert/actions"
echo ""
echo "۲) جدیدترین نسخه (بالاترین شماره) را دانلود کن:"
echo "   https://github.com/mmadmehdi/battery-alert/releases"
echo ""
echo "۳) اپ قبلی را حذف کن، نسخه جدید را نصب کن."
echo ""
