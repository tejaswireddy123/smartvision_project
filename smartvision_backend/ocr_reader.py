"""
OCR module — reads room numbers / signboards from a frame using EasyOCR,
and (where possible) matches the text against known location tags so the
system can confirm the user's current position without needing indoor
beacons or GPS.
"""

import re
import easyocr
import numpy as np
from locations_data import OCR_TAG_TO_NODE

_reader = easyocr.Reader(["en"], gpu=False)  # set gpu=True if running on a CUDA machine

_ROOM_NUMBER_PATTERN = re.compile(r"\b\d{2,4}\b")


def read_signboard(frame: np.ndarray) -> dict:
    """
    Runs OCR on a frame. Returns:
        {
          "raw_text": [...],       all text fragments detected
          "room_numbers": [...],   any digit sequences that look like room numbers
          "matched_node": str|None if a detected number matches a known location
        }
    """
    # canvas_size caps EasyOCR's internal resize — the default (2560) is
    # very slow on CPU. 720 is plenty for reading a nearby signboard and
    # is dramatically faster.
    results = _reader.readtext(frame, canvas_size=720)
    raw_text = [text for (_, text, conf) in results if conf > 0.4]

    room_numbers = []
    for text in raw_text:
        room_numbers.extend(_ROOM_NUMBER_PATTERN.findall(text))

    matched_node = None
    for number in room_numbers:
        if number in OCR_TAG_TO_NODE:
            matched_node = OCR_TAG_TO_NODE[number]
            break

    return {
        "raw_text": raw_text,
        "room_numbers": room_numbers,
        "matched_node": matched_node,
    }
