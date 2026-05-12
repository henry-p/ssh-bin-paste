use anyhow::{Context, Result, bail};
use serde::Deserialize;
use uuid::Uuid;

use crate::assets::{CLIPBOARD_IMAGE_SWIFT, write_temp_asset};
use crate::ssh::run_local;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CapturedImage {
    pub path: String,
    pub mime_type: String,
    pub size_bytes: u64,
}

pub fn capture_clipboard_image() -> Result<CapturedImage> {
    let script = write_temp_asset("clipboard-image.swift", CLIPBOARD_IMAGE_SWIFT)?;
    let output_path = std::env::temp_dir()
        .join(format!("ssh-bin-paste-{}.png", Uuid::new_v4()))
        .display()
        .to_string();
    let result = run_local(
        "swift",
        &[script.to_str().unwrap_or(""), "--output", &output_path],
        None,
    )?;
    if result.exit_code != 0 {
        bail!(
            "{}",
            result
                .stderr
                .trim()
                .strip_suffix('\n')
                .unwrap_or(result.stderr.trim())
        );
    }
    serde_json::from_str(&result.stdout).context("clipboard helper returned invalid JSON")
}

