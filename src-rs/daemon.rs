use anyhow::{Result, bail};

use crate::assets::{PASTE_DAEMON_SWIFT, write_temp_asset};
use crate::config::AppConfig;
use crate::ssh::run_local_inherit;

pub fn run_daemon(config: &AppConfig, hijack_paste: bool) -> Result<()> {
    let helper = write_temp_asset("paste-daemon.swift", PASTE_DAEMON_SWIFT)?;
    let command = std::env::current_exe()?.display().to_string();
    let helper_string = helper.display().to_string();
    let apps = config.daemon.allowlisted_apps.join(",");
    let mut owned_args = vec![
        helper_string,
        "--command".to_string(),
        command,
        "--allowlisted-apps".to_string(),
        apps,
    ];
    if let Some(ssh_command) = &config.ssh_command {
        owned_args.push("--ssh".to_string());
        owned_args.push(ssh_command.clone());
    } else {
        owned_args.push("--host".to_string());
        owned_args.push(config.host.clone());
    }
    if hijack_paste {
        owned_args.push("--hijack-paste".to_string());
    }
    let args = owned_args.iter().map(String::as_str).collect::<Vec<_>>();
    let code = run_local_inherit("swift", &args)?;
    if code != 0 {
        bail!("daemon exited with code {code}");
    }
    Ok(())
}

