use anyhow::{Result, bail};
use std::io::{self, IsTerminal, Write};

use crate::config::{AppConfig, save_config};
use crate::remote_helper::run_remote_helper;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TmuxPane {
    pub session_name: String,
    pub window_pane: String,
    pub pane_id: String,
    pub pane_pid: Option<u32>,
    pub command: String,
    pub cwd: String,
    pub title: String,
    pub score: u32,
}

pub fn list_panes(config: &AppConfig) -> Result<Vec<TmuxPane>> {
    let result = run_remote_helper(config, &["panes".to_string()], None)?;
    if result.exit_code != 0 {
        bail!("failed to list tmux panes: {}", result.stderr.trim());
    }
    let mut panes = result
        .stdout
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(parse_pane_line)
        .collect::<Vec<_>>();
    panes.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then_with(|| a.session_name.cmp(&b.session_name))
    });
    Ok(panes)
}

pub fn print_panes(panes: &[TmuxPane]) {
    if panes.is_empty() {
        println!("No tmux panes found on the remote host.");
        return;
    }
    for pane in panes {
        let score = if pane.score > 0 {
            format!(" agent-score={}", pane.score)
        } else {
            String::new()
        };
        println!(
            "{:<6} {}:{:<5} {:<16} {}{}",
            pane.pane_id, pane.session_name, pane.window_pane, pane.command, pane.cwd, score
        );
    }
}

pub fn select_and_save_pane(
    config: &AppConfig,
    panes: &[TmuxPane],
    requested_target: Option<&str>,
) -> Result<String> {
    if panes.is_empty() {
        bail!("No tmux panes found on the remote host.");
    }
    let target = match requested_target {
        Some(target) => target.to_string(),
        None => choose_pane(panes)?,
    };
    let Some(found) = panes
        .iter()
        .find(|pane| pane.pane_id == target || format!("{}:{}", pane.session_name, pane.window_pane) == target)
    else {
        bail!("Target pane {target} was not found.");
    };

    let mut next = config.clone();
    next.target_pane = Some(found.pane_id.clone());
    save_config(&next)?;
    println!(
        "saved target pane {} ({}:{})",
        found.pane_id, found.session_name, found.window_pane
    );
    Ok(found.pane_id.clone())
}

pub fn resolve_target_pane(config: &AppConfig) -> Result<String> {
    if let Some(target_pane) = &config.target_pane {
        return Ok(target_pane.clone());
    }
    let panes = likely_agent_panes(list_panes(config)?);
    if panes.is_empty() {
        bail!(
            "No tmux panes found. Start an agent with `ssh-bin-paste start --agent codex` or select an existing tmux pane."
        );
    }
    if panes.len() == 1 {
        return Ok(panes[0].pane_id.clone());
    }
    choose_pane(&panes)
}

pub fn likely_agent_panes(panes: Vec<TmuxPane>) -> Vec<TmuxPane> {
    let candidates = panes
        .iter()
        .filter(|pane| pane.score > 0)
        .cloned()
        .collect::<Vec<_>>();
    if candidates.is_empty() {
        panes
    } else {
        candidates
    }
}

pub fn parse_pane_line(line: &str) -> TmuxPane {
    let mut parts = line.split('\t');
    let session_name = parts.next().unwrap_or_default().to_string();
    let window_pane = parts.next().unwrap_or_default().to_string();
    let pane_id = parts.next().unwrap_or_default().to_string();
    let pane_pid = parts.next().and_then(|value| value.parse::<u32>().ok());
    let command = parts.next().unwrap_or_default().to_string();
    let cwd = parts.next().unwrap_or_default().to_string();
    let title = parts.next().unwrap_or_default().to_string();
    let score = score_pane(&session_name, &command, &title);
    TmuxPane {
        session_name,
        window_pane,
        pane_id,
        pane_pid,
        command,
        cwd,
        title,
        score,
    }
}

fn score_pane(session_name: &str, command: &str, title: &str) -> u32 {
    let haystack = format!("{session_name} {command} {title}").to_lowercase();
    let mut score = 0;
    if haystack.contains("codex") {
        score += 4;
    }
    if haystack.contains("claude") {
        score += 4;
    }
    if haystack.contains("agent") {
        score += 2;
    }
    if command == "node" {
        score += 1;
    }
    score
}

fn choose_pane(panes: &[TmuxPane]) -> Result<String> {
    if !io::stdin().is_terminal() {
        bail!("Multiple tmux panes found; rerun with `panes --select` in an interactive terminal.");
    }
    print_panes(panes);
    print!("Target pane id: ");
    io::stdout().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    Ok(answer.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_tmux_pane_format_and_scores_likely_agents() {
        let pane = parse_pane_line("agent\t0.0\t%4\t1234\tnode\t/root\tcodex");
        assert_eq!(pane.session_name, "agent");
        assert_eq!(pane.window_pane, "0.0");
        assert_eq!(pane.pane_id, "%4");
        assert!(pane.score > 0);
    }
}

