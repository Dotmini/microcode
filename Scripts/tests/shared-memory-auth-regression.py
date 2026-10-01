"""Exercise the generated bridge without pandas, network, or real credentials."""
import os
from pathlib import Path
import sys
import textwrap
import types

source = Path("MicroCode/Services/SharedMemoryService.swift").read_text()
bridge = textwrap.dedent(source.split('return """', 1)[1].split('"""', 1)[0])
requests = types.ModuleType("requests")
calls = []
requests.request = lambda *args, **kwargs: calls.append((args, kwargs))
sys.modules["requests"] = requests
sys.modules["pandas"] = types.ModuleType("pandas")
scope = {}
exec(compile(bridge, "generated-shm-bridge", "exec"), scope)
os.environ.pop("MICROCODE_LOCAL_API_TOKEN", None)
try:
    scope["shm"]._request("GET", "/list")
    raise AssertionError("Missing local capability was accepted")
except RuntimeError:
    pass
os.environ["MICROCODE_LOCAL_API_TOKEN"] = "test-only-capability"
scope["shm"]._request("GET", "/list")
assert calls[-1][1]["headers"] == {"X-MicroCode-Token": "test-only-capability"}
assert calls[-1][1]["allow_redirects"] is False
for base in ("https://remote.example/api/data", "http://localhost:4000/api/data"):
    scope["MicroCodeSHM"](base)._request("GET", "/list")
    assert calls[-1][1]["headers"] == {}
assert "test-only-capability" not in bridge
print("PASS: notebook bridge uses local environment capability without embedding or forwarding it")
