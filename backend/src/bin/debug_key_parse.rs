use base64::{engine::general_purpose, Engine as _};
use russh_keys::*;

fn main() {
    let key_str = "AAAAB3NzaC1yc2EAAAADAQABAAABgQDCs840CVshlma61ItVseAz9d6P2k+snmjQI5pTROe/uhN0zGf0qypyGiRWk4Mv2shFeifTwHHQST+uNyIo1uyujrdhbQAvQ5DYxQzCIV3lxcn+E/5F/EK6Qx8lCbCkn0xutfTmWboZvf3VMHwTwbJyBXGdHBCIHm6Ais+tXaM4dtdjEUEFH0tS6fo1f/MBNsQtY/ulZVMVeFbofweBNkzHWdCgFG5YhZheU7Rl8ev2Gq2EykMe+LkLy6GLvAdGNWdahjsQGkMS0Mq9L/vr1gte8XRyaDB1h6q4HT9Due5I9EEwlu5UHLJnAQmj/mwEMNFq/839QwmzhAe8k/PqBJi/n/BTzkc1+mdIepVqMB+i5IWm3JK2WwlljTDlCFUygK63OKI9Gx0hcBKPPWdD6BH4hkN0auP3huJ07SQ/Jq3BES4U3OxRU/lsQ3oPo9d2frNLo5RmtbWBItt8OJIlVGb2VpmmIH/ksdlWq9VJaRYRRj4z/5ItjFI2kOfIrgQOfRE=";

    match general_purpose::STANDARD.decode(key_str) {
        Ok(bytes) => {
            println!("Decoded {} bytes", bytes.len());
            if bytes.len() > 4 {
                let len = u32::from_be_bytes(bytes[0..4].try_into().unwrap()) as usize;
                if bytes.len() >= 4 + len {
                    let algo = &bytes[4..4 + len];
                    let rest = &bytes[4 + len..];
                    println!("Algo: {:?}", String::from_utf8_lossy(algo));

                    match russh_keys::key::PublicKey::parse(algo, &bytes) {
                        Ok(pk) => println!("✅ Key Parsed Successfully: {:?}", pk.name()),
                        Err(e) => println!("❌ Key Parse Failed: {:?}", e),
                    }
                } else {
                    println!("❌ Blob too short for algo name");
                }
            } else {
                println!("❌ Blob too short");
            }
        }
        Err(e) => println!("Base64 fail: {}", e),
    }
}
