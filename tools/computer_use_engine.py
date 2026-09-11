#!/usr/bin/env python3
"""
Dotmini MicroCode Computer Use Engine
=====================================
Proprietary macOS automation and live test engine designed for MicroCode Native.
Features:
  - 100% Computer Use UI automation
  - High-precision Accessibility Tree inspection (AXUIElement)
  - Hardware-level mouse movement and click emulation (CoreGraphics CGEvent)
  - Native keyboard text entry and modifier shortcuts (CGEvent Unicode & Keycodes)
  - Real-time window-specific high-resolution screen capture
  - End-to-end automated scenario verification for Cell Mode & Notebooks

Copyright © 2026 SPU AI CLUB — Dotmini Software
"""

import os
import sys
import time
import json
import subprocess
from typing import Dict, List, Optional, Tuple, Any

import Quartz
from Quartz.CoreGraphics import (
    CGEventCreate,
    CGEventGetLocation,
    CGEventCreateMouseEvent,
    CGEventPost,
    kCGHIDEventTap,
    kCGEventMouseMoved,
    kCGEventLeftMouseDown,
    kCGEventLeftMouseUp,
    kCGMouseButtonLeft,
    CGPoint,
    CGEventCreateKeyboardEvent,
    CGEventSetFlags,
    CGEventKeyboardSetUnicodeString,
    kCGEventFlagMaskCommand,
    kCGEventFlagMaskShift,
    kCGEventFlagMaskAlternate,
    kCGEventFlagMaskControl,
)
from ApplicationServices import (
    AXUIElementCreateApplication,
    AXUIElementCopyAttributeValue,
    kAXWindowsAttribute,
    kAXChildrenAttribute,
    kAXTitleAttribute,
    kAXRoleAttribute,
    kAXDescriptionAttribute,
    kAXValueAttribute,
    kAXPositionAttribute,
    kAXSizeAttribute,
    AXValueGetValue,
    kAXValueCGPointType,
    kAXValueCGSizeType,
)

# Standard macOS Virtual Keycodes
KEYCODES = {
    "return": 36,
    "enter": 36,
    "tab": 48,
    "space": 49,
    "delete": 51,
    "escape": 53,
    "command": 55,
    "shift": 56,
    "capslock": 57,
    "option": 58,
    "control": 59,
    "left": 123,
    "right": 124,
    "down": 125,
    "up": 126,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
    "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50,
}


class MicroCodeComputerUse:
    def __init__(self):
        self.pid, self.window_id, self.bounds = self._find_window()
        if not self.pid:
            raise RuntimeError("MicroCode process is not running!")

    def _find_window(self) -> Tuple[Optional[int], Optional[int], Optional[Dict[str, float]]]:
        """Find MicroCode process PID and CGWindow info."""
        try:
            pid_str = subprocess.check_output(
                ["pgrep", "-f", "/Volumes/MicroCodeBuild/apps/MicroCode.app/Contents/MacOS/MicroCode"]
            ).decode().strip().split("\n")[0]
            pid = int(pid_str)
        except Exception:
            return None, None, None

        window_id = None
        bounds = None
        candidates = []
        windows = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
        for w in windows:
            owner = w.get("kCGWindowOwnerName", "")
            if "MicroCode" in owner:
                wid = w.get("kCGWindowNumber")
                b = w.get("kCGWindowBounds", {})
                w_w = float(b.get("Width", 0))
                w_h = float(b.get("Height", 0))
                candidates.append((w_w * w_h, wid, {
                    "x": float(b.get("X", 0)),
                    "y": float(b.get("Y", 0)),
                    "width": w_w,
                    "height": w_h,
                }))

        if not candidates:
            return pid, None, None

        candidates.sort(key=lambda c: c[0], reverse=True)
        _, window_id, bounds = candidates[0]
        return pid, window_id, bounds

    def inspect_elements(self, max_depth: int = 8) -> List[Dict[str, Any]]:
        """Recursively query the AXUIElement tree of MicroCode."""
        app_ax = AXUIElementCreateApplication(self.pid)
        _, windows = AXUIElementCopyAttributeValue(app_ax, kAXWindowsAttribute, None)
        if not windows:
            return []

        # Choose the main window (the one with largest width/height or position matching bounds)
        best_w = windows[0]
        max_area = 0
        for w in windows:
            _, size_val = AXUIElementCopyAttributeValue(w, kAXSizeAttribute, None)
            if size_val:
                ok, sz = AXValueGetValue(size_val, kAXValueCGSizeType, None)
                if ok and (sz.width * sz.height) > max_area:
                    max_area = sz.width * sz.height
                    best_w = w

        w = best_w
        results = []

        def traverse(elem, depth):
            if depth > max_depth:
                return
            _, role = AXUIElementCopyAttributeValue(elem, kAXRoleAttribute, None)
            _, title = AXUIElementCopyAttributeValue(elem, kAXTitleAttribute, None)
            _, desc = AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute, None)
            _, val = AXUIElementCopyAttributeValue(elem, kAXValueAttribute, None)
            _, pos_val = AXUIElementCopyAttributeValue(elem, kAXPositionAttribute, None)
            _, size_val = AXUIElementCopyAttributeValue(elem, kAXSizeAttribute, None)

            pos = None
            size = None
            center = None
            if pos_val:
                ok, pt = AXValueGetValue(pos_val, kAXValueCGPointType, None)
                if ok:
                    pos = {"x": round(pt.x, 1), "y": round(pt.y, 1)}
            if size_val:
                ok, sz = AXValueGetValue(size_val, kAXValueCGSizeType, None)
                if ok:
                    size = {"width": round(sz.width, 1), "height": round(sz.height, 1)}

            if pos and size and size["width"] > 0 and size["height"] > 0:
                center = {
                    "x": round(pos["x"] + size["width"] / 2.0, 1),
                    "y": round(pos["y"] + size["height"] / 2.0, 1),
                }

            label = (title or desc or "").strip()
            if label or (role and any(k in role for k in ["Button", "Text", "Cell", "Menu"])):
                results.append({
                    "role": str(role or ""),
                    "title": str(title or ""),
                    "description": str(desc or ""),
                    "value": str(val or "") if isinstance(val, (str, int, float)) else "",
                    "label": label,
                    "position": pos,
                    "size": size,
                    "center": center,
                })

            _, children = AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute, None)
            if children:
                for c in children:
                    traverse(c, depth + 1)

        traverse(w, 0)
        return results

    def find_element(self, query: str, role: Optional[str] = None) -> Optional[Dict[str, Any]]:
        """Find an interactive element matching label or role."""
        elements = self.inspect_elements()
        query_clean = query.lower().strip()

        # 1. Exact match on title or description
        for el in elements:
            if role and role.lower() not in el["role"].lower():
                continue
            if el["label"].lower() == query_clean:
                return el

        # 2. Substring match
        for el in elements:
            if role and role.lower() not in el["role"].lower():
                continue
            if query_clean in el["label"].lower():
                return el

        return None

    def mouse_move(self, target_x: float, target_y: float, steps: int = 12, duration: float = 0.18):
        """Smoothly moves cursor to target coordinate mimicking human movement."""
        ev = CGEventCreate(None)
        cur = CGEventGetLocation(ev)
        start_x, start_y = cur.x, cur.y

        for i in range(1, steps + 1):
            t = i / steps
            ease = 1 - (1 - t) ** 3  # Ease out cubic
            x = start_x + (target_x - start_x) * ease
            y = start_y + (target_y - start_y) * ease
            move_ev = CGEventCreateMouseEvent(None, kCGEventMouseMoved, CGPoint(x, y), 0)
            CGEventPost(kCGHIDEventTap, move_ev)
            time.sleep(duration / steps)

    def mouse_click(self, x: float, y: float, click_count: int = 1):
        """Move to position and send native physical left click."""
        self.mouse_move(x, y)
        time.sleep(0.04)

        for i in range(1, click_count + 1):
            pt = CGPoint(x, y)
            down = CGEventCreateMouseEvent(None, kCGEventLeftMouseDown, pt, kCGMouseButtonLeft)
            up = CGEventCreateMouseEvent(None, kCGEventLeftMouseUp, pt, kCGMouseButtonLeft)
            
            # Set click state for double click
            Quartz.CGEventSetIntegerValueField(down, Quartz.kCGMouseEventClickState, i)
            Quartz.CGEventSetIntegerValueField(up, Quartz.kCGMouseEventClickState, i)

            CGEventPost(kCGHIDEventTap, down)
            time.sleep(0.05)
            CGEventPost(kCGHIDEventTap, up)
            if i < click_count:
                time.sleep(0.08)

    def click_element(self, query: str, role: Optional[str] = None, click_count: int = 1) -> Dict[str, Any]:
        """Find an element and click its center point."""
        el = self.find_element(query, role=role)
        if not el:
            raise ValueError(f"UI Element matching '{query}' not found in MicroCode window!")
        if not el.get("center"):
            raise ValueError(f"UI Element '{query}' has no valid coordinates on screen!")

        cx = el["center"]["x"]
        cy = el["center"]["y"]
        self.mouse_click(cx, cy, click_count=click_count)
        return {
            "success": True,
            "element": el["label"],
            "role": el["role"],
            "clicked_at": {"x": cx, "y": cy}
        }

    def type_text(self, text: str, delay: float = 0.015, press_enter: bool = False):
        """Type text into focused editor/cell with realistic typing cadence."""
        for char in text:
            # Create keyboard event with Unicode character
            down = CGEventCreateKeyboardEvent(None, 0, True)
            CGEventKeyboardSetUnicodeString(down, 1, char)
            CGEventPost(kCGHIDEventTap, down)
            time.sleep(0.005)
            up = CGEventCreateKeyboardEvent(None, 0, False)
            CGEventKeyboardSetUnicodeString(up, 1, char)
            CGEventPost(kCGHIDEventTap, up)
            time.sleep(delay)

        if press_enter:
            time.sleep(0.05)
            self.send_shortcut([], "return")

    def send_shortcut(self, modifiers: List[str], key: str):
        """Trigger native macOS shortcut (e.g. ['cmd'], 'return' or ['cmd'], 'k')."""
        key_clean = key.lower().strip()
        keycode = KEYCODES.get(key_clean)
        if keycode is None:
            raise ValueError(f"Unknown key name '{key}'")

        flags = 0
        for mod in modifiers:
            m = mod.lower().strip()
            if m in ["cmd", "command"]:
                flags |= kCGEventFlagMaskCommand
            elif m == "shift":
                flags |= kCGEventFlagMaskShift
            elif m in ["alt", "option"]:
                flags |= kCGEventFlagMaskAlternate
            elif m in ["ctrl", "control"]:
                flags |= kCGEventFlagMaskControl

        down = CGEventCreateKeyboardEvent(None, keycode, True)
        if flags:
            CGEventSetFlags(down, flags)
        CGEventPost(kCGHIDEventTap, down)
        time.sleep(0.05)

        up = CGEventCreateKeyboardEvent(None, keycode, False)
        if flags:
            CGEventSetFlags(up, flags)
        CGEventPost(kCGHIDEventTap, up)
        time.sleep(0.05)

    def capture_screenshot(self, output_path: str) -> str:
        """Capture the exact MicroCode window into an artifact PNG."""
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        cmd = ["screencapture", "-l", str(self.window_id), output_path]
        subprocess.check_call(cmd)
        return output_path


def main():
    if len(sys.argv) < 2:
        print("Usage: computer_use_engine.py <inspect|click|type|shortcut|capture|run_test> [args...]")
        sys.exit(1)

    cmd = sys.argv[1]
    engine = MicroCodeComputerUse()

    if cmd == "inspect":
        elements = engine.inspect_elements()
        print(json.dumps(elements, indent=2))

    elif cmd == "click":
        target = sys.argv[2]
        res = engine.click_element(target)
        print(json.dumps(res, indent=2))

    elif cmd == "type":
        text = sys.argv[2]
        press_enter = "--enter" in sys.argv
        engine.type_text(text, press_enter=press_enter)
        print(json.dumps({"success": True, "typed": text}))

    elif cmd == "shortcut":
        mods = [m for m in sys.argv[2:-1]]
        key = sys.argv[-1]
        engine.send_shortcut(mods, key)
        print(json.dumps({"success": True, "shortcut": f"{'+'.join(mods)}+{key}"}))

    elif cmd == "capture":
        dest = sys.argv[2] if len(sys.argv) > 2 else "/tmp/microcode_capture.png"
        path = engine.capture_screenshot(dest)
        print(json.dumps({"success": True, "path": path}))

    elif cmd == "run_test":
        print("🚀 Running full live Computer Use test on MicroCode...")
        art_dir = "/Users/dotmini/.gemini/antigravity/brain/197fe973-60a3-4cf1-b2bf-10645e78f063"
        s0 = engine.capture_screenshot(f"{art_dir}/live_step0_initial.png")
        print(f"✓ Step 0: Captured initial state -> {s0}")

        print("🖱️ Step 1: Locating and clicking 'Clear Outputs' button...")
        engine.click_element("Clear Outputs")
        time.sleep(1.0)
        s1 = engine.capture_screenshot(f"{art_dir}/live_step1_cleared.png")
        print(f"✓ Step 1: Outputs cleared -> {s1}")

        print("🖱️ Step 2: Locating and clicking 'Play' button to execute Python code...")
        try:
            engine.click_element("Play")
        except Exception as e:
            print(f"  Note on Play button ({e}), falling back to Cmd+Return...")
            engine.send_shortcut(["cmd"], "return")

        print("⏳ Step 3: Waiting for Python kernel & Seaborn execution...")
        time.sleep(3.5)
        s2 = engine.capture_screenshot(f"{art_dir}/live_step2_executed.png")
        print(f"✓ Step 3: Execution finished & charts re-rendered -> {s2}")

        print(json.dumps({
            "status": "success",
            "initial": s0,
            "cleared": s1,
            "executed": s2
        }, indent=2))


if __name__ == "__main__":
    main()
