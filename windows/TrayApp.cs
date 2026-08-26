using System;
using System.Drawing;
using System.Media;
using System.Windows.Forms;
using Microsoft.Win32;

namespace BatteryAlert
{
    public class TrayApp : ApplicationContext
    {
        private readonly NotifyIcon _tray;
        private readonly Timer _timer;
        private readonly BatteryMonitor _monitor;
        private Settings _settings;

        public TrayApp()
        {
            _settings = SettingsStore.Load();
            StartupManager.Apply(_settings.RunAtStartup);

            _tray = new NotifyIcon
            {
                Icon = SystemIcons.Information,
                Visible = true,
                Text = "هشدار باتری"
            };

            var menu = new ContextMenuStrip();
            menu.Items.Add("تنظیمات", null, (s, e) => OpenSettings());
            menu.Items.Add("خروج", null, (s, e) => ExitApp());
            _tray.ContextMenuStrip = menu;
            _tray.DoubleClick += (s, e) => OpenSettings();

            _monitor = new BatteryMonitor(_settings, ShowAlert, UpdateStatus);

            // این بخش معادل ثبت‌نام لحظه‌ای اندروید است: هر بار وضعیت برق سیستم
            // (وصل/قطع شارژر، خواب/بیداری) تغییر کند، بلافاصله چک می‌کند.
            SystemEvents.PowerModeChanged += OnPowerModeChanged;

            // چون ویندوز برخلاف اندروید، پخش رسمی «هر تغییر ۱ درصدی» ندارد، این تایمر
            // به‌عنوان تضمین اضافه، هر ۳۰ ثانیه هم چک می‌کند (روی سیستم رومیزی این
            // فاصله عملا بی‌اهمیت و کاملا سبک است).
            _timer = new Timer { Interval = 30000 };
            _timer.Tick += (s, e) => _monitor.Check();
            _timer.Start();

            _monitor.Check();
        }

        private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e) => _monitor.Check();

        private void ShowAlert(string title, string text)
        {
            _tray.BalloonTipTitle = title;
            _tray.BalloonTipText = text;
            _tray.BalloonTipIcon = ToolTipIcon.Warning;
            _tray.ShowBalloonTip(8000);
            SystemSounds.Exclamation.Play();
        }

        private void UpdateStatus(string text)
        {
            _tray.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private void OpenSettings()
        {
            using var form = new SettingsForm(_settings);
            if (form.ShowDialog() == DialogResult.OK)
            {
                _settings = form.Result;
                SettingsStore.Save(_settings);
                _monitor.UpdateSettings(_settings);
                StartupManager.Apply(_settings.RunAtStartup);
                _monitor.Check();
            }
        }

        private void ExitApp()
        {
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            _tray.Visible = false;
            Application.Exit();
        }
    }
}
