use anyhow::Result;

use crate::config::AppConfig;
use crate::ssh::{command_exists, remote_path_expr, run_ssh, shell_quote};

struct Check {
    label: String,
    ok: bool,
    detail: String,
    required: bool,
}

pub fn run_doctor(config: &AppConfig, agent_command: &str) -> Result<bool> {
    let mut checks = Vec::new();
    checks.push(Check {
        label: "local platform".to_string(),
        ok: cfg!(target_os = "macos"),
        detail: if cfg!(target_os = "macos") {
            "macOS".to_string()
        } else {
            "macOS is required for clipboard capture".to_string()
        },
        required: true,
    });

    for command in ["ssh", "swift"] {
        let path = command_exists(command)?;
        checks.push(Check {
            label: format!("local {command}"),
            ok: path.is_some(),
            detail: path.unwrap_or_else(|| "not found in PATH".to_string()),
            required: true,
        });
    }

    checks.push(remote_check(
        config,
        "ssh access",
        "printf ok",
        "ok",
        true,
        "ok",
    )?);
    checks.push(remote_command_check(config, "remote tmux", "tmux", true)?);
    checks.push(remote_command_check(
        config,
        "remote agent",
        agent_command,
        true,
    )?);
    checks.push(remote_writable_cache_check(config)?);

    for check in &checks {
        let mark = if check.ok {
            "ok"
        } else if check.required {
            "fail"
        } else {
            "warn"
        };
        println!("{mark:<4} {}: {}", check.label, check.detail);
    }

    Ok(checks.iter().all(|check| check.ok || !check.required))
}

fn remote_command_check(
    config: &AppConfig,
    label: &str,
    command: &str,
    required: bool,
) -> Result<Check> {
    let result = run_ssh(
        config,
        &format!("command -v {} 2>/dev/null || true", shell_quote(command)),
        None,
    )?;
    let detail = result.stdout.trim().to_string();
    Ok(Check {
        label: label.to_string(),
        ok: result.exit_code == 0 && !detail.is_empty(),
        detail: if detail.is_empty() {
            format!("{command} not found")
        } else {
            detail
        },
        required,
    })
}

fn remote_writable_cache_check(config: &AppConfig) -> Result<Check> {
    let dir = remote_path_expr(&config.remote_cache_dir);
    let command = format!("mkdir -p {dir} && test -d {dir} && test -w {dir} && printf ok");
    remote_check(
        config,
        "remote cache dir",
        &command,
        "ok",
        true,
        &config.remote_cache_dir,
    )
}

fn remote_check(
    config: &AppConfig,
    label: &str,
    command: &str,
    expected: &str,
    required: bool,
    success_detail: &str,
) -> Result<Check> {
    let result = run_ssh(config, command, None)?;
    let stdout = result.stdout.trim();
    let stderr = result.stderr.trim();
    let ok = result.exit_code == 0 && stdout == expected;
    Ok(Check {
        label: label.to_string(),
        ok,
        detail: if ok {
            success_detail.to_string()
        } else if !stderr.is_empty() {
            stderr.to_string()
        } else if !stdout.is_empty() {
            stdout.to_string()
        } else {
            format!("remote command exited {}", result.exit_code)
        },
        required,
    })
}
