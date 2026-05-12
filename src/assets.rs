use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;

pub const REMOTE_HELPER: &str = include_str!("../remote/ssh-bin-paste-remote.sh");
pub const CLIPBOARD_IMAGE_SWIFT: &str = include_str!("../native/clipboard-image.swift");
pub const PASTE_DAEMON_SWIFT: &str = include_str!("../native/paste-daemon.swift");

pub fn write_temp_asset(name: &str, contents: &str) -> Result<PathBuf> {
    let dir = std::env::temp_dir().join("ssh-bin-paste-assets");
    fs::create_dir_all(&dir).with_context(|| format!("failed to create {}", dir.display()))?;
    let path = dir.join(name);
    fs::write(&path, contents).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(path)
}
