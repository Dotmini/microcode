use wasmtime::{Config, Engine, Linker};
use wasmtime_wasi::WasiCtx;

pub struct WasmHost {
    engine: Engine,
    linker: Linker<WasiCtx>,
}

impl WasmHost {
    pub fn new() -> anyhow::Result<Self> {
        let mut config = Config::new();
        config.async_support(true);
        let engine = Engine::new(&config)?;

        let linker = Linker::new(&engine);
        // wasi setup placeholder

        Ok(Self { engine, linker })
    }
}
