"""
Obstacle detection (YOLOv8n) with an APPROXIMATE distance in meters.

Distance comes from the object's typical real-world height and how tall it
appears in the photo. It is an estimate, not a measurement.
"""

import math
from ultralytics import YOLO
import numpy as np

_model = YOLO("yolov8n.pt")

# Typical real-world heights in meters
TYPICAL_HEIGHT_M = {
    "person": 1.7, "chair": 0.9, "couch": 0.85, "bed": 0.6,
    "dining table": 0.75, "bench": 0.85, "potted plant": 0.6,
    "tv": 0.5, "laptop": 0.25, "refrigerator": 1.7, "toilet": 0.4,
    "sink": 0.3, "backpack": 0.45, "suitcase": 0.6, "handbag": 0.3,
    "umbrella": 0.9, "bottle": 0.25, "cup": 0.1, "bowl": 0.08, "book": 0.25,
}
RELEVANT_CLASSES = set(TYPICAL_HEIGHT_M.keys())

# Assumed camera field of view along the photo's longer side.
# If distances read too HIGH, increase this; if too LOW, decrease it.
CAMERA_FOV_DEG = 68


def _estimate_distance_m(name, box_h_px, img_w, img_h, truncated):
    real_h = TYPICAL_HEIGHT_M.get(name)
    if not real_h or box_h_px <= 0:
        return None
    f_px = (max(img_w, img_h) / 2) / math.tan(math.radians(CAMERA_FOV_DEG / 2))
    d = real_h * f_px / box_h_px
    # If the object is cut off by the top/bottom edge, its height looks too
    # small and it would seem farther than it is. Stay on the safe side.
    if truncated:
        d = min(d, 1.5)
    return d


def _category_from_m(d):
    if d < 1.0:
        return "very close"
    if d < 2.0:
        return "close"
    if d < 4.0:
        return "moderate"
    return "far"


def _area_category(ratio):
    if ratio > 0.25:
        return "very close"
    if ratio > 0.10:
        return "close"
    if ratio > 0.03:
        return "moderate"
    return "far"


def _distance_text(d):
    if d < 1.0:
        return "less than 1 meter"
    d = round(d * 2) / 2  # nearest half meter
    unit = "meter" if d == 1 else "meters"
    return f"about {d:g} {unit}"


def detect_obstacles(frame: np.ndarray) -> list[dict]:
    results = _model(frame, verbose=False, imgsz=480)[0]
    img_h, img_w = frame.shape[:2]
    frame_area = img_h * img_w

    obstacles = []
    for box in results.boxes:
        name = _model.names[int(box.cls[0])]
        if name not in RELEVANT_CLASSES:
            continue

        conf = float(box.conf[0])
        if conf < 0.5:
            continue

        x1, y1, x2, y2 = box.xyxy[0].tolist()
        truncated = y1 <= 3 or y2 >= img_h - 3
        d = _estimate_distance_m(name, y2 - y1, img_w, img_h, truncated)

        if d is None:
            ratio = ((x2 - x1) * (y2 - y1)) / frame_area
            category = _area_category(ratio)
            text = category
            dist_m = None
        else:
            category = _category_from_m(d)
            text = _distance_text(d)
            dist_m = round(d, 1)

        obstacles.append({
            # The distance is put in the label so the app shows and speaks it
            # without needing a rebuild.
            "label": f"{name} {text}",
            "name": name,
            "confidence": round(conf, 2),
            "distance_category": category,
            "distance_m": dist_m,
            "bbox": [round(v) for v in (x1, y1, x2, y2)],
        })

    # nearest first, so the app alerts about the closest obstacle
    obstacles.sort(key=lambda o: o["distance_m"] if o["distance_m"] is not None else 99)
    return obstacles