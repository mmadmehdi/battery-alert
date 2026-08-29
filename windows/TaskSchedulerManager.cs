using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace BatteryAlert
{
    public static class TaskSchedulerManager
    {
        private const string TaskName = "BatteryAlertWakeCheck";

        /// <returns>false فقط وقتی که کاربر خواسته فعال باشد ولی ساختن تسک شکست بخورد</returns>
        public static bool Apply(bool enabled, int intervalMinutes)
        {
            if (enabled)
                return Create(intervalMinutes);
            Remove();
            return true;
        }

        private static bool Create(int intervalMinutes)
        {
            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string xmlPath = Path.Combine(Path.GetTempPath(), "battery-alert-wake-task.xml");

            string xml = $@"<?xml version=""1.0"" encoding=""UTF-16""?>
<Task version=""1.2"" xmlns=""http://schemas.microsoft.com/windows/2004/02/mit/task"">
  <Triggers>
    <TimeTrigger>
      <Repetition>
        <Interval>PT{intervalMinutes}M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2020-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id=""Author"">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <WakeToRun>true</WakeToRun>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
  </Settings>
  <Actions Context=""Author"">
    <Exec>
      <Command>""{exePath}""</Command>
      <Arguments>--check</Arguments>
    </Exec>
  </Actions>
</Task>";
            try
            {
                File.WriteAllText(xmlPath, xml, Encoding.Unicode);
                bool ok = RunSchtasks($"/Create /TN \"{TaskName}\" /XML \"{xmlPath}\" /F");
                try { File.Delete(xmlPath); } catch { }
                return ok;
            }
            catch
            {
                return false;
            }
        }

        private static void Remove()
        {
            RunSchtasks($"/Delete /TN \"{TaskName}\" /F");
        }

        private static bool RunSchtasks(string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo("schtasks.exe", arguments)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using Process p = Process.Start(psi);
                p.WaitForExit(5000);
                return p.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }
    }
}
