"""
Standalone live demo — no FastAPI/Flutter needed. Good as a fallback for
your PRC if WiFi in the review room is unreliable: everything runs
locally off your laptop's webcam.

Flow:
  1. Asks (by voice, with typed fallback) where you want to go.
  2. Plans a route using the sample indoor graph and speaks the first
     instruction.
  3. Continuously watches the webcam feed: announces obstacles when
     something gets close, and confirms location if a known signboard
     number is read via OCR.
  4. Press 'n' in the video window to advance to the next navigation
     instruction, 'o' to read a signboard (OCR is slow on CPU, so it
     runs on-demand rather than automatically), 'q' to quit.
  5. Press 'w' to SIMULATE an ultrasonic "wall/closed-door detected"
     reading. This isn't a fake feature — it's exactly the reading the
     ESP32-CAM headband firmware sends over its /distance endpoint. The
     camera can only recognize named objects (chair, person, etc.);
     walls and closed doors have no distinct shape for a vision model
     to classify, which is precisely why the headband design pairs the
     camera with ultrasonic sensors. This key simulates that sensor
     input until the physical headband is wired up.

Run with:
    python demo_run.py
"""

import time
import cv2

from detection import detect_obstacles
from ocr_reader import read_signboard
from path_planner import resolve_destination, plan_route, route_to_instructions
from voice_assistant import listen_for_destination, speak

CURRENT_NODE = "entrance"
OBSTACLE_ALERT_COOLDOWN_SEC = 4  # don't spam the same alert every frame
DETECTION_EVERY_N_FRAMES = 3     # skip frames between YOLO runs to keep video smooth on CPU

def main():
    global CURRENT_NODE

    spoken = listen_for_destination()
    dest_node = resolve_destination(spoken)
    if dest_node is None:
        print(f"Could not understand destination: '{spoken}'")
        return

    path = plan_route(CURRENT_NODE, dest_node)
    instructions = route_to_instructions(path)
    step_index = 0

    speak(f"Route found. {instructions[step_index]}")
    step_index += 1

    cap = cv2.VideoCapture(0)
    last_alert_time = 0
    frame_count = 0
    obstacles = []  # keep last known boxes so the display doesn't blank between detection frames

    print("Live demo running. Press 'n' for next instruction, 'o' to read a signboard, 'q' to quit.")

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        frame_count += 1
        # Only run YOLO every few frames — it's the most expensive step on
        # CPU, and re-running it every single frame is what caused the lag.
        if frame_count % DETECTION_EVERY_N_FRAMES == 0:
            obstacles = detect_obstacles(frame)

        # Draw boxes for the on-screen demo
        for obs in obstacles:
            x1, y1, x2, y2 = obs["bbox"]
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(frame, f"{obs['label']} {obs['confidence']:.2f} ({obs['distance_category']})",
                        (x1, max(y1 - 8, 12)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)

        now = time.time()
        close_obstacles = [o for o in obstacles if o["distance_category"] in ("close", "very close")]
        if close_obstacles and (now - last_alert_time) > OBSTACLE_ALERT_COOLDOWN_SEC:
            nearest = close_obstacles[0]
            speak(f"Caution, {nearest['label']} {nearest['distance_category']} ahead")
            last_alert_time = now

        # On-screen caption so the panel can see the vision/ultrasonic
        # split explicitly during the live demo, not just hear about it.
        cv2.putText(frame, "Camera: named objects  |  'w' = simulated ultrasonic (walls/doors)",
                    (10, frame.shape[0] - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 0), 1)

        cv2.imshow("SmartVision Demo", frame)
        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        elif key == ord("w"):
            # Simulated ultrasonic reading — same alert pathway a real
            # headband /distance reading below ALERT_DISTANCE_CM would
            # trigger. Class-independent, which is the whole point.
            speak("Caution, wall or closed door very close ahead")
        elif key == ord("o"):
            # OCR is heavy on CPU, so it only runs when you explicitly ask
            # for it — this is also more realistic: you'd read a sign when
            # you're near one, not continuously.
            speak("Reading sign")
            ocr_result = read_signboard(frame)
            if ocr_result["matched_node"] and ocr_result["matched_node"] != CURRENT_NODE:
                CURRENT_NODE = ocr_result["matched_node"]
                speak(f"Location confirmed: {CURRENT_NODE.replace('_', ' ')}")
            elif ocr_result["room_numbers"]:
                speak(f"Sign reads {' '.join(ocr_result['room_numbers'])}")
            else:
                speak("No sign detected")
        elif key == ord("n"):
            if step_index < len(instructions):
                speak(instructions[step_index])
                step_index += 1
            else:
                speak("You have reached your destination")

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
