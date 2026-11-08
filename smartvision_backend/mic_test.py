"""
Microphone diagnostic — run this on its own to figure out exactly where
voice input is failing, separate from the rest of the demo.

Run with:
    python mic_test.py
"""

import speech_recognition as sr

print("Available microphones on this system:")
mic_list = sr.Microphone.list_microphone_names()
for i, name in enumerate(mic_list):
    print(f"  [{i}] {name}")

if not mic_list:
    print("\nNo microphones found at all — check Windows Sound settings"
          " (Settings > System > Sound > Input) to confirm a mic is connected.")
    exit()

print(f"\nUsing default microphone (index not specified). "
      f"If this is the wrong device, note its index above.\n")

r = sr.Recognizer()

try:
    with sr.Microphone() as source:
        print("Calibrating for ambient noise (stay quiet for 1 second)...")
        r.adjust_for_ambient_noise(source, duration=1.0)
        print(f"Energy threshold set to: {r.energy_threshold}")
        print("Now SPEAK CLEARLY — say something like 'room 101'. Listening for 8 seconds...")
        audio = r.listen(source, timeout=8, phrase_time_limit=6)
    print("Got audio! Sending to Google's speech recognizer...")
    text = r.recognize_google(audio)
    print(f"\nSUCCESS — recognized text: '{text}'")
except sr.WaitTimeoutError:
    print("\nFAILED — no speech detected at all (timed out waiting for you to start talking).")
    print("This usually means: wrong mic selected, mic is muted, or mic volume is too low.")
except sr.UnknownValueError:
    print("\nPARTIAL — audio was captured, but Google's recognizer couldn't understand it.")
    print("Try speaking louder/clearer, or check for background noise.")
except sr.RequestError as e:
    print(f"\nFAILED — could not reach Google's speech API: {e}")
    print("This means no internet connection, or it's being blocked (firewall/college network).")
except Exception as e:
    print(f"\nFAILED — unexpected error: {e}")
