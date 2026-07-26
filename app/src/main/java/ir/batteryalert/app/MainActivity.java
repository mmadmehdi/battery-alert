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
