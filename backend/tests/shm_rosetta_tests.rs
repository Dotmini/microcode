//! Integration Tests for MicroCode Rosetta Hybrid In-Memory Fabric
//!
//! Verifies:
//! 1. POSIX Shared Memory allocation and 64-byte NEON alignment
//! 2. Hardware-level memory protection via `mprotect(PROT_READ)`
//! 3. Arrow IPC serialization/deserialization for zero-copy polyglot cells
//! 4. Polyglot code generation (Python & Ardium bridges)
//! 5. RAM-to-RAM Flight transfer preparation & materialization

use microcode_embedded::arrow_cdata::*;
use microcode_embedded::arrow_flight::ArrowFlightService;
use microcode_embedded::polyglot::*;
use microcode_embedded::polyglot::ardium_bridge::ArdiumBridge;
use microcode_embedded::polyglot::python_bridge::PythonBridge;
use microcode_embedded::polyglot::r_bridge::RBridge;
use microcode_embedded::polyglot::julia_bridge::JuliaBridge;
use microcode_embedded::polyglot::go_bridge::GoBridge;
use microcode_embedded::polyglot::rust_bridge::RustBridge;
use microcode_embedded::polyglot::cpp_bridge::CppBridge;
use microcode_embedded::polyglot::objc_bridge::ObjCBridge;
use microcode_embedded::shm_broker::GLOBAL_SHM_BROKER;
use polars::prelude::*;

#[test]
fn test_shm_broker_allocation_and_sealing() {
    let broker = &*GLOBAL_SHM_BROKER;
    let session = "integ_test_session_01";
    let var = "user_features";

    // 1. Allocate 2000 bytes (should be rounded to 2048 for 64-byte alignment)
    let seg_arc = broker
        .allocate(session, var, 2000, "tensor_float32")
        .expect("Allocation failed");

    let test_payload = b"MICROCODE_ROSETTA_HYBRID_ENGINE_ARM64";

    {
        let mut seg = seg_arc.write().expect("Lock write failed");
        assert_eq!(seg.size() % 64, 0, "Buffer must be 64-byte aligned for Apple Silicon NEON");
        assert!(seg.size() >= 2000);

        // 2. Write payload
        seg.write_bytes(0, test_payload).expect("Write bytes failed");

        // 3. Seal as immutable read-only
        seg.seal_read_only().expect("mprotect seal failed");
        assert!(seg.metadata.is_read_only);

        // 4. Verify writes are now blocked
        let write_attempt = seg.write_bytes(0, b"ILLEGAL_WRITE");
        assert!(write_attempt.is_err());
    }

    // 5. Read back safely
    {
        let seg = seg_arc.read().expect("Lock read failed");
        let slice = seg.read_slice(0, test_payload.len()).expect("Read slice failed");
        assert_eq!(slice, test_payload);
    }

    // 6. Clean up
    broker.remove(session, var).expect("Remove failed");
}

#[test]
fn test_arrow_ipc_zero_copy_dataframe() {
    let col_id = Series::new("user_id", &[101i64, 102, 103, 104]);
    let col_score = Series::new("model_accuracy", &[0.945f64, 0.982, 0.891, 0.999]);
    let col_tier = Series::new("tier", &["Ultra", "Pro", "Lite", "Ultra"]);
    let mut df = DataFrame::new(vec![col_id, col_score, col_tier]).unwrap();

    let ipc_bytes = serialize_df_to_arrow_ipc(&mut df).expect("IPC serialization failed");
    assert!(!ipc_bytes.is_empty());

    let restored_df = deserialize_df_from_arrow_ipc(&ipc_bytes).expect("IPC deserialization failed");
    assert_eq!(restored_df.shape(), (4, 3));
    assert_eq!(
        restored_df.get_column_names(),
        vec!["user_id", "model_accuracy", "tier"]
    );
}

#[test]
fn test_polyglot_bridge_code_generation() {
    let bindings = vec![
        PolyglotVariableBinding {
            name: "sales_data".to_string(),
            shm_name: "mc_session1_sales_data_e1".to_string(),
            data_type: "arrow_table".to_string(),
            num_rows: Some(50000),
            num_cols: Some(12),
        },
        PolyglotVariableBinding {
            name: "weights".to_string(),
            shm_name: "mc_session1_weights_e1".to_string(),
            data_type: "tensor_f32".to_string(),
            num_rows: None,
            num_cols: None,
        },
    ];

    // Verify Python bridge
    let py_code = PythonBridge::generate_prelude(&bindings);
    assert!(py_code.contains("sales_data = _mc_load_shm_var('mc_session1_sales_data_e1')"));
    assert!(py_code.contains("weights = _mc_load_shm_var('mc_session1_weights_e1')"));

    // Verify Ardium bridge
    let ardium_code = ArdiumBridge::generate_prelude(&bindings);
    assert!(ardium_code.contains("@extern \"C\""));
    assert!(ardium_code.contains("let sales_data = MicroCodeArrowBuffer::load(\"mc_session1_sales_data_e1\");"));

    // Verify R / R Markdown bridge
    let r_code = RBridge::generate_prelude(&bindings);
    assert!(r_code.contains("sales_data <- ._mc_load_shm_var('mc_session1_sales_data_e1')"));

    // Verify Julia bridge
    let julia_code = JuliaBridge::generate_prelude(&bindings);
    assert!(julia_code.contains("sales_data = _mc_load_shm_var(\"mc_session1_sales_data_e1\")"));

    // Verify Go bridge
    let go_code = GoBridge::generate_prelude(&bindings);
    assert!(go_code.contains("sales_dataBuffer, _ = mcLoadShmVar(\"mc_session1_sales_data_e1\")"));

    // Verify Rust bridge
    let rust_code = RustBridge::generate_prelude(&bindings);
    assert!(rust_code.contains("let sales_data = mc_load_shm_dataframe(\"mc_session1_sales_data_e1\");"));

    // Verify C/C++ bridge
    let cpp_code = CppBridge::generate_prelude(&bindings);
    assert!(cpp_code.contains("auto sales_data = mc_load_shm_buffer(\"mc_session1_sales_data_e1\");"));

    // Verify Objective-C bridge
    let objc_code = ObjCBridge::generate_prelude(&bindings);
    assert!(objc_code.contains("NSData* sales_data = mc_load_shm_nsdata(@\"mc_session1_sales_data_e1\");"));

    // Verify unified PolyglotBridge injector
    let injected_python = PolyglotBridge::inject_prelude("python", "print('hello')", &bindings);
    assert!(injected_python.contains("sales_data = _mc_load_shm_var"));
    assert!(injected_python.ends_with("print('hello')"));

    let injected_r = PolyglotBridge::inject_prelude("r", "cat('hello')", &bindings);
    assert!(injected_r.contains("sales_data <- ._mc_load_shm_var"));
    assert!(injected_r.ends_with("cat('hello')"));
}

#[test]
fn test_arrow_flight_export_import_roundtrip() {
    let broker = &*GLOBAL_SHM_BROKER;
    let session = "flight_test_session";
    let var = "dataset_x";

    let seg_arc = broker
        .allocate(session, var, 1024, "arrow_ipc")
        .expect("allocate failed");

    {
        let mut seg = seg_arc.write().unwrap();
        seg.write_bytes(0, b"FLIGHT_STREAM_RAW_PAYLOAD_12345").unwrap();
        seg.seal_read_only().unwrap();
    }

    let service = ArrowFlightService::new();
    let (header, payload) = service
        .prepare_export(session, var, None)
        .expect("prepare export failed");

    assert_eq!(header.variable_name, "dataset_x");
    assert!(!payload.is_empty());

    // Ingest into a new session
    let mut import_header = header.clone();
    import_header.session_id = "cloud_worker_session".to_string();
    import_header.variable_name = "imported_dataset_x".to_string();

    let imported_seg = service
        .ingest_import(&import_header, &payload)
        .expect("ingest import failed");

    {
        let seg = imported_seg.read().unwrap();
        let data = seg.read_slice(0, 31).unwrap();
        assert_eq!(data, b"FLIGHT_STREAM_RAW_PAYLOAD_12345");
        assert!(seg.metadata.is_read_only);
    }

    // Clean up
    broker.remove(session, var).unwrap();
    broker.remove("cloud_worker_session", "imported_dataset_x").unwrap();
}
