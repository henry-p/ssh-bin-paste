use anyhow::{Context, Result, bail};

use crate::assets::REMOTE_HELPER;
use crate::config::AppConfig;
use crate::remote_helper::run_remote_helper;
use crate::ssh::{remote_path_expr, run_ssh, target_label};

#[derive(Debug, Clone, Default)]
pub struct InstallRemoteOptions {
    pub cleanup_daemon: Option<bool>,
    pub cleanup_max_age_seconds: Option<u64>,
    pub cleanup_interval_seconds: Option<u64>,
}

pub fn install_remote_helper(config: &AppConfig, options: &InstallRemoteOptions) -> Result<()> {
    let dir = remote_dirname(&config.remote_helper_path);
    let mkdir = run_ssh(config, &format!("mkdir -p {}", remote_path_expr(&dir)), None)?;
    if mkdir.exit_code != 0 {
        bail!("failed to create remote helper directory: {}", mkdir.stderr.trim());
    }

    let install = run_ssh(
        config,
        &format!(
            "cat > {} && chmod 0755 {}",
            remote_path_expr(&config.remote_helper_path),
            remote_path_expr(&config.remote_helper_path)
        ),
        Some(REMOTE_HELPER.as_bytes()),
    )?;
    if install.exit_code != 0 {
        bail!("failed to install remote helper: {}", install.stderr.trim());
    }

    let verify = run_ssh(
        config,
        &format!("{} version", remote_path_expr(&config.remote_helper_path)),
        None,
    )?;
    if verify.exit_code != 0 {
        bail!("remote helper did not run: {}", verify.stderr.trim());
    }

    println!(
        "installed {} on {} ({})",
        config.remote_helper_path,
        target_label(config),
        verify.stdout.trim()
    );

    if options.cleanup_daemon.unwrap_or(config.cleanup_daemon.enabled) {
        let max_age = options
            .cleanup_max_age_seconds
            .unwrap_or(config.cleanup_daemon.max_age_seconds);
        let interval = options
            .cleanup_interval_seconds
            .unwrap_or(config.cleanup_daemon.interval_seconds);
        let result = run_remote_helper(
            config,
            &[
                "daemon-start".to_string(),
                config.remote_cache_dir.clone(),
                max_age.to_string(),
                interval.to_string(),
            ],
            None,
        )
        .context("failed to start cleanup daemon")?;
        if result.exit_code != 0 {
            bail!("failed to start cleanup daemon: {}", result.stderr.trim());
        }
        println!("cleanup daemon {}", result.stdout.trim());
    }

    Ok(())
}

fn remote_dirname(path: &str) -> String {
    let normalized = path.trim_end_matches('/');
    match normalized.rfind('/') {
        Some(idx) if idx > 0 => normalized[..idx].to_string(),
        _ => ".".to_string(),
    }
}

