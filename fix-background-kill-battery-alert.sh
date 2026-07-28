#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=================================="
echo "  آپدیت اپ هشدار باتری - نسخه 1.5"
echo "  (رفع کشته شدن در بک‌گراند با سرویس دائمی)"
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
        versionCode 6
        versionName "1.5"
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

# --- Manifest: اجازه سرویس دائمی + خود سرویس ---
cat > app/src/main/AndroidManifest.xml << 'EOF_MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
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

# --- Checker.java: check() حالا برمی‌گرداند شارژ هست یا نه، و یک آلارم پشتیبان دارد ---
cat > app/src/main/java/ir/batteryalert/app/Checker.java << 'EOF_CHECKER'
package ir.batteryalert.app;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.BatteryManager;
import android.os.Build;

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

    /** یک بار وضعیت باتری را چک می‌کند و می‌گوید الان در حال شارژ هست یا نه. */
    static boolean check(Context c) {
        ensureChannels(c);

        Intent b = c.getApplicationContext().registerReceiver(
                null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (b == null) return false;

        int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        if (level < 0 || scale <= 0) return false;
        int percent = (int) (level * 100L / scale);
        boolean charging = b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;

        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();

        if (charging && percent >= p.getInt("high", 80)) {
            if (now - p.getLong("lastHigh", 0) > p.getInt("repHigh", 5) * 60000L) {
                p.edit().putLong("lastHigh", now).putLong("lastLow", 0).apply();
                alert(c, 2, "شارژر را جدا کن", "باتری به " + percent + "٪ رسید");
            }
        } else if (!charging && percent <= p.getInt("low", 20)) {
            if (now - p.getLong("lastLow", 0) > p.getInt("repLow", 10) * 60000L) {
                p.edit().putLong("lastLow", now).putLong("lastHigh", 0).apply();
                alert(c, 3, "گوشی را به شارژ بزن", "باتری فقط " + percent + "٪ است");
            }
        } else {
            p.edit().putLong("lastHigh", 0).putLong("lastLow", 0).apply();
        }

        c.getSystemService(NotificationManager.class).notify(1, status(c,
                "باتری: " + percent + "٪  |  هشدار در: "
                + p.getInt("high", 80) + "٪ و " + p.getInt("low", 20) + "٪"));

        scheduleRestartAlarm(c);
        return charging;
    }

    /** برنامه هر چند دقیقه باید دوباره چک کند (تنظیمات کاربر). */
    static int nextIntervalMinutes(Context c, boolean charging) {
        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        return charging ? p.getInt("chkCharge", 2) : p.getInt("chkNormal", 10);
    }

    /**
     * این فقط یک "زنگ خطر پشتیبان" است: اگر سیستم سرویس اصلی را کشت،
     * حداکثر تا ۱۵ دقیقه بعد این آلارم دوباره سرویس را روشن می‌کند.
     * موتور اصلی چک کردن، حلقه‌ی داخل BatteryService است، نه این آلارم.
     */
    static void scheduleRestartAlarm(Context c) {
        AlarmManager am = c.getSystemService(AlarmManager.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 10,
                new Intent(c, BootReceiver.class).setAction("ir.batteryalert.app.RESTART"),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long at = System.currentTimeMillis() + 15 * 60000L;

        boolean canExact = true;
        if (Build.VERSION.SDK_INT >= 31) {
            canExact = am.canScheduleExactAlarms();
        }
        if (canExact) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
                return;
            } catch (Exception e) {
                // ادامه به حالت جایگزین زیر
            }
        }
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

# --- BatteryService.java: سرویس دائمی که خودش حلقه‌ی چک کردن را نگه می‌دارد ---
cat > app/src/main/java/ir/batteryalert/app/BatteryService.java << 'EOF_SERVICE'
package ir.batteryalert.app;

import android.app.Service;
import android.content.Intent;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

/**
 * این سرویس همیشه زنده می‌ماند (با یک نوتیفیکیشن کم‌اهمیت که از قبل هم وجود داشت)
 * و خودش هر چند دقیقه باتری را چک می‌کند. چون سیستم سرویس فورگراند را خیلی دیرتر
 * از یک اپ عادی می‌کشد، دیگر چند دقیقه بدون هیچ چکی سپری نمی‌شود.
 */
public class BatteryService extends Service {

    private final Handler handler = new Handler(Looper.getMainLooper());
    private Runnable loop;
    private boolean running = false;

    @Override
    public void onCreate() {
        super.onCreate();
        Checker.ensureChannels(this);
        startForeground(1, Checker.status(this, "در حال بررسی باتری..."));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!running) {
            running = true;
            loop = this::runCheck;
            handler.post(loop);
        }
        return START_STICKY;
    }

    private void runCheck() {
        boolean charging = Checker.check(this);
        int minutes = Checker.nextIntervalMinutes(this, charging);
        long delayMs = Math.max(60000L, minutes * 60000L); // حداقل ۱ دقیقه، برای صرفه‌جویی باتری
        handler.postDelayed(loop, delayMs);
    }

    @Override
    public void onDestroy() {
        running = false;
        if (loop != null) handler.removeCallbacks(loop);
        // اگر سیستم سرویس را کشت، آلارم پشتیبان دوباره روشنش می‌کند
        Checker.scheduleRestartAlarm(this);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
EOF_SERVICE

# --- BootReceiver.java: فقط سرویس را روشن می‌کند ---
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

# --- MainActivity.java: روشن کردن سرویس در کنار دکمه‌های اجازه ---
cat > app/src/main/java/ir/batteryalert/app/MainActivity.java << 'EOF_MAIN'
package ir.batteryalert.app;

import android.app.Activity;
import android.app.AlarmManager;
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
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {

    private EditText highInput, lowInput;
    private EditText chkChargeInput, chkNormalInput, repHighInput, repLowInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);
        root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

        TextView title = new TextView(this);
        title.setText("هشدار باتری");
        title.setTextSize(24);
        root.addView(title);

        highInput = addField(root, "\nهشدار شارژ بالا (درصد) — موقع شارژ شدن:", prefs.getInt("high", 80));
        lowInput = addField(root, "هشدار شارژ پایین (درصد) — موقع خالی شدن:", prefs.getInt("low", 20));

        Button settingsBtn = new Button(this);
        settingsBtn.setText("تنظیمات زمان‌بندی");
        root.addView(settingsBtn);

        LinearLayout adv = new LinearLayout(this);
        adv.setOrientation(LinearLayout.VERTICAL);
        adv.setVisibility(View.GONE);
        root.addView(adv);

        settingsBtn.setOnClickListener(v ->
                adv.setVisibility(adv.getVisibility() == View.GONE ? View.VISIBLE : View.GONE));

        chkChargeInput = addField(adv, "موقع شارژ، هر چند دقیقه چک شود؟", prefs.getInt("chkCharge", 2));
        chkNormalInput = addField(adv, "حالت عادی، هر چند دقیقه چک شود؟", prefs.getInt("chkNormal", 10));
        repHighInput = addField(adv, "هشدار بالا هر چند دقیقه تکرار شود؟", prefs.getInt("repHigh", 5));
        repLowInput = addField(adv, "هشدار پایین هر چند دقیقه تکرار شود؟", prefs.getInt("repLow", 10));

        TextView advHint = new TextView(this);
        advHint.setText("عدد کمتر = واکنش سریع‌تر ولی کمی مصرف بیشتر.");
        adv.addView(advHint);

        Button save = new Button(this);
        save.setText("ذخیره و شروع");
        save.setOnClickListener(v -> {
            int high = clamp(parseOr(highInput, 80), 1, 100);
            int low = clamp(parseOr(lowInput, 20), 0, 99);
            if (low >= high) {
                Toast.makeText(this, "عدد پایین باید کمتر از عدد بالا باشد", Toast.LENGTH_LONG).show();
                return;
            }
            prefs.edit()
                    .putInt("high", high)
                    .putInt("low", low)
                    .putInt("chkCharge", clamp(parseOr(chkChargeInput, 2), 1, 60))
                    .putInt("chkNormal", clamp(parseOr(chkNormalInput, 10), 5, 120))
                    .putInt("repHigh", clamp(parseOr(repHighInput, 5), 1, 60))
                    .putInt("repLow", clamp(parseOr(repLowInput, 10), 1, 120))
                    .apply();
            startBatteryService();
            Toast.makeText(this, "ذخیره شد، هشدار فعال است", Toast.LENGTH_SHORT).show();
        });
        root.addView(save);

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

        Button exactAlarm = new Button(this);
        exactAlarm.setText("اجازه آلارم دقیق (پشتیبان)");
        exactAlarm.setOnClickListener(v -> {
            if (Build.VERSION.SDK_INT < 31) {
                Toast.makeText(this, "روی این نسخه اندروید لازم نیست", Toast.LENGTH_SHORT).show();
                return;
            }
            AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am != null && am.canScheduleExactAlarms()) {
                Toast.makeText(this, "قبلا فعال شده است", Toast.LENGTH_SHORT).show();
                return;
            }
            Intent i = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM);
            i.setData(Uri.parse("package:" + getPackageName()));
            startActivity(i);
        });
        root.addView(exactAlarm);

        TextView hint = new TextView(this);
        hint.setText("\nتا وقتی شارژ از حد بالا (موقع شارژ) یا حد پایین رد شده باشد، هشدار طبق فاصله‌ای که تعیین کرده‌ای تکرار می‌شود.\n\nالان برنامه با یک سرویس دائمی (همان نوتیفیکیشن ثابت پایین صفحه) کار می‌کند تا سیستم آن را نکشد. با این حال هر دو دکمه بالا را هم بزن.\n\nنکته مهم شیائومی: در صفحه برنامه‌های اخیر، این اپ را قفل کن تا سیستم آن را نبندد.");
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
git commit -m "نسخه 1.5 - سرویس فورگراند دائمی برای جلوگیری از کشته شدن در بک‌گراند"
git push origin main

echo ""
echo "=================================="
echo "  تمام شد!"
echo "=================================="
echo ""
echo "تغییر اصلی: حالا برنامه یک سرویس دائمی دارد (همان نوتیفیکیشن پایین"
echo "صفحه که قبلا هم بود، چیز جدیدی اضافه نشده) و خودش هر چند دقیقه چک می‌کند."
echo "سرویس فورگراند خیلی دیرتر از یک brodcast/آلارم ساده کشته می‌شود،"
echo "پس دیگر نباید چند دقیقه بدون هیچ چکی بگذرد."
echo ""
echo "۱) صبر کن تیک سبز بیاید:"
echo "   https://github.com/mmadmehdi/battery-alert/actions"
echo ""
echo "۲) جدیدترین نسخه (بالاترین شماره) را دانلود کن:"
echo "   https://github.com/mmadmehdi/battery-alert/releases"
echo ""
echo "۳) اپ قبلی را حذف کن، نسخه جدید را نصب کن."
echo ""
echo "۴) بعد از نصب حتما هر دو دکمه را بزن و اپ را در برنامه‌های اخیر قفل کن."
echo ""
