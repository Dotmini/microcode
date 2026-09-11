#!/usr/bin/env python3
"""
MicroCode Live Real-time Test Driver
===================================
Executes realistic human interactions on the running MicroCode instance:
  1. Focus MicroCode window
  2. Capture initial screenshot (Step 0)
  3. Move mouse to 'Clear Outputs' button and click (Step 1)
  4. Wait & capture cleared state screenshot
  5. Move mouse to 'Play' button and click (Step 2)
  6. Wait for Python execution & Matplotlib plot render
  7. Capture final executed screenshot (Step 3)
"""

import os
import sys
import time
import json
import AppKit

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tools.computer_use_engine import MicroCodeComputerUse

def run():
    print("==================================================")
    print("  MicroCode Real-Time 100% Computer Use Live Test")
    print("==================================================")

    engine = MicroCodeComputerUse()
    art_dir = "/Users/dotmini/.gemini/antigravity/brain/197fe973-60a3-4cf1-b2bf-10645e78f063"

    # 1. Activate application
    print("1. Activating MicroCode window to foreground...")
    app = AppKit.NSRunningApplication.runningApplicationWithProcessIdentifier_(engine.pid)
    if app:
        app.activateWithOptions_(AppKit.NSApplicationActivateIgnoringOtherApps)
    time.sleep(0.5)

    # 2. Capture Initial State
    s0_path = f"{art_dir}/realtime_step0_before.png"
    engine.capture_screenshot(s0_path)
    print(f"✓ Step 0: Initial state captured -> {s0_path}")

    # 3. Locate & Click 'Clear Outputs'
    print("2. Simulating mouse move and click on 'Clear Outputs'...")
    res_clear = engine.click_element("Clear Outputs")
    print(f"   Clicked: {res_clear['element']} at ({res_clear['clicked_at']['x']}, {res_clear['clicked_at']['y']})")
    time.sleep(1.2)

    # 4. Capture Cleared State
    s1_path = f"{art_dir}/realtime_step1_cleared.png"
    engine.capture_screenshot(s1_path)
    print(f"✓ Step 1: Cleared state captured -> {s1_path}")

    # 5. Locate & Click 'Play' button or Run Cell
    print("3. Simulating mouse move and click on 'Play' (▶) to execute Python code...")
    try:
        res_play = engine.click_element("Play")
        print(f"   Clicked: {res_play['element']} at ({res_play['clicked_at']['x']}, {res_play['clicked_at']['y']})")
    except Exception as e:
        print(f"   Note: {e}, falling back to keyboard shortcut Cmd+Return...")
        engine.send_shortcut(["cmd"], "return")

    # 6. Wait for Python execution
    print("4. Waiting for Python kernel to execute and generate plots (3.5s)...")
    time.sleep(3.5)

    # 7. Capture Final State
    s2_path = f"{art_dir}/realtime_step2_executed.png"
    engine.capture_screenshot(s2_path)
    print(f"✓ Step 2: Final state after execution captured -> {s2_path}")

    print("\n🎉 Live Computer Use Test Completed Successfully!")
    print(json.dumps({
        "success": True,
        "step0_before": s0_path,
        "step1_cleared": s1_path,
        "step2_executed": s2_path,
    }, indent=2))

if __name__ == "__main__":
    run()
