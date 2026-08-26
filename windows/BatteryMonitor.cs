using System;
using System.Windows.Forms;

namespace BatteryAlert
{
    public class BatteryMonitor
    {
        private Settings _settings;
        private readonly Action<string, string> _onAlert;
        private readonly Action<string> _onStatus;

        private DateTime _lastHigh = DateTime.MinValue;
        private DateTime _lastLow = DateTime.MinValue;
        private DateTime _lastTemp = DateTime.MinValue;

        public BatteryMonitor(Settings settings, Action<string, string> onAlert, Action<string> onStatus)
        {
            _settings = settings;
            _onAlert = onAlert;
            _onStatus = onStatus;
        }

        public void UpdateSettings(Settings settings) => _settings = settings;

        public void Check()
        {
            PowerStatus status = SystemInformation.PowerStatus;
            int percent = (int)Math.Round(status.BatteryLifePercent * 100);
            bool charging = status.PowerLineStatus == PowerLineStatus.Online;
            DateTime now = DateTime.Now;

            bool enableHigh = _settings.EnableHigh && !IsSuppressed(true);
            bool enableLow = _settings.EnableLow && !IsSuppressed(true);

            if (enableHigh && charging && percent >= _settings.High)
            {
                if ((now - _lastHigh).TotalMinutes > _settings.RepHighMinutes)
                {
                    _lastHigh = now;
                    _lastLow = DateTime.MinValue;
                    _onAlert("شارژر را جدا کن", $"باتری به {percent}٪ رسید");
                }
            }
            else if (enableLow && !charging && percent <= _settings.Low)
            {
                if ((now - _lastLow).TotalMinutes > _settings.RepLowMinutes)
                {
                    _lastLow = now;
                    _lastHigh = DateTime.MinValue;
                    _onAlert("به شارژر وصل کن", $"باتری فقط {percent}٪ است");
                }
            }
            else
            {
                _lastHigh = DateTime.MinValue;
                _lastLow = DateTime.MinValue;
            }

            string tempText = "";
            if (_settings.EnableTemp)
            {
                double? tempC = TemperatureReader.TryReadCelsius();
                if (tempC.HasValue)
                {
                    tempText = $"  |  دما: {tempC.Value:0.0}°C";
                    bool tempActiveNow = !IsSuppressed(false) && (!charging || _settings.TempWhileCharging);

                    if (tempActiveNow && tempC.Value >= _settings.TempHigh)
                    {
                        if ((now - _lastTemp).TotalMinutes > _settings.RepTempMinutes)
                        {
                            _lastTemp = now;
                            _onAlert("دمای باتری بالا رفت", $"دما به {tempC.Value:0.0}°C رسید");
                        }
                    }
                    else if (!tempActiveNow || tempC.Value < _settings.TempHigh)
                    {
                        _lastTemp = DateTime.MinValue;
                    }
                }
                else
                {
                    tempText = "  |  دما: در دسترس نیست";
                }
            }

            _onStatus($"باتری: {percent}٪{tempText}");
        }

        private bool IsSuppressed(bool forBattery)
        {
            DateTime now = DateTime.Now;
            int nowMin = now.Hour * 60 + now.Minute;
            foreach (QuietPeriod q in _settings.QuietPeriods)
            {
                bool matches = forBattery ? q.Battery : q.Temp;
                if (!matches) continue;
                bool inRange = q.Start <= q.End
                    ? (nowMin >= q.Start && nowMin < q.End)
                    : (nowMin >= q.Start || nowMin < q.End);
                if (inRange) return true;
            }
            return false;
        }
    }
}
