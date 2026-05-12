use anyhow::{Result, bail};

use crate::config::{AppConfig, resolve_agent_command, save_config};
use crate::panes::list_panes;
use crate::ssh::{run_ssh, shell_quote, ssh_display_command, target_label};

pub fn start_managed_agent(
    config: &AppConfig,
    agent: &str,
    session_override: Option<&str>,
) -> Result<()> {
    let session_name = session_override.unwrap_or(&config.tmux_session);
    let agent_command = resolve_agent_command(config, agent);
    let tmux_command = format!(
        "tmux has-session -t {} 2>/dev/null || tmux new-session -d -s {} -n agent {}",
        shell_quote(session_name),
        shell_quote(session_name),
        shell_quote(&format!("exec {agent_command}"))
    );
    let result = run_ssh(config, &tmux_command, None)?;
    if result.exit_code != 0 {
        bail!("failed to start managed tmux session: {}", result.stderr.trim());
    }

    let mut started_config = config.clone();
    started_config.tmux_session = session_name.to_string();
    let panes = list_panes(&started_config)?;
    let Some(pane) = panes
        .iter()
        .find(|candidate| candidate.session_name == session_name)
    else {
        bail!("Started tmux session {session_name}, but could not find its pane.");
    };

    started_config.target_pane = Some(pane.pane_id.clone());
    save_config(&started_config)?;
    println!(
        "agent session ready: {}:{} target {}",
        target_label(config),
        session_name,
        pane.pane_id
    );
    println!(
        "attach with: {}",
        ssh_display_command(config, &format!("tmux attach -t {session_name}"), &["-t"])?
    );
    Ok(())
}

