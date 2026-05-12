use anyhow::Result;
use std::io::{self, BufRead, IsTerminal, Write};

use crate::config::{
    AgentProfile, AppConfig, ConfigOverrides, config_path, load_config, save_config,
};

pub fn run_config_command(print_path: bool, print_config: bool) -> Result<()> {
    if print_path {
        println!("{}", config_path().display());
        return Ok(());
    }

    if print_config {
        println!(
            "{}",
            serde_json::to_string_pretty(&load_config(ConfigOverrides::default())?)?
        );
        return Ok(());
    }

    if !io::stdin().is_terminal() {
        anyhow::bail!(
            "config wizard requires an interactive terminal; use `ssh-bin-paste config --path` to locate the file"
        );
    }

    let mut config = load_config(ConfigOverrides::default())?;
    println!("ssh-bin-paste config wizard");
    println!("Config file: {}", config_path().display());
    println!();

    run_wizard(&mut config, &mut io::stdin().lock(), &mut io::stdout())?;
    save_config(&config)?;
    println!();
    println!("wrote {}", config_path().display());
    Ok(())
}

fn run_wizard(
    config: &mut AppConfig,
    input: &mut impl BufRead,
    output: &mut impl Write,
) -> Result<()> {
    let target_mode = prompt_choice(
        input,
        output,
        "Remote target",
        &["SSH config host alias", "Full SSH command"],
        if config.ssh_command.is_some() { 2 } else { 1 },
    )?;
    if target_mode == 1 {
        config.host = prompt_string(input, output, "SSH host alias", &config.host)?;
        config.ssh_command = None;
    } else {
        let current = config
            .ssh_command
            .as_deref()
            .unwrap_or("ssh -i ~/.ssh/example_ed25519 root@203.0.113.10");
        config.ssh_command = Some(prompt_string(input, output, "Full SSH command", current)?);
    }

    let default_agent = if config.agents.contains_key("codex") {
        "codex"
    } else if config.agents.contains_key("claude") {
        "claude"
    } else {
        "agent"
    };
    let agent = prompt_string(input, output, "Default agent profile name", default_agent)?;
    let agent_command = config
        .agents
        .get(&agent)
        .map(|profile| profile.command.as_str())
        .unwrap_or(agent.as_str());
    let command = prompt_string(input, output, "Agent command", agent_command)?;
    config.agents.insert(agent, AgentProfile { command });

    config.tmux_session =
        prompt_string(input, output, "Managed tmux session", &config.tmux_session)?;
    config.remote_cache_dir = prompt_string(
        input,
        output,
        "Remote image cache dir",
        &config.remote_cache_dir,
    )?;
    config.remote_helper_path = prompt_string(
        input,
        output,
        "Remote helper path",
        &config.remote_helper_path,
    )?;
    config.cleanup_daemon.enabled = prompt_bool(
        input,
        output,
        "Start remote cleanup daemon",
        config.cleanup_daemon.enabled,
    )?;
    config.cleanup_daemon.max_age_seconds = prompt_u64(
        input,
        output,
        "Cleanup max age seconds",
        config.cleanup_daemon.max_age_seconds,
    )?;
    config.cleanup_daemon.interval_seconds = prompt_u64(
        input,
        output,
        "Cleanup interval seconds",
        config.cleanup_daemon.interval_seconds,
    )?;
    config.daemon.hijack_paste = prompt_bool(
        input,
        output,
        "Hijack normal paste in allowlisted terminal apps",
        config.daemon.hijack_paste,
    )?;
    Ok(())
}

fn prompt_choice(
    input: &mut impl BufRead,
    output: &mut impl Write,
    label: &str,
    choices: &[&str],
    default: usize,
) -> Result<usize> {
    loop {
        writeln!(output, "{label}:")?;
        for (idx, choice) in choices.iter().enumerate() {
            writeln!(output, "  {}. {}", idx + 1, choice)?;
        }
        write!(output, "Choose [{default}]: ")?;
        output.flush()?;
        let answer = read_line(input)?;
        if answer.is_empty() {
            return Ok(default);
        }
        if let Ok(choice) = answer.parse::<usize>() {
            if (1..=choices.len()).contains(&choice) {
                return Ok(choice);
            }
        }
        writeln!(output, "Please enter a number from 1 to {}.", choices.len())?;
    }
}

fn prompt_string(
    input: &mut impl BufRead,
    output: &mut impl Write,
    label: &str,
    default: &str,
) -> Result<String> {
    write!(output, "{label} [{default}]: ")?;
    output.flush()?;
    let answer = read_line(input)?;
    if answer.is_empty() {
        Ok(default.to_string())
    } else {
        Ok(answer)
    }
}

fn prompt_bool(
    input: &mut impl BufRead,
    output: &mut impl Write,
    label: &str,
    default: bool,
) -> Result<bool> {
    let default_label = if default { "Y/n" } else { "y/N" };
    loop {
        write!(output, "{label} [{default_label}]: ")?;
        output.flush()?;
        let answer = read_line(input)?.to_lowercase();
        match answer.as_str() {
            "" => return Ok(default),
            "y" | "yes" => return Ok(true),
            "n" | "no" => return Ok(false),
            _ => writeln!(output, "Please answer yes or no.")?,
        }
    }
}

fn prompt_u64(
    input: &mut impl BufRead,
    output: &mut impl Write,
    label: &str,
    default: u64,
) -> Result<u64> {
    loop {
        write!(output, "{label} [{default}]: ")?;
        output.flush()?;
        let answer = read_line(input)?;
        if answer.is_empty() {
            return Ok(default);
        }
        if let Ok(value) = answer.parse::<u64>() {
            return Ok(value);
        }
        writeln!(output, "Please enter a positive integer.")?;
    }
}

fn read_line(input: &mut impl BufRead) -> Result<String> {
    let mut line = String::new();
    input.read_line(&mut line)?;
    Ok(line.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufReader, Cursor};

    #[test]
    fn wizard_updates_config_from_answers() {
        let mut config = AppConfig::default();
        let answers = b"2\nssh user@example.test\nclaude\nclaude --model sonnet\nwork\n/tmp/images\n~/.local/bin/helper\ny\n3600\n60\ny\n";
        let mut input = BufReader::new(Cursor::new(&answers[..]));
        let mut output = Vec::new();

        run_wizard(&mut config, &mut input, &mut output).unwrap();

        assert_eq!(config.ssh_command.as_deref(), Some("ssh user@example.test"));
        assert_eq!(config.agents["claude"].command, "claude --model sonnet");
        assert_eq!(config.tmux_session, "work");
        assert_eq!(config.remote_cache_dir, "/tmp/images");
        assert_eq!(config.cleanup_daemon.max_age_seconds, 3600);
        assert_eq!(config.cleanup_daemon.interval_seconds, 60);
        assert!(config.daemon.hijack_paste);
        assert!(String::from_utf8(output).unwrap().contains("Remote target"));
    }
}
