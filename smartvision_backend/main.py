"""
SmartVision FastAPI backend.
Run with:
    uvicorn main:app --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
import cv2

from detection import detect_obstacles
from ocr_reader import read_signboard
from path_planner import resolve_destination, plan_route, route_to_instructions, total_distance

app = FastAPI(title="SmartVision Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

state = {
    "current_node": "entrance",
    "destination_node": None,
    "instructions": [],
    "step_index": 0,
}

EMPTY_OCR = {"raw_text": [], "room_numbers": [], "matched_node": None}
MAX_SIDE = 800  # shrink big phone photos before analysing them


def _decode_upload(file_bytes: bytes):
    arr = np.frombuffer(file_bytes, np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        return None
    h, w = frame.shape[:2]
    longest = max(h, w)
    if longest > MAX_SIDE:
        scale = MAX_SIDE / longest
        frame = cv2.resize(frame, (int(w * scale), int(h * scale)))
    return frame


@app.post("/destination")
async def set_destination(spoken_text: str):
    node = resolve_destination(spoken_text)
    if node is None:
        return {"error": f"Could not match '{spoken_text}' to a known location"}

    path = plan_route(state["current_node"], node)
    instructions = route_to_instructions(path)

    state["destination_node"] = node
    state["instructions"] = instructions
    state["step_index"] = 0

    return {
        "destination": node,
        "path": path,
        "instructions": instructions,
        "distance_m": total_distance(path),
    }


@app.get("/navigate/next")
async def next_instruction():
    i = state["step_index"]
    if i >= len(state["instructions"]):
        return {"done": True, "instruction": None}
    instruction = state["instructions"][i]
    state["step_index"] += 1
    return {"done": False, "instruction": instruction}


# Plain "def" (not async) so FastAPI runs this heavy work in a worker thread
# and the other endpoints stay responsive while it runs.
@app.post("/analyze_frame")
def analyze_frame(file: UploadFile = File(...), ocr: bool = False):
    frame = _decode_upload(file.file.read())
    if frame is None:
        return {"obstacles": [], "ocr": EMPTY_OCR, "current_node": state["current_node"]}

    obstacles = detect_obstacles(frame)

    # OCR is slow on CPU, so only run it when the app asks (Read Sign button)
    ocr_result = read_signboard(frame) if ocr else EMPTY_OCR

    if ocr_result["matched_node"]:
        state["current_node"] = ocr_result["matched_node"]

    return {
        "obstacles": obstacles,
        "ocr": ocr_result,
        "current_node": state["current_node"],
    }


@app.get("/health")
async def health():
    return {"status": "ok"}