#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=================================="
echo "  آپدیت اپ هشدار باتری - نسخه 1.7"
echo "  (کم‌مصرف‌تر، بدون تغییر در هشدارها)"
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
        versionCode 8
        versionName "1.7"
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

# --- Checker.java: منطق هشدار عیناً همان است، فقط کارهای بی‌مصرف حذف شده ---
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
import android.os.Build;

public class Checker {

    static final String CH_STATUS = "status";
    static final String CH_ALERT = "alert2";
    private static boolean channelsReady = false;

    // یادگاری‌های ساده در حافظه، برای اینکه کار تکراری انجام نشود
    private static String lastStatusText = null;
    private static long lastAlarmSetAt = 0;

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
     * همان روش قبلی: سیستم هر بار که وضعیت باتری عوض شود این Intent را می‌فرستد
     * و همان لحظه اینجا پردازش می‌شود. شرط‌های هشدار و تکرارشان هیچ تغییری نکرده‌اند.
     *
     * تنها تفاوت: اندروید این پخش را هر چند ثانیه می‌فرستد (دما و ولتاژ هم آن را
     * عوض می‌کند)، پس کارهای گران‌قیمت فقط وقتی انجام می‌شوند که واقعاً لازم باشند:
     *   - نوشتن روی حافظه فقط وقتی مقدارش عوض شده
     *   - آپدیت نوتیفیکیشن فقط وقتی متنش عوض شده
     *   - ثبت آلارم پشتیبان حداکثر هر ۱۰ دقیقه یک بار
     */
    static void checkFromIntent(Context c, Intent b) {
        if (b == null) return;
        ensureChannels(c);

        int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        if (level < 0 || scale <= 0) return;
        int percent = (int) (level * 100L / scale);
        boolean charging = b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;

        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        int high = p.getInt("high", 80);
        int low = p.getInt("low", 20);

        if (charging && percent >= high) {
            if (now - p.getLong("lastHigh", 0) > p.getInt("repHigh", 5) * 60000L) {
                p.edit().putLong("lastHigh", now).putLong("lastLow", 0).apply();
                alert(c, 2, "شارژر را جدا کن", "باتری به " + percent + "٪ رسید");
            }
        } else if (!charging && percent <= low) {
            if (now - p.getLong("lastLow", 0) > p.getInt("repLow", 10) * 60000L) {
                p.edit().putLong("lastLow", now).putLong("lastHigh", 0).apply();
                alert(c, 3, "گوشی را به شارژ بزن", "باتری فقط " + percent + "٪ است");
            }
        } else {
            // قبلا این دو مقدار هر چند ثانیه یک بار بی‌دلیل روی حافظه نوشته می‌شدند
            if (p.getLong("lastHigh", 0) != 0 || p.getLong("lastLow", 0) != 0) {
                p.edit().putLong("lastHigh", 0).putLong("lastLow", 0).apply();
            }
        }

        // نوتیفیکیشن وضعیت فقط وقتی عوض شده دوباره فرستاده می‌شود
        String text = "باتری: " + percent + "٪  |  هشدار در: " + high + "٪ و " + low + "٪";
        if (!text.equals(lastStatusText)) {
            lastStatusText = text;
            c.getSystemService(NotificationManager.class).notify(1, status(c, text));
        }

        scheduleRestartAlarm(c);
    }

    static void scheduleRestartAlarm(Context c) {
        scheduleRestartAlarm(c, false);
    }

    /**
     * فقط زنگ خطر پشتیبان: اگر بنا به هر دلیلی سرویس اصلی کشته شد،
     * حداکثر ۱۵ دقیقه بعد دوباره روشنش می‌کند تا گیرنده‌ی لحظه‌ای دوباره ثبت شود.
     *
     * تا وقتی سرویس سلامت است این آلارم مرتب به جلو هل داده می‌شود و عملا هیچ‌وقت
     * زنگ نمی‌زند (مثل قبل)، ولی حالا به جای هزاران بار در روز، فقط هر ۱۰ دقیقه
     * یک بار ثبت می‌شود.
     */
    static void scheduleRestartAlarm(Context c, boolean force) {
        long now = System.currentTimeMillis();
        if (!force && now - lastAlarmSetAt < 10 * 60000L) return;
        lastAlarmSetAt = now;

        AlarmManager am = c.getSystemService(AlarmManager.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 10,
                new Intent(c, BootReceiver.class).setAction("ir.batteryalert.app.RESTART"),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long at = now + 15 * 60000L;

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

# --- BatteryService.java: مثل قبل، فقط موقع مرگ سرویس آلارم را قطعی ثبت می‌کند ---
cat > app/src/main/java/ir/batteryalert/app/BatteryService.java << 'EOF_SERVICE'
package ir.batteryalert.app;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.IBinder;

/**
 * این سرویس همیشه زنده می‌ماند و مستقیماً روی پخش سیستمی ACTION_BATTERY_CHANGED
 * ثبت‌نام می‌کند، پس درصد باتری بدون هیچ تاخیری دریافت می‌شود. (بدون تغییر)
 */
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
        // این تابع خودش بلافاصله آخرین وضعیت باتری را برمی‌گرداند (sticky broadcast)
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
        // اگر سیستم سرویس را کشت، آلارم پشتیبان دوباره روشنش می‌کند
        Checker.scheduleRestartAlarm(this, true);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
EOF_SERVICE

echo "در حال ارسال به گیت‌هاب..."
git add -A
git commit -m "نسخه 1.7 - کاهش مصرف باتری: حذف نوشتن و آپدیت و آلارم‌های تکراری بی‌فایده"
git push origin main

echo ""
echo "=================================="
echo "  تمام شد!"
echo "=================================="
echo ""
echo "منطق هشدارها هیچ تغییری نکرده. فقط سه کار بی‌فایده که هر چند ثانیه"
echo "یک بار انجام می‌شد حذف شد:"
echo "  ۱) نوشتن روی حافظه وقتی مقدارش همان بود"
echo "  ۲) فرستادن دوباره‌ی نوتیفیکیشن وضعیت وقتی متنش همان بود"
echo "  ۳) ثبت هزاران آلارم پشتیبان (حالا هر ۱۰ دقیقه یک بار)"
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
