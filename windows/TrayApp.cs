using System;
using System.Drawing;
using System.IO;
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
        private SoundPlayer _customSound;

        public TrayApp()
        {
            _settings = SettingsStore.Load();
            StartupManager.Apply(_settings.RunAtStartup);
            LoadCustomSound();

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

            SystemEvents.PowerModeChanged += OnPowerModeChanged;

            _timer = new Timer { Interval = 30000 };
            _timer.Tick += (s, e) => _monitor.Check();
            _timer.Start();

            _monitor.Check();
        }

        private void LoadCustomSound()
        {
            _customSound?.Dispose();
            _customSound = null;
            if (!string.IsNullOrEmpty(_settings.SoundPath) && File.Exists(_settings.SoundPath))
            {
                try
                {
                    _customSound = new SoundPlayer(_settings.SoundPath);
                    _customSound.Load();
                }
                catch
                {
                    _customSound = null;
                }
            }
        }

        private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e) => _monitor.Check();

        private void ShowAlert(string title, string text)
        {
            _tray.BalloonTipTitle = title;
            _tray.BalloonTipText = text;
            _tray.BalloonTipIcon = ToolTipIcon.Warning;
            _tray.ShowBalloonTip(8000);

            if (_customSound != null)
            {
                try
                {
                    _customSound.Play();
                    return;
                }
                catch
                {
                    // اگر پخش فایل دلخواه با خطا مواجه شد، به صدای پیش‌فرض برمی‌گردیم
                }
            }
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
                LoadCustomSound();
                _monitor.Check();
            }
        }

        private void ExitApp()
        {
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            _customSound?.Dispose();
            _tray.Visible = false;
            Application.Exit();
        }
    }
}
