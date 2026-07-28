#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=================================="
echo "  آپدیت اپ هشدار باتری - نسخه 1.4"
echo "  (رفع مشکل هشدار نامنظم / کشته شدن در بک‌گراند)"
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
        versionCode 5
        versionName "1.4"
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

# --- Manifest: پرمیشن درست برای آلارم دقیق + ری‌استارت بعد از آپدیت ---
cat > app/src/main/AndroidManifest.xml << 'EOF_MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />

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

    </application>
</manifest>
EOF_MANIFEST

# --- Checker.java: قبل از آلارم دقیق، چک می‌کند که اجازه‌اش را واقعا دارد یا نه ---
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

        scheduleNext(c, charging);
    }

    static void scheduleNext(Context c, boolean charging) {
        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        int minutes = charging ? p.getInt("chkCharge", 2) : p.getInt("chkNormal", 10);

        AlarmManager am = c.getSystemService(AlarmManager.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 10,
                new Intent(c, BootReceiver.class).setAction("ir.batteryalert.app.CHECK"),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long at = System.currentTimeMillis() + minutes * 60000L;

        // نکته مهم: قبل از هر چیز چک می‌کنیم که سیستم واقعا اجازه آلارم دقیق داده یا نه.
        // بدون این چک، اندروید ممکن است بی‌سروصدا آلارم را نامنظم و با تاخیر زیاد اجرا کند
        // که دقیقا همان علت هشدارهای "عشقی" است.
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

# --- MainActivity.java: دکمه جدید برای اجازه "آلارم دقیق" ---
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
        advHint.setText("عدد کمتر = واکنش سریع‌تر ولی کمی مصرف بیشتر. در خواب عمیق گوشی، خود اندروید ممکن است چک‌های کمتر از حدود ۱۰ دقیقه را کمی عقب بیندازد.");
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

        Button exactAlarm = new Button(this);
        exactAlarm.setText("اجازه آلارم دقیق (خیلی مهم — بدون این هشدارها نامنظم می‌شوند)");
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
        hint.setText("\nتا وقتی شارژ از حد بالا (موقع شارژ) یا حد پایین رد شده باشد، هشدار طبق فاصله‌ای که تعیین کرده‌ای تکرار می‌شود.\n\nنکته مهم: هر دو دکمه بالا (پس‌زمینه و آلارم دقیق) را حتما بزن، وگرنه هشدارها نامنظم می‌شوند یا اصلا نمی‌آیند.\n\nنکته مهم شیائومی: در صفحه برنامه‌های اخیر، این اپ را قفل کن تا سیستم آن را نبندد.");
        root.addView(hint);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                   != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }

        Checker.check(this);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        Checker.check(this);
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
git commit -m "نسخه 1.4 - رفع باگ اصلی هشدار نامنظم (پرمیشن اشتباه آلارم دقیق) + دکمه اجازه آلارم دقیق"
git push origin main

echo ""
echo "=================================="
echo "  تمام شد!"
echo "=================================="
echo ""
echo "مشکل اصلی این بود: برنامه پرمیشن USE_EXACT_ALARM را داشت که"
echo "فقط مخصوص اپ‌های ساعت/تقویم رسمی است و برای بقیه اپ‌ها به صورت"
echo "خاموش نادیده گرفته می‌شود؛ در نتیجه اندروید آلارم‌ها را به صورت"
echo "نامنظم و با تاخیر اجرا می‌کرد. الان پرمیشن درست (SCHEDULE_EXACT_ALARM)"
echo "گذاشته شده و یک دکمه در برنامه اضافه شده که باید بزنی تا اجازه‌اش را بدهی."
echo ""
echo "۱) صبر کن تیک سبز بیاید:"
echo "   https://github.com/mmadmehdi/battery-alert/actions"
echo ""
echo "۲) جدیدترین نسخه (بالاترین شماره) را دانلود کن:"
echo "   https://github.com/mmadmehdi/battery-alert/releases"
echo ""
echo "۳) اپ قبلی را حذف کن، نسخه جدید را نصب کن."
echo ""
echo "۴) بعد از نصب حتما هر دو دکمه را بزن:"
echo "   - اجازه اجرای دائمی در پس‌زمینه"
echo "   - اجازه آلارم دقیق"
echo "   و در صفحه برنامه‌های اخیر اپ را قفل کن."
echo ""
