use anyhow::Result;

use crate::agent::insertion::inject_text;
use crate::agent::tmux::resolve_target_pane;
use crate::config::AppConfig;
use crate::transfer::cache::upload_payload;
use crate::transfer::clipboard::capture_clipboard_payload;

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
