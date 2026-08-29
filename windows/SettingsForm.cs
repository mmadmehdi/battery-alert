using System.Collections.Generic;
using System.Media;
using System.Windows.Forms;

namespace BatteryAlert
{
    public class SettingsForm : Form
    {
        public Settings Result { get; private set; }

        private CheckBox _enableHigh, _enableLow, _enableTemp, _tempWhileCharging, _runAtStartup, _wakeFromSleep;
        private NumericUpDown _high, _low, _tempHigh, _repHigh, _repLow, _repTemp, _wakeInterval;
        private ListBox _quietList;
        private readonly List<QuietPeriod> _quietPeriods;
        private Button _testTempBtn;
        private Label _testTempResult;
        private Label _soundPathLabel;
        private string _soundPath;

        public SettingsForm(Settings current)
        {
            Result = Clone(current);
            _quietPeriods = new List<QuietPeriod>(current.QuietPeriods);
            _soundPath = current.SoundPath;

            Text = "تنظیمات هشدار باتری";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Width = 480;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScroll = true;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;

            var layout = new TableLayoutPanel
            {
                Dock = DockStyle.Top,
                ColumnCount = 2,
                AutoSize = true,
                Padding = new Padding(12)
            };

            _enableHigh = AddCheck(layout, "هشدار شارژ بالا فعال باشد", current.EnableHigh);
            _high = AddNumeric(layout, "هشدار شارژ بالا (٪)", current.High, 1, 100);
            _enableLow = AddCheck(layout, "هشدار شارژ پایین فعال باشد", current.EnableLow);
            _low = AddNumeric(layout, "هشدار شارژ پایین (٪)", current.Low, 0, 99);

            _enableTemp = AddCheck(layout, "هشدار دمای باتری فعال باشد (تجربی، شاید نیاز به اجرا با دسترسی ادمین داشته باشد)", current.EnableTemp);
            _tempWhileCharging = AddCheck(layout, "هشدار دما در حالت شارژ هم فعال باشد", current.TempWhileCharging);
            _tempHigh = AddNumeric(layout, "هشدار دما (سانتی‌گراد)", current.TempHigh, 30, 90);

            _repHigh = AddNumeric(layout, "تکرار هشدار شارژ بالا (دقیقه)", current.RepHighMinutes, 1, 60);
            _repLow = AddNumeric(layout, "تکرار هشدار شارژ پایین (دقیقه)", current.RepLowMinutes, 1, 120);
            _repTemp = AddNumeric(layout, "تکرار هشدار دما (دقیقه)", current.RepTempMinutes, 1, 60);

            _runAtStartup = AddCheck(layout, "اجرای خودکار هنگام روشن شدن ویندوز", current.RunAtStartup);

            _wakeFromSleep = AddCheck(layout, "در حالت خواب هم سیستم بیدار شود و باتری چک شود", current.WakeFromSleep);
            _wakeInterval = AddNumeric(layout, "فاصله‌ی بیدار شدن در خواب (دقیقه)", current.WakeIntervalMinutes, 5, 60);

            Controls.Add(layout);

            _testTempBtn = new Button { Text = "تست خواندن دما روی این سیستم", Left = 12, Top = layout.PreferredSize.Height + 12, Width = 220 };
            _testTempResult = new Label { Left = 240, Top = _testTempBtn.Top + 4, Width = 210, AutoSize = true };
            _testTempBtn.Click += (s, e) =>
            {
                double? t = TemperatureReader.TryReadCelsius();
                _testTempResult.Text = t.HasValue ? $"نتیجه: {t.Value:0.0}°C" : "دما در این سیستم در دسترس نیست";
            };
            Controls.Add(_testTempBtn);
            Controls.Add(_testTempResult);

            var soundTitle = new Label { Text = "صدای هشدار:", Left = 12, Top = _testTempBtn.Bottom + 14, AutoSize = true };
            Controls.Add(soundTitle);

            _soundPathLabel = new Label
            {
                Left = 12,
                Top = soundTitle.Bottom + 4,
                Width = 440,
                Height = 20,
                Text = string.IsNullOrEmpty(_soundPath) ? "صدای پیش‌فرض ویندوز" : _soundPath
            };
            Controls.Add(_soundPathLabel);

            var chooseSoundBtn = new Button { Text = "انتخاب فایل صدا (wav)", Left = 12, Top = _soundPathLabel.Bottom + 6, Width = 160 };
            chooseSoundBtn.Click += (s, e) =>
            {
                using var dlg = new OpenFileDialog { Filter = "فایل صوتی (*.wav)|*.wav" };
                if (dlg.ShowDialog() == DialogResult.OK)
                {
                    _soundPath = dlg.FileName;
                    _soundPathLabel.Text = _soundPath;
                }
            };
            Controls.Add(chooseSoundBtn);

            var testSoundBtn = new Button { Text = "پخش آزمایشی", Left = 180, Top = _soundPathLabel.Bottom + 6, Width = 110 };
            testSoundBtn.Click += (s, e) =>
            {
                if (!string.IsNullOrEmpty(_soundPath) && System.IO.File.Exists(_soundPath))
                {
                    try { new SoundPlayer(_soundPath).Play(); }
                    catch { MessageBox.Show("پخش این فایل ممکن نشد.", "خطا"); }
                }
                else
                {
                    SystemSounds.Exclamation.Play();
                }
            };
            Controls.Add(testSoundBtn);

            var clearSoundBtn = new Button { Text = "بازگشت به صدای پیش‌فرض", Left = 300, Top = _soundPathLabel.Bottom + 6, Width = 150 };
            clearSoundBtn.Click += (s, e) =>
            {
                _soundPath = "";
                _soundPathLabel.Text = "صدای پیش‌فرض ویندوز";
            };
            Controls.Add(clearSoundBtn);

            var quietLabel = new Label { Text = "بازه‌های سکوت:", Left = 12, Top = clearSoundBtn.Bottom + 14, AutoSize = true };
            Controls.Add(quietLabel);

            _quietList = new ListBox { Left = 12, Top = quietLabel.Bottom + 4, Width = 440, Height = 110 };
            Controls.Add(_quietList);
            RefreshQuietList();

            var addQuietBtn = new Button { Text = "+ افزودن بازه‌ی جدید", Left = 12, Top = _quietList.Bottom + 8, Width = 160 };
            addQuietBtn.Click += (s, e) => ShowAddQuietDialog();
            Controls.Add(addQuietBtn);

            var removeQuietBtn = new Button { Text = "حذف بازه‌ی انتخاب‌شده", Left = 180, Top = _quietList.Bottom + 8, Width = 160 };
            removeQuietBtn.Click += (s, e) =>
            {
                if (_quietList.SelectedIndex >= 0)
                {
                    _quietPeriods.RemoveAt(_quietList.SelectedIndex);
                    RefreshQuietList();
                }
            };
            Controls.Add(removeQuietBtn);

            var okBtn = new Button { Text = "ذخیره", Left = 12, Top = removeQuietBtn.Bottom + 16, Width = 100, DialogResult = DialogResult.OK };
            okBtn.Click += (s, e) => SaveClicked();
            Controls.Add(okBtn);

            var cancelBtn = new Button { Text = "انصراف", Left = 120, Top = removeQuietBtn.Bottom + 16, Width = 100, DialogResult = DialogResult.Cancel };
            Controls.Add(cancelBtn);

            AcceptButton = okBtn;
            CancelButton = cancelBtn;
            Height = cancelBtn.Bottom + 90;
        }

        private CheckBox AddCheck(TableLayoutPanel layout, string label, bool value)
        {
            var cb = new CheckBox { Text = label, Checked = value, AutoSize = true };
            layout.Controls.Add(cb, 0, layout.RowCount);
            layout.SetColumnSpan(cb, 2);
            layout.RowCount++;
            return cb;
        }

        private NumericUpDown AddNumeric(TableLayoutPanel layout, string label, int value, int min, int max)
        {
            var lbl = new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(3, 8, 3, 3) };
            var num = new NumericUpDown { Minimum = min, Maximum = max, Value = value, Width = 80 };
            layout.Controls.Add(lbl, 0, layout.RowCount);
            layout.Controls.Add(num, 1, layout.RowCount);
            layout.RowCount++;
            return num;
        }

        private void RefreshQuietList()
        {
            _quietList.Items.Clear();
            foreach (QuietPeriod q in _quietPeriods)
            {
                string what = q.Battery && q.Temp ? "باتری و دما" : (q.Battery ? "باتری" : "دما");
                _quietList.Items.Add($"از {q.Start / 60:00}:{q.Start % 60:00} تا {q.End / 60:00}:{q.End % 60:00} — خاموش: {what}");
            }
        }

        private void ShowAddQuietDialog()
        {
            using var dlg = new Form
            {
                Text = "افزودن بازه‌ی سکوت",
                Width = 320,
                Height = 260,
                RightToLeft = RightToLeft.Yes,
                RightToLeftLayout = true,
                StartPosition = FormStartPosition.CenterParent,
                FormBorderStyle = FormBorderStyle.FixedDialog,
                MaximizeBox = false,
                MinimizeBox = false
            };

            var startH = new NumericUpDown { Minimum = 0, Maximum = 23, Left = 20, Top = 20, Width = 60 };
            var startM = new NumericUpDown { Minimum = 0, Maximum = 59, Left = 90, Top = 20, Width = 60 };
            dlg.Controls.Add(new Label { Text = "شروع (ساعت / دقیقه)", Left = 160, Top = 22, AutoSize = true });
            dlg.Controls.Add(startH);
            dlg.Controls.Add(startM);

            var endH = new NumericUpDown { Minimum = 0, Maximum = 23, Left = 20, Top = 55, Width = 60 };
            var endM = new NumericUpDown { Minimum = 0, Maximum = 59, Left = 90, Top = 55, Width = 60 };
            dlg.Controls.Add(new Label { Text = "پایان (ساعت / دقیقه)", Left = 160, Top = 57, AutoSize = true });
            dlg.Controls.Add(endH);
            dlg.Controls.Add(endM);

            var bCheck = new CheckBox { Text = "خاموش کردن هشدار باتری", Left = 20, Top = 95, AutoSize = true };
            var tCheck = new CheckBox { Text = "خاموش کردن هشدار دما", Left = 20, Top = 120, AutoSize = true };
            dlg.Controls.Add(bCheck);
            dlg.Controls.Add(tCheck);

            var addBtn = new Button { Text = "افزودن", Left = 20, Top = 160, Width = 100, DialogResult = DialogResult.OK };
            var cancelBtn = new Button { Text = "انصراف", Left = 130, Top = 160, Width = 100, DialogResult = DialogResult.Cancel };
            dlg.Controls.Add(addBtn);
            dlg.Controls.Add(cancelBtn);
            dlg.AcceptButton = addBtn;
            dlg.CancelButton = cancelBtn;

            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                if (!bCheck.Checked && !tCheck.Checked)
                {
                    MessageBox.Show("حداقل یکی از باتری یا دما را انتخاب کن", "خطا");
                    return;
                }
                _quietPeriods.Add(new QuietPeriod
                {
                    Start = (int)startH.Value * 60 + (int)startM.Value,
                    End = (int)endH.Value * 60 + (int)endM.Value,
                    Battery = bCheck.Checked,
                    Temp = tCheck.Checked
                });
                RefreshQuietList();
            }
        }

        private void SaveClicked()
        {
            if ((int)_low.Value >= (int)_high.Value)
            {
                MessageBox.Show("عدد پایین باید کمتر از عدد بالا باشد", "خطا");
                DialogResult = DialogResult.None;
                return;
            }

            Result.EnableHigh = _enableHigh.Checked;
            Result.EnableLow = _enableLow.Checked;
            Result.EnableTemp = _enableTemp.Checked;
            Result.TempWhileCharging = _tempWhileCharging.Checked;
            Result.High = (int)_high.Value;
            Result.Low = (int)_low.Value;
            Result.TempHigh = (int)_tempHigh.Value;
            Result.RepHighMinutes = (int)_repHigh.Value;
            Result.RepLowMinutes = (int)_repLow.Value;
            Result.RepTempMinutes = (int)_repTemp.Value;
            Result.RunAtStartup = _runAtStartup.Checked;
            Result.SoundPath = _soundPath;
            Result.WakeFromSleep = _wakeFromSleep.Checked;
            Result.WakeIntervalMinutes = (int)_wakeInterval.Value;
            Result.QuietPeriods = _quietPeriods;
        }

        private static Settings Clone(Settings s) => new Settings
        {
            EnableHigh = s.EnableHigh,
            EnableLow = s.EnableLow,
            EnableTemp = s.EnableTemp,
            TempWhileCharging = s.TempWhileCharging,
            High = s.High,
            Low = s.Low,
            TempHigh = s.TempHigh,
            RepHighMinutes = s.RepHighMinutes,
            RepLowMinutes = s.RepLowMinutes,
            RepTempMinutes = s.RepTempMinutes,
            RunAtStartup = s.RunAtStartup,
            SoundPath = s.SoundPath,
            WakeFromSleep = s.WakeFromSleep,
            WakeIntervalMinutes = s.WakeIntervalMinutes,
            QuietPeriods = new List<QuietPeriod>(s.QuietPeriods)
        };
    }
}
