//! Julia Polyglot Bridge
//!
//! Injects active Arrow IPC shared memory datasets into Julia's workspace
//! and provides hooks to export DataFrames back to MicroCode SHM.

use super::PolyglotVariableBinding;

pub struct JuliaBridge;

impl JuliaBridge {
    /// Generate Julia prelude code to inject existing SHM variables
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"# --- MicroCode Rosetta In-Memory Hybrid Bridge (Julia) ---
try
    using Arrow
    using DataFrames
    global _has_arrow = true
catch
    global _has_arrow = false
end

function _mc_load_shm_var(shm_name::String)
    paths = ["/dev/shm/" * shm_name, "/tmp/" * shm_name, "/tmp/" * shm_name * ".shm"]
    target = nothing
    for p in paths
        if isfile(p)
            target = p
            break
        end
    end
    if target === nothing
        return nothing
    end
    try
        if _has_arrow
            return DataFrame(Arrow.Table(target))
        else
            return read(target)
        end
    catch e
        return nothing
    end
end
"#,
        );

        for var in variables {
            code.push_str(&format!(
                "{} = _mc_load_shm_var(\"{}\")\n",
                var.name, var.shm_name
            ));
        }

        code.push_str("# --- End MicroCode Julia Bridge ---\n\n");
        code
    }

    /// Generate Julia postlude code to auto-export variables
    pub fn generate_postlude(target_var_names: &[String]) -> String {
        let mut code = String::from(
            r#"
# --- MicroCode Julia Postlude Export Hook ---
try
    if _has_arrow
"#,
        );

        for name in target_var_names {
            code.push_str(&format!(
                r#"        if isdefined(Main, Symbol("{name}"))
            val = getfield(Main, Symbol("{name}"))
            if val isa DataFrame
                Arrow.write("/tmp/{name}.shm", val)
            end
        end
"#,
                name = name
            ));
        }

        code.push_str(
            r#"    end
catch e
end
# --- End Julia Postlude ---
"#,
        );
        code
    }
}
