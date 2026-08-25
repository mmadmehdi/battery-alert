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
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {

    private CheckBox enableHighBox, enableLowBox, enableTempBox, tempWhileChargingBox;
    private EditText highInput, lowInput;
    private EditText repHighInput, repLowInput;
    private EditText tempHighInput, repTempInput;

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

        enableHighBox = addCheck(root, "\nهشدار شارژ بالا فعال باشد", prefs.getBoolean("enableHigh", true));
        highInput = addField(root, "هشدار شارژ بالا (درصد) — موقع شارژ شدن:", prefs.getInt("high", 80));

        enableLowBox = addCheck(root, "\nهشدار شارژ پایین فعال باشد", prefs.getBoolean("enableLow", true));
        lowInput = addField(root, "هشدار شارژ پایین (درصد) — موقع خالی شدن:", prefs.getInt("low", 20));

        enableTempBox = addCheck(root, "\nهشدار دمای باتری فعال باشد", prefs.getBoolean("enableTemp", true));
        tempWhileChargingBox = addCheck(root, "هشدار دما در حالت شارژ هم فعال باشد", prefs.getBoolean("tempWhileCharging", true));
        tempHighInput = addField(root, "هشدار دمای باتری (سانتی‌گراد):", prefs.getInt("tempHigh", 45));

        Button settingsBtn = new Button(this);
        settingsBtn.setText("تنظیمات تکرار هشدار");
        root.addView(settingsBtn);

        LinearLayout adv = new LinearLayout(this);
        adv.setOrientation(LinearLayout.VERTICAL);
        adv.setVisibility(View.GONE);
        root.addView(adv);

        settingsBtn.setOnClickListener(v ->
                adv.setVisibility(adv.getVisibility() == View.GONE ? View.VISIBLE : View.GONE));

        repHighInput = addField(adv, "هشدار شارژ بالا هر چند دقیقه تکرار شود؟", prefs.getInt("repHigh", 5));
        repLowInput = addField(adv, "هشدار شارژ پایین هر چند دقیقه تکرار شود؟", prefs.getInt("repLow", 10));
        repTempInput = addField(adv, "هشدار دما هر چند دقیقه تکرار شود؟", prefs.getInt("repTemp", 5));

        Button save = new Button(this);
        save.setText("ذخیره و شروع");
        save.setOnClickListener(v -> {
            int high = clamp(parseOr(highInput, 80), 1, 100);
            int low = clamp(parseOr(lowInput, 20), 0, 99);
            if (low >= high) {
                Toast.makeText(this, "عدد پایین باید کمتر از عدد بالا باشد", Toast.LENGTH_LONG).show();
                return;
            }
            int tempHigh = clamp(parseOr(tempHighInput, 45), 30, 60);
            prefs.edit()
                    .putBoolean("enableHigh", enableHighBox.isChecked())
                    .putBoolean("enableLow", enableLowBox.isChecked())
                    .putBoolean("enableTemp", enableTempBox.isChecked())
                    .putBoolean("tempWhileCharging", tempWhileChargingBox.isChecked())
                    .putInt("high", high)
                    .putInt("low", low)
                    .putInt("tempHigh", tempHigh)
                    .putInt("repHigh", clamp(parseOr(repHighInput, 5), 1, 60))
                    .putInt("repLow", clamp(parseOr(repLowInput, 10), 1, 120))
                    .putInt("repTemp", clamp(parseOr(repTempInput, 5), 1, 60))
                    .apply();
            startBatteryService();
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
        hint.setText("\nهر سه هشدار (شارژ بالا، شارژ پایین، دما) کاملا مستقل از هم روشن یا خاموش می‌شوند. خاموش کردن یکی، تاثیری روی بقیه ندارد.\n\nحد پیش‌فرض دما ۴۵ درجه سانتی‌گراد است.\n\nنکته مهم شیائومی: در صفحه برنامه‌های اخیر، این اپ را قفل کن تا سیستم آن را نبندد.");
        root.addView(hint);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);

        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                   != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1);
        }

        startBatteryService();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        startBatteryService();
    }

    private void startBatteryService() {
        Intent i = new Intent(this, BatteryService.class);
        if (Build.VERSION.SDK_INT >= 26) {
            startForegroundService(i);
        } else {
            startService(i);
        }
    }

    private CheckBox addCheck(LinearLayout parent, String label, boolean value) {
        CheckBox cb = new CheckBox(this);
        cb.setText(label);
        cb.setChecked(value);
        parent.addView(cb);
        return cb;
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
