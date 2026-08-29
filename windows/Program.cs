using System;
using System.Drawing;
using System.IO;
using System.Media;
using System.Windows.Forms;

namespace BatteryAlert
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.SetHighDpiMode(HighDpiMode.SystemAware);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (args.Length > 0 && args[0] == "--check")
            {
                RunSilentCheck();
                return;
            }

            Application.Run(new TrayApp());
        }

        /// <summary>
        /// این حالت وقتی اجرا می‌شود که تسک زمان‌بند ویندوز سیستم را از خواب بیدار کرده
        /// تا باتری چک شود. فقط یک بار چک می‌کند، اگر لازم بود هشدار می‌دهد، و اگر
        /// هیچ هشداری لازم نبود، سیستم را دوباره فورا به خواب برمی‌گرداند تا باتری
        /// اضافه مصرف نشود.
        /// </summary>
        private static void RunSilentCheck()
        {
            Settings settings = SettingsStore.Load();

            SoundPlayer customSound = null;
            if (!string.IsNullOrEmpty(settings.SoundPath) && File.Exists(settings.SoundPath))
            {
                try { customSound = new SoundPlayer(settings.SoundPath); customSound.Load(); }
                catch { customSound = null; }
            }

            using var tray = new NotifyIcon { Icon = SystemIcons.Information, Visible = true, Text = "هشدار باتری" };
            bool alerted = false;

            var monitor = new BatteryMonitor(settings,
                (title, text) =>
                {
                    alerted = true;
                    tray.BalloonTipTitle = title;
                    tray.BalloonTipText = text;
                    tray.BalloonTipIcon = ToolTipIcon.Warning;
                    tray.ShowBalloonTip(10000);
                    if (customSound != null)
                    {
                        try { customSound.Play(); }
                        catch { SystemSounds.Exclamation.Play(); }
                    }
                    else
                    {
                        SystemSounds.Exclamation.Play();
                    }
                },
                _ => { });

            monitor.Check();

            // مدتی صبر می‌کنیم تا نوتیفیکیشن و صدا واقعا فرصت اجرا شدن داشته باشند
            var ctx = new ApplicationContext();
            var waitTimer = new Timer { Interval = alerted ? 12000 : 2000 };
            waitTimer.Tick += (s, e) => { waitTimer.Stop(); ctx.ExitThread(); };
            waitTimer.Start();
            Application.Run(ctx);

            tray.Visible = false;
            customSound?.Dispose();

            if (!alerted)
            {
                // چیزی برای هشدار دادن نبود؛ سیستم را دوباره سریع بخوابان
                NativeMethods.SetSuspendState(false, true, false);
            }
        }
    }
}
