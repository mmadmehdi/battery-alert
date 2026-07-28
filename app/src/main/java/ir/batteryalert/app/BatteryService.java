package ir.batteryalert.app;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.IBinder;

/**
 * این سرویس همیشه زنده می‌ماند (همان نوتیفیکیشن کم‌اهمیت قبلی) و مستقیماً روی
 * پخش سیستمی ACTION_BATTERY_CHANGED ثبت‌نام می‌کند. اندروید این پخش را همان
 * لحظه‌ای که درصد باتری حتی یک واحد تغییر کند یا شارژر وصل/قطع شود می‌فرستد،
 * پس دیگر نیازی به "هر چند دقیقه یک بار پرسیدن" نیست و دیگر تاخیری در دریافت
 * درصد باتری وجود ندارد.
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
        Checker.scheduleRestartAlarm(this);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
