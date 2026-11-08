# SmartVision / PathSense AI — Software Backend (Phase-I)

## Setup

1. Create a virtual environment and install dependencies:
   ```
   python -m venv venv
   venv\Scripts\activate      (Windows)   or   source venv/bin/activate   (Mac/Linux)
   pip install -r requirements.txt
   ```

2. **PyAudio install note**: this is the most common install failure.
   - Windows: `pip install pipwin && pipwin install pyaudio`
   - Mac: `brew install portaudio` then `pip install pyaudio`
   - Linux: `sudo apt-get install portaudio19-dev` then `pip install pyaudio`

   If you can't get it working in time, `voice_assistant.py` already falls
   back to typed input, so this won't block your demo.

3. First run will auto-download the YOLOv8n weights (~6MB) and EasyOCR's
   model files (~100MB) — do this once **before** your review, on a
   working internet connection, so nothing hangs during the live demo.

## Two ways to demo

- **Standalone (recommended for the panel room):**
  ```
  python demo_run.py
  ```
  Uses your laptop webcam directly. No server, no WiFi dependency. This
  is the safest option if the venue's network is unreliable.

- **Full backend (shows the actual architecture):**
  ```
  uvicorn main:app --reload
  ```
  Then open http://localhost:8000/docs to demonstrate the API endpoints
  live, or point your Flutter app / ESP32-CAM stream at it.

## Suggested 7-day plan to Oct 1

- **Day 1 (today):** Get `requirements.txt` installed, run
  `python path_planner.py` to confirm the graph/routing works — this has
  no ML dependencies so it's the fastest thing to get green.
- **Day 2:** Get `demo_run.py` running with just detection (comment out
  the OCR call temporarily if EasyOCR install is slow) — confirm the
  webcam + YOLO + voice loop works end to end.
- **Day 3:** Add OCR back in, test with a few printed "101"/"102" signs
  taped around a room to simulate signboards.
- **Day 4:** Polish voice interaction — test in a noisy room to make
  sure the typed-input fallback actually triggers gracefully.
- **Day 5:** Wire up `main.py` (FastAPI) and test hitting `/destination`
  and `/analyze_frame` from the interactive docs page.
- **Day 6:** Flash the ESP32-CAM headband firmware (see the .ino file
  from earlier) and try pointing OpenCV at its `/stream` URL instead of
  the webcam, if time allows — not essential for the demo to succeed.
- **Day 7:** Rehearse the demo twice, out loud, with the actual panel
  timing in mind. Have `demo_run.py` as your primary demo and the
  FastAPI docs page as backup if someone asks "show me the API."

## What to say if asked about limitations (be upfront, panels respect this)

- Distance estimation is a bounding-box-area heuristic, not true depth —
  future work item, or fuse with the headband's ultrasonic sensors for
  real distance.
- The indoor location graph (`locations_data.py`) is hardcoded for the
  demo; a full deployment would load this per-building from a database.
- Voice recognition needs internet for `recognize_google`; an offline
  option (e.g. Vosk) is a stated future improvement for infrastructure-
  independence, which matters given your abstract's "infrastructure-
  independent" claim.
