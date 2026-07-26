#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=================================="
echo "  آپدیت اپ هشدار باتری - نسخه 1.1"
echo "=================================="
echo ""

if [ ! -d ~/battery-alert/.git ]; then
  echo "پوشه پروژه پیدا نشد! اول اسکریپت ساخت اولیه را اجرا کن."
  exit 1
fi

cd ~/battery-alert

# --- ساخت کلید امضای ثابت (برای اینکه آپدیت‌های بعدی بدون حذف نصب شوند) ---
if ! command -v keytool >/dev/null 2>&1; then
  echo "در حال نصب ابزار امضا (فقط همین یک بار، کمی طول می‌کشد)..."
  pkg install -y openjdk-17 >/dev/null 2>&1 || pkg install -y openjdk-21 >/dev/null 2>&1 || true
fi

if command -v keytool >/dev/null 2>&1; then
  if [ ! -f app/debug.keystore ]; then
    keytool -genkeypair -keystore app/debug.keystore -alias androiddebugkey \
      -storepass android -keypass android \
      -dname "CN=Android Debug,O=Android,C=US" \
      -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
    echo "کلید امضای ثابت ساخته شد."
  fi
else
  echo "هشدار: ابزار امضا نصب نشد. اپ باز هم ساخته می‌شود ولی برای هر آپدیت باید نسخه قبلی را حذف کنی."
fi

echo "در حال به‌روز کردن فایل‌های برنامه..."

# --- تنظیمات بیلد (نسخه 1.1 + امضای ثابت) ---
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
        versionCode 2
        versionName "1.1"
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

# --- مانیفست (اجازه‌های جدید + بیدار شدن با وصل/جدا شدن شارژر) ---
cat > app/src/main/AndroidManifest.xml << 'EOF_MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />

    <application
        android:label="هشدار باتری"
        android:theme="@android:style/Theme.Material.Light"
        android:allowBackup="true">

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".BatteryService"
            android:exported="false" />

        <receiver
            android:name=".BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.ACTION_POWER_CONNECTED" />
                <action android:name="android.intent.action.ACTION_POWER_DISCONNECTED" />
            </intent-filter>
        </receiver>

    </application>
</manifest>
EOF_MANIFEST

# --- مغز برنامه: چک کردن باتری، هشدار، و زنجیره آلارم ---
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

    static void ensureChannels(Context c) {
        NotificationManager nm = c.getSystemService(NotificationManager.class);

        NotificationChannel status = new NotificationChannel(
                CH_STATUS, "وضعیت باتری", NotificationManager.IMPORTANCE_MIN);
        status.setShowBadge(false);
        nm.createNotificationChannel(status);

        NotificationChannel alert = new NotificationChannel(
                CH_ALERT, "هشدار فوری باتری", NotificationManager.IMPORTANCE_HIGH);
        alert.enableVibration(true);
        alert.setVibrationPattern(new long[]{0, 600, 250, 600, 250, 600});
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        alert.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), attrs);
        nm.createNotificationChannel(alert);

        nm.deleteNotificationChannel("alert");
    }

    static void check(Context c) {
        ensureChannels(c);

        Intent b = c.getApplicationContext().registerReceiver(
                null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (b == null) return;

        int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        if (level < 0 || scale <= 0) return;
        int percent = (int) (level * 100L / scale);
        boolean charging = b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;

        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        int high = p.getInt("high", 80);
        int low = p.getInt("low", 20);
        long now = System.currentTimeMillis();

        if (charging) {
            if (p.getLong("lastLow", 0) != 0) p.edit().putLong("lastLow", 0).apply();
            if (percent >= high) {
                long last = p.getLong("lastHigh", 0);
                if (now - last > 5 * 60 * 1000L) {
                    p.edit().putLong("lastHigh", now).apply();
                    alert(c, 2, "شارژر را جدا کن", "باتری به " + percent + "٪ رسید");
                }
            } else {
                if (p.getLong("lastHigh", 0) != 0) p.edit().putLong("lastHigh", 0).apply();
            }
        } else {
            if (p.getLong("lastHigh", 0) != 0) p.edit().putLong("lastHigh", 0).apply();
            if (percent <= low) {
                long last = p.getLong("lastLow", 0);
                if (now - last > 10 * 60 * 1000L) {
                    p.edit().putLong("lastLow", now).apply();
                    alert(c, 3, "گوشی را به شارژ بزن", "باتری فقط " + percent + "٪ است");
                }
            } else {
                if (p.getLong("lastLow", 0) != 0) p.edit().putLong("lastLow", 0).apply();
            }
        }

        NotificationManager nm = c.getSystemService(NotificationManager.class);
        nm.notify(1, status(c, "باتری: " + percent + "٪  |  هشدار در: " + high + "٪ و " + low + "٪"));

        scheduleNext(c, charging);
    }

    static void scheduleNext(Context c, boolean charging) {
        AlarmManager am = c.getSystemService(AlarmManager.class);
        Intent i = new Intent(c, BootReceiver.class).setAction("ir.batteryalert.app.CHECK");
        PendingIntent pi = PendingIntent.getBroadcast(c, 10, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long delay = charging ? 2 * 60 * 1000L : 10 * 60 * 1000L;
        long at = System.currentTimeMillis() + delay;
        try {
            if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
            }
        } catch (Exception e) {
            am.set(AlarmManager.RTC_WAKEUP, at, pi);
        }
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

# --- نگهبان پس‌زمینه ---
cat > app/src/main/java/ir/batteryalert/app/BatteryService.java << 'EOF_SERVICE'
package ir.batteryalert.app;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.IBinder;

public class BatteryService extends Service {

    private BroadcastReceiver receiver;

    @Override
    public void onCreate() {
        super.onCreate();
        Checker.ensureChannels(this);
        startForeground(1, Checker.status(this, "در حال زیر نظر گرفتن باتری..."));

        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                Checker.check(context);
            }
        };
        registerReceiver(receiver, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(1, Checker.status(this, "در حال زیر نظر گرفتن باتری..."));
        Checker.check(this);
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (receiver != null) {
            unregisterReceiver(receiver);
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
EOF_SERVICE

# --- بیدارکننده: با روشن شدن گوشی، وصل/جدا شدن شارژر، و آلارم دوره‌ای ---
cat > app/src/main/java/ir/batteryalert/app/BootReceiver.java << 'EOF_BOOT'
package ir.batteryalert.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Checker.check(context);

        try {
            Intent i = new Intent(context, BatteryService.class);
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(i);
            } else {
                context.startService(i);
            }
        } catch (Exception ignored) {
        }
    }
}
EOF_BOOT

# --- صفحه اصلی ---
cat > app/src/main/java/ir/batteryalert/app/MainActivity.java << 'EOF_MAIN'
package ir.batteryalert.app;

import android.app.Activity;
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
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {

    private EditText highInput;
    private EditText lowInput;

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

        TextView highLabel = new TextView(this);
        highLabel.setText("\nهشدار شارژ بالا (درصد) — موقع شارژ شدن:");
        root.addView(highLabel);

        highInput = new EditText(this);
        highInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        highInput.setText(String.valueOf(prefs.getInt("high", 80)));
        root.addView(highInput);

        TextView lowLabel = new TextView(this);
        lowLabel.setText("هشدار شارژ پایین (درصد) — موقع خالی شدن:");
        root.addView(lowLabel);

        lowInput = new EditText(this);
        lowInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        lowInput.setText(String.valueOf(prefs.getInt("low", 20)));
        root.addView(lowInput);

        Button save = new Button(this);
        save.setText("ذخیره و شروع");
        save.setOnClickListener(v -> {
            int high = parseOr(highInput.getText().toString(), 80);
            int low = parseOr(lowInput.getText().toString(), 20);
            if (high > 100) high = 100;
            if (high < 1) high = 1;
            if (low < 0) low = 0;
            if (low > 99) low = 99;
            if (low >= high) {
                Toast.makeText(this, "عدد پایین باید کمتر از عدد بالا باشد", Toast.LENGTH_LONG).show();
                return;
            }
            prefs.edit().putInt("high", high).putInt("low", low).apply();
            startBatteryService();
            Checker.check(this);
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

        TextView hint = new TextView(this);
        hint.setText("\nاین برنامه هر ۲ دقیقه (موقع شارژ) و هر ۱۰ دقیقه (حالت عادی) باتری را چک می‌کند، حتی اگر سیستم آن را بسته باشد. تا وقتی شارژ بالای حد باشد، هشدار هر ۵ دقیقه تکرار می‌شود.\n\nنکته مهم شیائومی: در صفحه برنامه‌های اخیر، این اپ را قفل کن تا سیستم آن را نبندد.");
        root.addView(hint);

        setContentView(root);

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                   != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }

        startBatteryService();
        Checker.check(this);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        startBatteryService();
        Checker.check(this);
    }

    private int parseOr(String s, int def) {
        try {
            return Integer.parseInt(s.trim());
        } catch (Exception e) {
            return def;
        }
    }

    private void startBatteryService() {
        Intent i = new Intent(this, BatteryService.class);
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(i);
        } else {
            startService(i);
        }
    }
}
EOF_MAIN

# --- ارسال به گیت‌هاب ---
echo "در حال ارسال به گیت‌هاب..."
git add -A
git commit -m "نسخه 1.1 - هشدار مطمئن با آلارم سیستمی و تکرار" >/dev/null
git push origin main

echo ""
echo "=================================="
echo "  تمام شد!"
echo "=================================="
echo ""
echo "۱) صبر کن تیک سبز بیاید:"
echo "   https://github.com/mmadmehdi/battery-alert/actions"
echo ""
echo "۲) جدیدترین نسخه را از اینجا دانلود کن:"
echo "   https://github.com/mmadmehdi/battery-alert/releases"
echo ""
echo "۳) مهم: اول اپ قبلی را حذف کن، بعد نسخه جدید را نصب کن."
echo "   (فقط همین یک بار - آپدیت‌های بعدی مستقیم نصب می‌شوند)"
echo ""
echo "۴) بعد از نصب: اپ را باز کن، اجازه‌ها و عددها را بده،"
echo "   و در صفحه برنامه‌های اخیر اپ را قفل کن."
echo ""
