use anyhow::{Context, Result, bail};

use crate::assets::REMOTE_HELPER;
use crate::config::AppConfig;
use crate::remote_helper::run_remote_helper;
use crate::ssh::{remote_path_expr, run_ssh, shell_quote, target_label};

#[derive(Debug, Clone, Default)]
pub struct InstallRemoteOptions {
    pub cleanup_daemon: Option<bool>,
    pub cleanup_max_age_seconds: Option<u64>,
    pub cleanup_interval_seconds: Option<u64>,
}

pub fn install_remote_helper(config: &AppConfig, options: &InstallRemoteOptions) -> Result<()> {
    let dir = remote_dirname(&config.remote_helper_path);
    let helper_name = remote_basename(&config.remote_helper_path);
    let wrapper_path = remote_join(&dir, "ssh-bin-paste");
    let mkdir = run_ssh(
        config,
        &format!("mkdir -p {}", remote_path_expr(&dir)),
        None,
    )?;
    if mkdir.exit_code != 0 {
        bail!(
            "failed to create remote helper directory: {}",
            mkdir.stderr.trim()
        );
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

    let wrapper = remote_wrapper_script(&helper_name);
    let install_wrapper = run_ssh(
        config,
        &format!(
            "cat > {} && chmod 0755 {}",
            remote_path_expr(&wrapper_path),
            remote_path_expr(&wrapper_path)
        ),
        Some(wrapper.as_bytes()),
    )?;
    if install_wrapper.exit_code != 0 {
        bail!(
            "failed to install remote attach command: {}",
            install_wrapper.stderr.trim()
        );
    }
    ensure_remote_wrapper_on_path(config, &dir)?;

    println!(
        "installed {} and {} on {} ({})",
        config.remote_helper_path,
        wrapper_path,
        target_label(config),
        verify.stdout.trim()
    );

    if options
        .cleanup_daemon
        .unwrap_or(config.cleanup_daemon.enabled)
    {
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

fn remote_basename(path: &str) -> String {
    let normalized = path.trim_end_matches('/');
    match normalized.rfind('/') {
        Some(idx) => normalized[idx + 1..].to_string(),
        None => normalized.to_string(),
    }
}

fn remote_join(dir: &str, name: &str) -> String {
    if dir == "." {
        name.to_string()
    } else {
        format!("{}/{}", dir.trim_end_matches('/'), name)
    }
}

fn remote_wrapper_script(helper_name: &str) -> String {
    format!(
        "#!/usr/bin/env bash\nset -euo pipefail\nDIR=\"$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd)\"\nHELPER_NAME={}\nexec \"$DIR/$HELPER_NAME\" \"$@\"\n",
        shell_quote(helper_name)
    )
}

fn ensure_remote_wrapper_on_path(config: &AppConfig, dir: &str) -> Result<()> {
    let block = profile_path_block(dir);
    let command = format!(
        "if ! command -v ssh-bin-paste >/dev/null 2>&1; then \
         for profile in \"$HOME/.profile\" \"$HOME/.zshrc\" \"$HOME/.bashrc\"; do \
         touch \"$profile\"; \
         grep -q 'ssh-bin-paste PATH' \"$profile\" || cat >> \"$profile\" <<'SSH_BIN_PASTE_PATH_EOF'\n{}\nSSH_BIN_PASTE_PATH_EOF\n; \
         done; \
         fi",
        block
    );
    let result = run_ssh(config, &command, None)?;
    if result.exit_code != 0 {
        bail!(
            "failed to update remote shell PATH for ssh-bin-paste attach: {}",
            result.stderr.trim()
        );
    }
    Ok(())
}

fn profile_path_block(dir: &str) -> String {
    let assignment = if dir == "~" {
        "SBP_BIN_DIR=\"$HOME\"".to_string()
    } else if let Some(rest) = dir.strip_prefix("~/") {
        format!(
            "SBP_BIN_DIR=\"$HOME/{}\"",
            escape_profile_double_quoted(rest)
        )
    } else {
        format!("SBP_BIN_DIR={}", shell_quote(dir))
    };
    format!(
        "\n# ssh-bin-paste PATH\n{}\ncase \":$PATH:\" in\n  *\":$SBP_BIN_DIR:\"*) ;;\n  *) export PATH=\"$SBP_BIN_DIR:$PATH\" ;;\nesac\n",
        assignment
    )
}

fn escape_profile_double_quoted(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('$', "\\$")
        .replace('`', "\\`")
}
