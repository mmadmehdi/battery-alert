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
