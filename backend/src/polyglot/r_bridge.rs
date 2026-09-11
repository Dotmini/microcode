//! R and R Markdown Polyglot Bridge
//!
//! Injects active Arrow IPC shared memory datasets into R's global environment
//! and provides hooks to export modified data frames back into MicroCode SHM.

use super::PolyglotVariableBinding;

pub struct RBridge;

impl RBridge {
    /// Generate R prelude code to inject existing SHM variables
    pub fn generate_prelude(variables: &[PolyglotVariableBinding]) -> String {
        let mut code = String::from(
            r#"# --- MicroCode Rosetta In-Memory Hybrid Bridge (R / R Markdown) ---
suppressWarnings({
    .has_arrow <- requireNamespace("arrow", quietly = TRUE)
    .has_nanoarrow <- requireNamespace("nanoarrow", quietly = TRUE)
})

._mc_load_shm_var <- function(shm_name) {
    paths <- c(
        file.path("/dev/shm", shm_name),
        file.path("/tmp", shm_name),
        file.path("/tmp", paste0(shm_name, ".shm"))
    )
    target <- NULL
    for (p in paths) {
        if (file.exists(p)) {
            target <- p
            break
        }
    }
    if (is.null(target)) return(NULL)
    
    tryCatch({
        if (.has_arrow) {
            return(as.data.frame(arrow::read_ipc_stream(target)))
        } else if (.has_nanoarrow) {
            return(as.data.frame(nanoarrow::read_nanoarrow(target)))
        } else {
            return(NULL)
        }
    }, error = function(e) {
        NULL
    })
}
"#,
        );

        for var in variables {
            code.push_str(&format!(
                "{} <- ._mc_load_shm_var('{}')\n",
                var.name, var.shm_name
            ));
        }

        code.push_str("# --- End MicroCode R Bridge ---\n\n");
        code
    }

    /// Generate R postlude code to auto-export newly defined data frames
    pub fn generate_postlude(target_var_names: &[String]) -> String {
        let mut code = String::from(
            r#"
# --- MicroCode R Postlude Export Hook ---
tryCatch({
    if (.has_arrow) {
"#,
        );

        for name in target_var_names {
            code.push_str(&format!(
                r#"        if (exists("{name}", envir = .GlobalEnv)) {{
            .val <- get("{name}", envir = .GlobalEnv)
            if (is.data.frame(.val)) {{
                arrow::write_ipc_stream(.val, "/tmp/{name}.shm")
            }}
        }}
"#,
                name = name
            ));
        }

        code.push_str(
            r#"    }
}, error = function(e) NULL)
# --- End Postlude ---
"#,
        );
        code
    }
}
