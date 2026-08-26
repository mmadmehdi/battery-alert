using Microsoft.Win32;

namespace BatteryAlert
{
    public static class StartupManager
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "BatteryAlert";

        public static void Apply(bool enabled)
        {
            using RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, true);
            if (key == null) return;

            if (enabled)
            {
                string exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
                key.SetValue(ValueName, $"\"{exePath}\"");
            }
            else if (key.GetValue(ValueName) != null)
            {
                key.DeleteValue(ValueName);
            }
        }
    }
}
