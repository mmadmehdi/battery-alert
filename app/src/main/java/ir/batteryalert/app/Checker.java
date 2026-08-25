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
