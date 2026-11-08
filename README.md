# SmartVision Project — Start Here

This folder has two parts, kept deliberately separate:

```
smartvision_project/
├── smartvision_backend/     ← Python backend (ALREADY WORKING — tested and debugged)
└── smartvision_app_source/  ← Flutter app SOURCE FILES (not a runnable project yet — see below)
```

## 1. Backend — nothing to do, it already works

`smartvision_backend/` contains the exact same Python files you already tested successfully
(path planning, detection, OCR, voice, FastAPI server, the standalone webcam demo). Just:

```
cd smartvision_backend
python -m venv venv        (optional — see note below)
pip install -r requirements.txt
python path_planner.py     ← should immediately print a sample route
```

Note: last time, packages ended up installing to your global Python even with venv "active" —
if that happens again, it's fine, just skip the venv and run everything from a normal terminal.

## 2. Flutter app — IMPORTANT: read this before doing anything

**`smartvision_app_source/` is NOT a runnable Flutter project.** It's just the three files that
are actually custom-written for SmartVision (`pubspec.yaml`, `lib/main.dart`, `SETUP.md`). Flutter
projects also need `android/`, `ios/`, and other scaffolding folders that only Flutter itself can
generate — you can't download those as plain files.

Correct order:

1. First confirm `flutter doctor` runs cleanly (see `smartvision_app_source/SETUP.md` for full
   install instructions).
2. In a terminal, from inside `smartvision_project/`, run:
   ```
   flutter create smartvision_app
   ```
   This generates a complete, real Flutter project folder called `smartvision_app/` next to the
   other two folders.
3. Copy the **content** of `smartvision_app_source/pubspec.yaml` into the new
   `smartvision_app/pubspec.yaml` (overwrite it).
4. Copy the **content** of `smartvision_app_source/lib/main.dart` into the new
   `smartvision_app/lib/main.dart` (overwrite it).
5. Follow the remaining steps in `smartvision_app_source/SETUP.md` (permissions, connecting your
   phone, pointing it at your backend's IP address).

Once this is done, `smartvision_app_source/` has served its purpose — everything real lives in
`smartvision_app/` from that point on.

## Order to actually do this in, given your timeline

1. Get the backend running (should take a few minutes — it's already proven to work).
2. Install Flutter, confirm with `flutter doctor`.
3. Generate the real Flutter project and copy the source files in.
4. Connect your phone, run the app, point it at your backend.

Ping me with the exact output of any command that errors — don't guess at fixes, paste the real
error and we'll fix it together like before.
