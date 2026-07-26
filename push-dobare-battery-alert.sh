#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "در حال ارسال دوباره به گیت‌هاب..."

if [ ! -d ~/battery-alert/.git ]; then
  echo "پوشه پروژه پیدا نشد!"
  exit 1
fi

cd ~/battery-alert
git push origin main --force

echo ""
echo "=================================="
echo "  تمام شد!"
echo "=================================="
echo ""
echo "۱) صبر کن تیک سبز بیاید:"
echo "   https://github.com/mmadmehdi/battery-alert/actions"
echo ""
echo "۲) جدیدترین نسخه (بالاترین شماره) را دانلود کن:"
echo "   https://github.com/mmadmehdi/battery-alert/releases"
echo ""
echo "۳) اپ قبلی را حذف کن، نسخه جدید را نصب کن،"
echo "   اجازه‌ها و عددها را بده و اپ را در برنامه‌های اخیر قفل کن."
echo ""
