# Flutter App Setup — SmartVision

## 1. Install Flutter (Windows)

1. Download the Flutter SDK zip: https://docs.flutter.dev/get-started/install/windows
2. Extract it somewhere permanent, e.g. `C:\src\flutter` (NOT Program Files — avoid spaces/special
   permissions issues).
3. Add `C:\src\flutter\bin` to your PATH:
   - Search "Environment Variables" in Windows search → Edit the system environment variables →
     Environment Variables → under "User variables", select `Path` → Edit → New → paste the path.
4. Open a NEW terminal (PATH changes need a fresh terminal) and run:
   ```
   flutter doctor
   ```
   This tells you what's missing. You need Android toolchain at minimum — install "Android Studio"
   if it flags that missing (https://developer.android.com/studio), then re-run `flutter doctor`
   and follow its remaining instructions (accepting licenses: `flutter doctor --android-licenses`).

This step alone can take 1-2 hours depending on your internet speed and machine — don't leave it
to the last day.

## 2. Test on your real phone (skip emulator — faster and it's what you want for the demo anyway)

1. On your Android phone: Settings → About phone → tap "Build number" 7 times to enable Developer
   Options.
2. Settings → Developer Options → enable "USB debugging".
3. Connect phone to laptop via USB cable. Allow the "Allow USB debugging?" popup on your phone.
4. Run `flutter devices` — your phone should be listed. If not, try a different USB cable (some are
   charge-only) or install your phone brand's USB driver.

## 3. Create the project and drop in the provided files

```
flutter create smartvision_app
cd smartvision_app
```

Replace the generated `pubspec.yaml` with the one provided here, and replace `lib/main.dart` with
the one provided here.

Then get packages:
```
flutter pub get
```

## 4. Add permissions (Android)

Open `android/app/src/main/AndroidManifest.xml` in the generated project. Add these lines just
inside the `<manifest>` tag, above `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-feature android:name="android.hardware.camera" android:required="true"/>
```

## 5. Point the app at your laptop's backend

Your phone and laptop must be on the **same WiFi network**. Find your laptop's local IP:
```
ipconfig
```
Look for "IPv4 Address" under your WiFi adapter (something like `192.168.1.5`).

Start the backend so it's reachable from other devices (not just localhost):
```
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Windows Firewall will likely prompt "Allow python.exe to communicate on networks?" the first time —
click **Allow** (private networks is enough).

In the app, enter `http://192.168.1.5:8000` (your actual IP) in the backend URL field when it
first launches.

## 6. Run it

```
flutter run
```

With your phone connected via USB, this installs and launches the app directly on your phone —
exactly what you want for the panel to hold and see working.

## Once the ESP32-CAM headband arrives

Change one thing: instead of the phone's own camera feed, point the analysis loop at frames pulled
from `http://<esp32-ip>/stream` instead. I can update `main.dart` for that swap once you have the
headband's IP — the backend side (`/analyze_frame`) doesn't change at all.
