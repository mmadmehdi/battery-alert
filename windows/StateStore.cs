using System;
using System.IO;
using System.Text.Json;

namespace BatteryAlert
{
    public static class StateStore
    {
        private static string FilePath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "BatteryAlert", "state.json");

        public static AlertState Load()
        {
            try
            {
                if (File.Exists(FilePath))
                {
                    string json = File.ReadAllText(FilePath);
                    var s = JsonSerializer.Deserialize<AlertState>(json);
                    if (s != null) return s;
                }
            }
            catch
            {
            }
            return new AlertState();
        }

        public static void Save(AlertState s)
        {
            try
            {
                string dir = Path.GetDirectoryName(FilePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                    Directory.CreateDirectory(dir);
                string json = JsonSerializer.Serialize(s);
                File.WriteAllText(FilePath, json);
            }
            catch
            {
            }
        }
    }
}
