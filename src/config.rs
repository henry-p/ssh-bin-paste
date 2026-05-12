use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProfile {
    pub command: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CleanupDaemonConfig {
    pub enabled: bool,
    pub max_age_seconds: u64,
    pub interval_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DaemonConfig {
    pub shortcut: String,
    pub hijack_paste: bool,
    pub allowlisted_apps: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AppConfig {
    pub host: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ssh_command: Option<String>,
    pub default_agent: String,
    pub tmux_session: String,
    pub remote_cache_dir: String,
    pub remote_helper_path: String,
    pub cleanup_daemon: CleanupDaemonConfig,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target_pane: Option<String>,
    pub agents: BTreeMap<String, AgentProfile>,
    pub daemon: DaemonConfig,
}

#[derive(Debug, Clone, Default)]
pub struct ConfigOverrides {
    pub host: Option<String>,
    pub ssh_command: Option<String>,
}

impl Default for AppConfig {
    fn default() -> Self {
        let mut agents = BTreeMap::new();
        agents.insert(
            "codex".to_string(),
            AgentProfile {
                command: "codex".to_string(),
            },
        );
        agents.insert(
            "claude".to_string(),
            AgentProfile {
                command: "claude".to_string(),
            },
        );

        Self {
            host: "example-vps".to_string(),
            ssh_command: None,
            default_agent: "codex".to_string(),
            tmux_session: "agent".to_string(),
            remote_cache_dir: "~/.cache/ssh-bin-paste/images".to_string(),
            remote_helper_path: "~/.local/bin/ssh-bin-paste-remote".to_string(),
            cleanup_daemon: CleanupDaemonConfig {
                enabled: true,
                max_age_seconds: 86_400,
                interval_seconds: 300,
            },
            target_pane: None,
            agents,
            daemon: DaemonConfig {
                shortcut: "cmd+shift+v".to_string(),
                hijack_paste: false,
                allowlisted_apps: vec![
                    "com.googlecode.iterm2".to_string(),
                    "com.apple.Terminal".to_string(),
                    "com.github.wez.wezterm".to_string(),
                    "com.mitchellh.ghostty".to_string(),
                    "com.termius-dmg.mac".to_string(),
                ],
            },
        }
    }
}

pub fn config_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("ssh-bin-paste").join("config.json")
}

pub fn load_config(overrides: ConfigOverrides) -> Result<AppConfig> {
    let mut config = match fs::read_to_string(config_path()) {
        Ok(raw) => {
            let mut base = serde_json::to_value(AppConfig::default())?;
            let user =
                serde_json::from_str::<Value>(&raw).context("failed to parse config file")?;
            merge_json(&mut base, user);
            serde_json::from_value::<AppConfig>(base).context("failed to load config file")?
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => AppConfig::default(),
        Err(error) => return Err(error).context("failed to read config file"),
    };

    if let Some(host) = overrides.host {
        config.host = host;
    }
    if let Some(ssh_command) = overrides.ssh_command {
        config.ssh_command = Some(ssh_command);
    }
    Ok(config)
}

pub fn save_config(config: &AppConfig) -> Result<()> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(
        &path,
        format!("{}\n", serde_json::to_string_pretty(config)?),
    )
    .with_context(|| format!("failed to write {}", path.display()))
}

pub fn ensure_config_file() -> Result<PathBuf> {
    let path = config_path();
    if path.exists() {
        return Ok(path);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(
        &path,
        format!("{}\n", serde_json::to_string_pretty(&AppConfig::default())?),
    )
    .with_context(|| format!("failed to write {}", path.display()))?;
    Ok(path)
}

pub fn resolve_agent_command(config: &AppConfig, agent: &str) -> String {
    config
        .agents
        .get(agent)
        .map(|profile| profile.command.clone())
        .unwrap_or_else(|| agent.to_string())
}

fn merge_json(base: &mut Value, overlay: Value) {
    match (base, overlay) {
        (Value::Object(base_map), Value::Object(overlay_map)) => {
            for (key, value) in overlay_map {
                match base_map.get_mut(&key) {
                    Some(existing) => merge_json(existing, value),
                    None => {
                        base_map.insert(key, value);
                    }
                }
            }
        }
        (base_value, overlay_value) => *base_value = overlay_value,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_configured_agent_profiles() {
        let mut config = AppConfig::default();
        config.agents.insert(
            "custom".to_string(),
            AgentProfile {
                command: "agent --flag".to_string(),
            },
        );

        assert_eq!(resolve_agent_command(&config, "custom"), "agent --flag");
        assert_eq!(
            resolve_agent_command(&config, "unknown-agent"),
            "unknown-agent"
        );
    }
}
