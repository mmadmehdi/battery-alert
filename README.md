Battery Alert
=============

Simple battery monitoring tool for Windows with notifications.

Features
--------
- Real-time battery monitoring
- Low battery alert (notification + beep)
- Full battery alert (notification + beep)
- Visual progress bar display
- Easy configuration

Quick Start
-----------
Requirements: Windows 10 / 11 - nothing else needed!

Just double-click on start.bat

Or run from PowerShell with custom settings:

    .\src\battery_alert.ps1 -LowThreshold 20 -FullThreshold 95 -CheckInterval 60

Configuration
-------------
Edit config.ini:

    [settings]
    low_threshold = 20
    full_threshold = 95
    check_interval = 60

Project Structure
-----------------
    battery-alert/
    |-- start.bat          <- double-click this!
    |-- config.ini         <- settings
    |-- src/
    |   +-- battery_alert.ps1
    +-- README.md

License
-------
MIT License
