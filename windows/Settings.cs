using System.Collections.Generic;

namespace BatteryAlert
{
    public class QuietPeriod
    {
        public int Start { get; set; }
        public int End { get; set; }
        public bool Battery { get; set; }
        public bool Temp { get; set; }
    }

    public class Settings
    {
        public bool EnableHigh { get; set; } = true;
        public bool EnableLow { get; set; } = true;

        public bool EnableTemp { get; set; } = false;
        public bool TempWhileCharging { get; set; } = true;

        public int High { get; set; } = 80;
        public int Low { get; set; } = 20;
        public int TempHigh { get; set; } = 45;

        public int RepHighMinutes { get; set; } = 5;
        public int RepLowMinutes { get; set; } = 10;
        public int RepTempMinutes { get; set; } = 5;

        public bool RunAtStartup { get; set; } = false;

        // مسیر فایل صدای دلخواه (wav). اگر خالی باشد، صدای پیش‌فرض ویندوز پخش می‌شود.
        public string SoundPath { get; set; } = "";

        public List<QuietPeriod> QuietPeriods { get; set; } = new List<QuietPeriod>();
    }
}
