import os
import glob
import shutil

# ==================== تنظیمات اصلی ====================
# ۱. پسوند مورد نظرت رو اینجا بنویس (بدون نقطه)
EXTENSION = "sh"  

# ۲. مسیر کامل پوشه مقصد رو اینجا وارد کن
DESTINATION_FOLDER = "/storage/emulated/0/Download/sh"
# ====================================================

def move_files():
    # گرفتن مسیر پوشه فعلی
    current_directory = os.getcwd()
    
    # پیدا کردن تمام فایل‌های دارای پسوند مشخص شده
    search_path = os.path.join(current_directory, f"*.{EXTENSION}")
    files_to_move = glob.glob(search_path)
    
    if not files_to_move:
        print(f"❌ هیچ فایلی با پسوند .{EXTENSION} در این پوشه پیدا نشد.")
        return

    # ساخت پوشه مقصد در صورت عدم وجود
    if not os.path.exists(DESTINATION_FOLDER):
        try:
            os.makedirs(DESTINATION_FOLDER)
            print(f"📁 پوشه مقصد وجود نداشت و ساخته شد: {DESTINATION_FOLDER}")
        except Exception as e:
            print(f"⚠️ خطا در ساخت پوشه مقصد: {e}")
            return

    print(f"📦 تعداد {len(files_to_move)} فایل پیدا شد. در حال انتقال...")
    
    # شروع فرآیند انتقال
    for file_path in files_to_move:
        try:
            shutil.move(file_path, DESTINATION_FOLDER)
            file_name = os.path.basename(file_path)
            print(f"✅ منتقل شد: {file_name}")
        except Exception as e:
            print(f"⚠️ خطا در انتقال فایل {os.path.basename(file_path)}: {e}")
            
    print("✨ عملیات انتقال با موفقیت به پایان رسید.")

if __name__ == "__main__":
    move_files()
