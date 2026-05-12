use anyhow::{Result, bail};
use std::io::{self, BufRead, IsTerminal, Write};

use crate::config::{
    AgentProfile, AppConfig, ConfigOverrides, config_path, load_config, save_config,
};
use crate::ssh::parse_shell_words;

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
        config.host = prompt_string_validated(
            input,
            output,
            "SSH host alias",
            &config.host,
            validate_host_alias,
        )?;
        config.ssh_command = None;
    } else {
        let current = config
            .ssh_command
            .as_deref()
            .unwrap_or("ssh -i ~/.ssh/example_ed25519 root@203.0.113.10");
        config.ssh_command = Some(prompt_string_validated(
            input,
            output,
            "Full SSH command",
            current,
            validate_ssh_command,
        )?);
    }

    let default_agent = if !config.default_agent.trim().is_empty() {
        config.default_agent.clone()
    } else if config.agents.contains_key("codex") {
        "codex".to_string()
    } else if config.agents.contains_key("claude") {
        "claude".to_string()
    } else {
        "agent".to_string()
    };
    let agent = prompt_string_validated(
        input,
        output,
        "Default agent profile name",
        &default_agent,
        validate_profile_name,
    )?;
    let agent_command = config
        .agents
        .get(&agent)
        .map(|profile| profile.command.as_str())
        .unwrap_or(agent.as_str());
    let command = prompt_string_validated(
        input,
        output,
        "Agent command",
        agent_command,
        validate_non_empty,
    )?;
    config.default_agent = agent.clone();
    config.agents.insert(agent, AgentProfile { command });

    config.tmux_session = prompt_string_validated(
        input,
        output,
        "Managed tmux session",
        &config.tmux_session,
        validate_tmux_session,
    )?;
    config.remote_cache_dir = prompt_string_validated(
        input,
        output,
        "Remote image cache dir",
        &config.remote_cache_dir,
        validate_non_empty,
    )?;
    config.remote_helper_path = prompt_string_validated(
        input,
        output,
        "Remote helper path",
        &config.remote_helper_path,
        validate_non_empty,
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

fn prompt_string_validated<F>(
    input: &mut impl BufRead,
    output: &mut impl Write,
    label: &str,
    default: &str,
    validate: F,
) -> Result<String>
where
    F: Fn(&str) -> Result<()>,
{
    loop {
        let value = prompt_string(input, output, label, default)?;
        match validate(&value) {
            Ok(()) => return Ok(value),
            Err(error) => writeln!(output, "{error}")?,
        }
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

fn validate_non_empty(value: &str) -> Result<()> {
    if value.trim().is_empty() {
        bail!("Please enter a value.");
    }
    Ok(())
}

fn validate_host_alias(value: &str) -> Result<()> {
    validate_non_empty(value)?;
    if value.starts_with("ssh ") {
        bail!("That looks like a full SSH command. Choose option 2 for full SSH commands.");
    }
    if value.split_whitespace().count() != 1 {
        bail!("SSH host aliases cannot contain whitespace.");
    }
    Ok(())
}

fn validate_ssh_command(value: &str) -> Result<()> {
    validate_non_empty(value)?;
    let words = parse_shell_words(value)?;
    let Some(program) = words.first() else {
        bail!("SSH command is empty.");
    };
    if program != "ssh" && !program.ends_with("/ssh") {
        bail!("SSH command must start with ssh.");
    }
    if words.len() < 2 {
        bail!("SSH command must include a remote host.");
    }
    Ok(())
}

fn validate_profile_name(value: &str) -> Result<()> {
    validate_non_empty(value)?;
    if value.split_whitespace().count() != 1 {
        bail!("Agent profile names cannot contain whitespace.");
    }
    Ok(())
}

fn validate_tmux_session(value: &str) -> Result<()> {
    validate_non_empty(value)?;
    if value.chars().any(char::is_whitespace) || value.contains(':') {
        bail!("tmux session names cannot contain whitespace or ':'.");
    }
    Ok(())
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
        assert_eq!(config.default_agent, "claude");
        assert_eq!(config.agents["claude"].command, "claude --model sonnet");
        assert_eq!(config.tmux_session, "work");
        assert_eq!(config.remote_cache_dir, "/tmp/images");
        assert_eq!(config.cleanup_daemon.max_age_seconds, 3600);
        assert_eq!(config.cleanup_daemon.interval_seconds, 60);
        assert!(config.daemon.hijack_paste);
        assert!(String::from_utf8(output).unwrap().contains("Remote target"));
    }

    #[test]
    fn wizard_reprompts_invalid_ssh_target() {
        let mut config = AppConfig::default();
        let answers = b"1\nssh user@example.test\nexample-vps\ncodex\ncodex\nagent\n~/.cache/ssh-bin-paste/images\n~/.local/bin/ssh-bin-paste-remote\ny\n86400\n300\nn\n";
        let mut input = BufReader::new(Cursor::new(&answers[..]));
        let mut output = Vec::new();

        run_wizard(&mut config, &mut input, &mut output).unwrap();

        assert_eq!(config.host, "example-vps");
        assert!(
            String::from_utf8(output)
                .unwrap()
                .contains("Choose option 2 for full SSH commands")
        );
    }
}
