use anyhow::{Result, bail};

use crate::clipboard::capture_clipboard_payload;
use crate::config::AppConfig;
use crate::panes::resolve_target_pane;
use crate::remote_cache::upload_payload;
use crate::remote_helper::run_remote_helper;

pub fn paste_clipboard_payload(config: &AppConfig, target_pane: Option<&str>) -> Result<()> {
    let payload = capture_clipboard_payload()?;
    let remote_path = upload_payload(config, &payload)?;
    let target = match target_pane {
        Some(target) => target.to_string(),
        None => resolve_target_pane(config)?,
    };
    inject_text(config, &target, &remote_path)?;
    println!("pasted {remote_path} into {target}");
    Ok(())
}

pub fn inject_text(config: &AppConfig, target_pane: &str, text: &str) -> Result<()> {
    let result = run_remote_helper(
        config,
        &["inject".to_string(), target_pane.to_string()],
        Some(text.as_bytes()),
    )?;
    if result.exit_code != 0 {
        bail!(
            "remote paste failed: {}",
            if result.stderr.trim().is_empty() {
                result.stdout.trim()
            } else {
                result.stderr.trim()
            }
        );
    }
    Ok(())
}
