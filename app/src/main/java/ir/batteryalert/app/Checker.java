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
        int repHigh = p.getInt("repHigh", 5);
        int repLow = p.getInt("repLow", 10);
        long now = System.currentTimeMillis();

        if (charging) {
            if (p.getLong("lastLow", 0) != 0) p.edit().putLong("lastLow", 0).apply();
            if (percent >= high) {
                long last = p.getLong("lastHigh", 0);
                if (now - last > repHigh * 60L * 1000L) {
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
                if (now - last > repLow * 60L * 1000L) {
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
        SharedPreferences p = c.getSharedPreferences("settings", Context.MODE_PRIVATE);
        int minutes = charging ? p.getInt("chkCharge", 2) : p.getInt("chkNormal", 10);

        AlarmManager am = c.getSystemService(AlarmManager.class);
        Intent i = new Intent(c, BootReceiver.class).setAction("ir.batteryalert.app.CHECK");
        PendingIntent pi = PendingIntent.getBroadcast(c, 10, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long at = System.currentTimeMillis() + minutes * 60L * 1000L;
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
