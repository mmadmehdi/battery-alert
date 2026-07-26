package ir.batteryalert.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.BatteryManager;
import android.os.IBinder;

public class BatteryService extends Service {

    private static final String CH_STATUS = "status";
    private static final String CH_ALERT = "alert";

    private boolean alertedHigh = false;
    private boolean alertedLow = false;
    private BroadcastReceiver receiver;

    @Override
    public void onCreate() {
        super.onCreate();

        NotificationManager nm = getSystemService(NotificationManager.class);

        NotificationChannel status = new NotificationChannel(
                CH_STATUS, "وضعیت باتری", NotificationManager.IMPORTANCE_MIN);
        status.setShowBadge(false);
        nm.createNotificationChannel(status);

        NotificationChannel alert = new NotificationChannel(
                CH_ALERT, "هشدار فوری باتری", NotificationManager.IMPORTANCE_HIGH);
        alert.enableVibration(true);
        nm.createNotificationChannel(alert);

        startForeground(1, buildStatus("در حال زیر نظر گرفتن باتری..."));

        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                handleBattery(intent);
            }
        };
        registerReceiver(receiver, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
    }

    private void handleBattery(Intent intent) {
        int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        if (level < 0 || scale <= 0) return;
        int percent = (int) (level * 100L / scale);

        int plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0);
        boolean charging = plugged != 0;

        SharedPreferences prefs = getSharedPreferences("settings", MODE_PRIVATE);
        int high = prefs.getInt("high", 80);
        int low = prefs.getInt("low", 20);

        if (charging) {
            alertedLow = false;
            if (percent >= high && !alertedHigh) {
                alertedHigh = true;
                sendAlert(2, "شارژر را جدا کن", "باتری به " + percent + "٪ رسید");
            }
        } else {
            alertedHigh = false;
            if (percent <= low && !alertedLow) {
                alertedLow = true;
                sendAlert(3, "گوشی را به شارژ بزن", "باتری فقط " + percent + "٪ است");
            }
        }

        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.notify(1, buildStatus("باتری: " + percent + "٪  |  هشدار در: " + high + "٪ و " + low + "٪"));
    }

    private Notification buildStatus(String text) {
        Intent i = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CH_STATUS)
                .setSmallIcon(android.R.drawable.ic_lock_idle_charging)
                .setContentTitle("هشدار باتری فعال است")
                .setContentText(text)
                .setOngoing(true)
                .setContentIntent(pi)
                .build();
    }

    private void sendAlert(int id, String title, String text) {
        Intent i = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, 1, i, PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(this, CH_ALERT)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build();
        getSystemService(NotificationManager.class).notify(id, n);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(1, buildStatus("در حال زیر نظر گرفتن باتری..."));
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
