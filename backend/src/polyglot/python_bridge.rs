//! Python Polyglot Bridge
//!
//! Injects active SHM Arrow datasets into Python's global namespace
//! and captures newly exported DataFrames / Tensors into SHM.

use super::PolyglotVariableBinding;

pub struct PythonBridge;

impl PythonBridge {
    /// Generate Python prelude code to inject existing SHM variables
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"# --- MicroCode Rosetta In-Memory Hybrid Bridge (Python) ---
import sys, os
try:
    import polars as pl
    _has_polars = True
except ImportError:
    _has_polars = False

try:
    import pyarrow as pa
    import pyarrow.ipc as pa_ipc
    _has_arrow = True
except ImportError:
    _has_arrow = False

def _mc_load_shm_var(shm_name):
    # On macOS / Linux, POSIX SHM is accessible via /dev/shm or /tmp
    paths = [f"/dev/shm/{shm_name}", f"/tmp/{shm_name}", f"/tmp/{shm_name}.shm"]
    target = None
    for p in paths:
        if os.path.exists(p):
            target = p
            break
    if not target:
        return None
    try:
        if _has_polars:
            return pl.read_ipc(target)
        elif _has_arrow:
            with pa.memory_map(target, 'r') as source:
                return pa_ipc.open_stream(source).read_all()
    except Exception:
        return None
"#,
        );

        for var in variables {
            code.push_str(&format!(
                "{} = _mc_load_shm_var('{}')\n",
                var.name, var.shm_name
            ));
        }

        code.push_str("# --- End MicroCode Bridge ---\n\n");
        code
    }

    /// Generate Python postlude code to auto-export newly defined DataFrames
    pub fn generate_postlude(target_var_names: &[String]) -> String {
        let targets_repr = format!("{:?}", target_var_names);
        format!(
            r#"
# --- MicroCode Postlude Export Hook ---
try:
    for _var_name in {}:
        if _var_name in locals():
            _val = locals()[_var_name]
            # If Polars DataFrame
            if _has_polars and isinstance(_val, pl.DataFrame):
                _out_path = f"/tmp/{{_var_name}}.shm"
                _val.write_ipc(_out_path)
            # If Pandas DataFrame
            elif hasattr(_val, 'to_feather'):
                _out_path = f"/tmp/{{_var_name}}.shm"
                _val.to_feather(_out_path)
except Exception as _e:
    pass
# --- End Postlude ---
"#,
            targets_repr
        )
    }
}
