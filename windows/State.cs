using System;

namespace BatteryAlert
{
    /// <summary>
    /// چون هر بار که سیستم برای چک کردن بیدار می‌شود، برنامه به‌صورت یک پردازش
    /// کاملا تازه اجرا می‌شود (نه ادامه‌ی همان پردازش قبلی)، زمان آخرین هشدارها
    /// باید روی دیسک ذخیره شود تا فاصله‌ی تکرار هشدار درست رعایت شود.
    /// </summary>
    public class AlertState
    {
        public DateTime LastHigh { get; set; } = DateTime.MinValue;
        public DateTime LastLow { get; set; } = DateTime.MinValue;
        public DateTime LastTemp { get; set; } = DateTime.MinValue;
    }
}
