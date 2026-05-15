use russh::*;
use russh_keys::*;
use std::sync::Arc;
use std::time::Duration;

struct Client {}

#[async_trait::async_trait]
impl client::Handler for Client {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &key::PublicKey,
    ) -> Result<bool, Self::Error> {
        println!("🔍 Server Check: Key Type = {:?}", server_public_key.name());
        Ok(true)
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut config = client::Config::default();

    // Exact configuration from remote.rs
    config.preferred = Preferred {
        kex: std::borrow::Cow::Borrowed(&[
            russh::kex::CURVE25519,
            russh::kex::DH_G14_SHA256,
            russh::kex::DH_G14_SHA1,
            russh::kex::DH_G1_SHA1,
        ]),
        cipher: std::borrow::Cow::Borrowed(&[
            russh::cipher::CHACHA20_POLY1305,
            russh::cipher::AES_256_GCM,
            russh::cipher::AES_256_CTR,
            russh::cipher::AES_192_CTR,
            russh::cipher::AES_128_CTR,
        ]),
        key: std::borrow::Cow::Borrowed(&[
            russh_keys::key::ED25519,
            russh_keys::key::ECDSA_SHA2_NISTP256,
            russh_keys::key::RSA_SHA2_512,
            russh_keys::key::RSA_SHA2_256,
            russh_keys::key::SSH_RSA,
        ]),
        compression: std::borrow::Cow::Borrowed(&[
            russh::compression::NONE,
            russh::compression::ZLIB,
        ]),
        ..Default::default()
    };

    config.keepalive_interval = Some(Duration::from_secs(10));

    let config = Arc::new(config);
    let sh = Client {};

    println!("Connecting to ssh.lightning.ai:22...");

    // Try to connect
    match tokio::time::timeout(
        Duration::from_secs(10),
        client::connect(config, ("ssh.lightning.ai", 22), sh),
    )
    .await
    {
        Ok(res) => match res {
            Ok(_) => println!("✅ Connection/Handshake Successful!"),
            Err(e) => println!("❌ Connection Failed: {}", e),
        },
        Err(_) => println!("❌ Connection Timed Out"),
    }

    Ok(())
}
