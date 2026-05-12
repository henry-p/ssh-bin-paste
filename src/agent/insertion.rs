use anyhow::{Result, bail};

use crate::config::AppConfig;
use crate::remote_helper::run_remote_helper;

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
