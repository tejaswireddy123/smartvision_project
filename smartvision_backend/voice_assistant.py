"""
Voice interaction module — two-way voice as described in your abstract:
  - listen_for_destination(): speech-to-text to capture where the user
    wants to go
  - speak(text): offline text-to-speech for navigation instructions and
    obstacle alerts

Design note for your demo: review rooms are noisy and WiFi can be
unreliable, so listen_for_destination() falls back to typed input if the
microphone/recognizer fails. Mention this fallback explicitly to your
panel — it's a deliberate reliability decision, not a missing feature.
"""

import speech_recognition as sr
import pyttsx3

_recognizer = sr.Recognizer()
_tts_engine = pyttsx3.init()
_tts_engine.setProperty("rate", 165)  # slightly slower than default for clarity


def speak(text: str) -> None:
    """Speaks text aloud via offline TTS (no internet dependency)."""
    print(f"[VOICE OUTPUT] {text}")
    _tts_engine.say(text)
    _tts_engine.runAndWait()


def listen_for_destination(timeout_sec: int = 10, phrase_time_limit_sec: int = 6) -> str:
    """
    Listens on the default microphone and returns recognized text.
    Falls back to a typed prompt if the mic isn't available or
    recognition fails (e.g. no internet for Google's recognizer) —
    this keeps the live demo from stalling in front of the panel.
    """
    try:
        with sr.Microphone() as source:
            print("[voice] calibrating for background noise...")
            _recognizer.adjust_for_ambient_noise(source, duration=1.0)
            speak("Where would you like to go?")
            audio = _recognizer.listen(source, timeout=timeout_sec, phrase_time_limit=phrase_time_limit_sec)
        text = _recognizer.recognize_google(audio)
        print(f"[VOICE INPUT] {text}")
        return text
    except Exception as e:
        print(f"[voice] speech recognition unavailable ({e}), falling back to typed input")
        return input("Type destination (e.g. 'room 101'): ")
