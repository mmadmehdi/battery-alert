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
