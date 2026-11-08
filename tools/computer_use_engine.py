#!/usr/bin/env python3
"""
Dotmini MicroCode Native Computer Use Client (Zero PyObjC Dependency)
=====================================================================
Routes all macOS Computer Use operations to MicroCode's compiled Swift engine
(`NativeComputerUseService` on `http://127.0.0.1:18888/v1/computer-use`).

Why Native Swift instead of PyObjC (`Quartz` / `ApplicationServices`)?
  - Works out-of-the-box on Python 3.12 / 3.13 / 3.14+ with zero pip dependencies
  - Hybrid Set-of-Mark (`[1..N]`) combining AXUIElement + In-Process AppKit NSView + Apple Vision ANE OCR
  - 1x Logical Coordinate Normalization (`.nominalResolution`) eliminating Retina 2x click drift
  - Background-first `AXPress` / `AXValue` execution (no mouse hijack when AX supports press)
  - Cursor restoration after physical `CGEvent` fallback
  - Hard-blocked security denylist (SecurityAgent, Keychain, Password Managers, System Settings)

Copyright © 2024-2026 Dotmini Company Limited (บริษัท ดอทมินิ จำกัด)
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional


NATIVE_ENDPOINT = os.environ.get(
    "MICROCODE_COMPUTER_USE_URL", "http://127.0.0.1:18888/v1/computer-use"
)


class MicroCodeComputerUse:
    def __init__(self, app: Optional[str] = None, auto_launch: bool = True):
        self.app = app
        if auto_launch and not self._is_bridge_alive():
            app_bundle = "/Applications/MicroCode.app"
            if os.path.exists(app_bundle):
                subprocess.Popen(["open", "-g", "-a", app_bundle])
                for _ in range(25):
                    time.sleep(0.25)
                    if self._is_bridge_alive():
                        break

    def _is_bridge_alive(self) -> bool:
        try:
            req = urllib.request.Request(
                "http://127.0.0.1:18888/v1/health",
                headers={"Accept": "application/json"},
                method="GET",
            )
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                return resp.status == 200
        except Exception:
            return False

    def call_native(self, payload: Dict[str, Any], timeout: float = 30.0) -> Dict[str, Any]:
        body = dict(payload)
        if self.app and "app" not in body:
            body["app"] = self.app
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            NATIVE_ENDPOINT,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                return json.loads(raw)
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="replace")
            try:
                parsed = json.loads(err_body)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                pass
            return {"success": False, "error": f"HTTP {e.code}: {err_body}"}
        except Exception as e:
            return self._cli_fallback(body, str(e))

    def _cli_fallback(self, payload: Dict[str, Any], reason: str) -> Dict[str, Any]:
        """Minimal stdlib CLI fallback when MicroCode.app HTTP server is offline."""
        action = str(payload.get("action", "observe")).lower()
        if action in ("capture", "observe"):
            out_path = payload.get("output_path") or "/tmp/microcode_screenshot.png"
            res = subprocess.run(["screencapture", "-x", out_path], capture_output=True)
            return {
                "success": res.returncode == 0 and os.path.exists(out_path),
                "path": out_path,
                "capture_method": "screencapture_cli_fallback",
                "bridge_offline_reason": reason,
            }
        return {
            "success": False,
            "error": f"MicroCode native Computer Use bridge on 127.0.0.1:18888 is unreachable ({reason}). Launch MicroCode.app first.",
        }

    # --- High-level Set-of-Mark & Multimodal Operations ---

    def list_windows(self, app: Optional[str] = None) -> Dict[str, Any]:
        return self.call_native({"action": "windows", "app": app or self.app})

    def observe(
        self,
        app: Optional[str] = None,
        window_id: Optional[int] = None,
        set_of_mark: bool = True,
        output_path: Optional[str] = None,
        include_image: bool = True,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "action": "observe",
            "set_of_mark": set_of_mark,
            "include_image": include_image,
        }
        if app or self.app:
            payload["app"] = app or self.app
        if window_id is not None:
            payload["window_id"] = int(window_id)
        if output_path:
            payload["output_path"] = output_path
        return self.call_native(payload)

    def act(self, params: Dict[str, Any]) -> Dict[str, Any]:
        return self.call_native(params)

    def batch(self, steps: List[Dict[str, Any]], app: Optional[str] = None) -> Dict[str, Any]:
        payload: Dict[str, Any] = {"action": "batch", "steps": steps}
        if app or self.app:
            payload["app"] = app or self.app
        return self.call_native(payload, timeout=60.0)

    def qa_verify(self, params: Dict[str, Any]) -> Dict[str, Any]:
        payload = dict(params)
        payload["action"] = "qa_verify"
        return self.call_native(payload, timeout=60.0)

    # --- Backward-Compatible Legacy API (`inspect`, `click`, `type`, `shortcut`, `capture`) ---

    def inspect_elements(
        self,
        query: Optional[str] = None,
        role: Optional[str] = None,
        app: Optional[str] = None,
        window_id: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        payload: Dict[str, Any] = {"action": "inspect"}
        if query:
            payload["query"] = query
        if role:
            payload["role"] = role
        if app or self.app:
            payload["app"] = app or self.app
        if window_id is not None:
            payload["window_id"] = int(window_id)
        res = self.call_native(payload)
        if not res.get("success", False) and "error" in res:
            raise RuntimeError(res["error"])
        return res.get("elements", [])

    def click_element(
        self,
        query: Optional[str] = None,
        role: Optional[str] = None,
        click_count: int = 1,
        mark_id: Optional[int] = None,
        delivery: str = "auto",
        app: Optional[str] = None,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "action": "double_click" if click_count == 2 else "click",
            "click_count": click_count,
            "delivery": delivery,
        }
        if mark_id is not None:
            payload["mark_id"] = int(mark_id)
        if query:
            payload["target"] = query
        if role:
            payload["role"] = role
        if app or self.app:
            payload["app"] = app or self.app
        res = self.call_native(payload)
        if not res.get("success", False):
            raise RuntimeError(res.get("error", f"Failed to click '{query or mark_id}'"))
        return res

    def mouse_click(
        self,
        x: float,
        y: float,
        click_count: int = 1,
        button: str = "left",
        window_relative: bool = False,
        restore_cursor: bool = True,
        app: Optional[str] = None,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "action": "right_click" if button == "right" else ("double_click" if click_count == 2 else "click"),
            "x": float(x),
            "y": float(y),
            "click_count": int(click_count),
            "button": button,
            "window_relative": bool(window_relative),
            "restore_cursor": bool(restore_cursor),
        }
        if app or self.app:
            payload["app"] = app or self.app
        res = self.call_native(payload)
        if not res.get("success", False):
            raise RuntimeError(res.get("error", f"Failed to click at ({x}, {y})"))
        return res

    def type_text(
        self,
        text: str,
        press_enter: bool = False,
        mark_id: Optional[int] = None,
        mode: str = "auto",
        app: Optional[str] = None,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "action": "type",
            "text": text,
            "press_enter": bool(press_enter),
            "mode": mode,
        }
        if mark_id is not None:
            payload["mark_id"] = int(mark_id)
        if app or self.app:
            payload["app"] = app or self.app
        res = self.call_native(payload)
        if not res.get("success", False):
            raise RuntimeError(res.get("error", "Failed to type text"))
        return res

    def send_shortcut(
        self,
        modifiers: List[str],
        key: str,
        app: Optional[str] = None,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "action": "shortcut",
            "modifiers": modifiers,
            "key": key,
        }
        if app or self.app:
            payload["app"] = app or self.app
        res = self.call_native(payload)
        if not res.get("success", False):
            raise RuntimeError(res.get("error", f"Failed to send shortcut {modifiers}+{key}"))
        return res

    def capture_screenshot(
        self,
        output_path: str = "/tmp/microcode_screenshot.png",
        set_of_mark: bool = False,
        app: Optional[str] = None,
    ) -> str:
        res = self.observe(
            app=app,
            set_of_mark=set_of_mark,
            output_path=output_path,
            include_image=False,
        )
        if not res.get("success", False):
            raise RuntimeError(res.get("error", "Screenshot capture failed"))
        return res.get("path", output_path)

    def run_live_notebook_scenario(self, artifact_dir: str = "/tmp") -> Dict[str, Any]:
        return self.qa_verify({"app": self.app or "MicroCode"})


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    engine = MicroCodeComputerUse(auto_launch=False)
    if action == "inspect":
        query = sys.argv[2] if len(sys.argv) > 2 else None
        print(json.dumps(engine.inspect_elements(query=query), indent=2, ensure_ascii=False))
    elif action == "observe":
        out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/microcode_som.png"
        print(json.dumps(engine.observe(output_path=out, include_image=False), indent=2, ensure_ascii=False))
    elif action == "windows":
        print(json.dumps(engine.list_windows(), indent=2, ensure_ascii=False))
    elif action == "click":
        target = sys.argv[2]
        print(json.dumps(engine.click_element(target), indent=2, ensure_ascii=False))
    elif action == "capture":
        out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/microcode_live.png"
        print(json.dumps({"path": engine.capture_screenshot(out)}, indent=2, ensure_ascii=False))
    else:
        print(json.dumps(engine.call_native({"action": action}), indent=2, ensure_ascii=False))
