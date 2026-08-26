using System;
using System.Management;

namespace BatteryAlert
{
    /// <summary>
    /// ویندوز هیچ رابط رسمی و یکسانی برای «دمای دقیق سلول باتری» ندارد (برخلاف اندروید).
    /// این کلاس با WMI سعی می‌کند دمای ناحیه‌ی حرارتی ACPI را بخواند که معمولا نزدیک به
    /// دمای مادربرد/سیستم است، نه لزوما خود باتری، و روی خیلی از لپ‌تاپ‌ها (مخصوصا
    /// مدل‌های جدید با کنترلر اختصاصی) اصلا در دسترس نیست یا عدد غیرواقعی می‌دهد.
    /// </summary>
    public static class TemperatureReader
    {
        public static double? TryReadCelsius()
        {
            try
            {
                using var searcher = new ManagementObjectSearcher(
                    @"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
                foreach (ManagementObject obj in searcher.Get())
                {
                    object raw = obj["CurrentTemperature"];
                    if (raw == null) continue;
                    double kelvinTenths = Convert.ToDouble(raw);
                    double celsius = (kelvinTenths / 10.0) - 273.15;
                    if (celsius > -50 && celsius < 150)
                        return celsius;
                }
            }
            catch
            {
                // نبود این قابلیت روی خیلی از سیستم‌ها کاملا طبیعی است
            }
            return null;
        }
    }
}
