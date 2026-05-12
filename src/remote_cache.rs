use anyhow::{Result, bail};
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::clipboard::CapturedImage;
use crate::config::AppConfig;
use crate::remote_helper::run_remote_helper;
use crate::ssh::{run_ssh, shell_quote, target_label};

pub fn upload_image(config: &AppConfig, image: &CapturedImage) -> Result<String> {
    let cache_dir = ensure_remote_cache(config)?;
    let ext = extension_for_mime(&image.mime_type);
    let timestamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis();
    let remote_path = format!(
        "{}/ssh-bin-paste-{}-{}.{}",
        cache_dir.trim_end_matches('/'),
        timestamp,
        Uuid::new_v4(),
        ext
    );
    let data = fs::read(&image.path)?;
    let result = run_ssh(
        config,
        &format!(
            "cat > {} && chmod 0600 {}",
            shell_quote(&remote_path),
            shell_quote(&remote_path)
        ),
        Some(&data),
    )?;
    if result.exit_code != 0 {
        bail!("failed to upload image: {}", result.stderr.trim());
    }
    Ok(remote_path)
}

pub fn cleanup_remote_images(config: &AppConfig, max_age_seconds: u64) -> Result<()> {
    let seconds = if max_age_seconds > 0 {
        max_age_seconds
    } else {
        86_400
    };
    let result = run_remote_helper(
        config,
        &[
            "cleanup".to_string(),
            config.remote_cache_dir.clone(),
            seconds.to_string(),
        ],
        None,
    )?;
    if result.exit_code != 0 {
        bail!("remote cleanup failed: {}", result.stderr.trim());
    }
    println!(
        "cleaned images older than {seconds}s on {}",
        target_label(config)
    );
    Ok(())
}

pub fn remote_cleanup_daemon(config: &AppConfig, action: &str) -> Result<()> {
    let args = match action {
        "start" => vec![
            "daemon-start".to_string(),
            config.remote_cache_dir.clone(),
            config.cleanup_daemon.max_age_seconds.to_string(),
            config.cleanup_daemon.interval_seconds.to_string(),
        ],
        "stop" => vec!["daemon-stop".to_string()],
        "status" => vec!["daemon-status".to_string()],
        _ => bail!("cleanup-daemon action must be start, stop, or status"),
    };
    let result = run_remote_helper(config, &args, None)?;
    if result.exit_code != 0 {
        bail!(
            "remote cleanup daemon {action} failed: {}",
            result.stderr.trim()
        );
    }
    println!("{}", result.stdout.trim());
    Ok(())
}

fn ensure_remote_cache(config: &AppConfig) -> Result<String> {
    let result = run_remote_helper(
        config,
        &["ensure-cache".to_string(), config.remote_cache_dir.clone()],
        None,
    )?;
    if result.exit_code != 0 {
        bail!("remote cache is not writable: {}", result.stderr.trim());
    }
    Ok(result.stdout.trim().to_string())
}

fn extension_for_mime(mime_type: &str) -> &'static str {
    match mime_type {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        "image/webp" => "webp",
        "image/gif" => "gif",
        _ => "bin",
    }
}

