use anyhow::{Result, anyhow};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use crate::config::AppConfig;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

pub trait SshTarget {
    fn host(&self) -> &str;
    fn ssh_command(&self) -> Option<&str>;
}

impl SshTarget for AppConfig {
    fn host(&self) -> &str {
        &self.host
    }

    fn ssh_command(&self) -> Option<&str> {
        self.ssh_command.as_deref()
    }
}

pub fn command_exists(command: &str) -> Result<Option<String>> {
    let result = run_local(
        "sh",
        &["-lc", &format!("command -v {}", shell_quote(command))],
        None,
    )?;
    let path = result.stdout.trim().to_string();
    if result.exit_code == 0 && !path.is_empty() {
        Ok(Some(path))
    } else {
        Ok(None)
    }
}

pub fn run_ssh<T: SshTarget>(
    target: &T,
    remote_command: &str,
    input: Option<&[u8]>,
) -> Result<CommandResult> {
    let args = ssh_args(target, remote_command)?;
    run_local(
        &args[0],
        &args[1..].iter().map(String::as_str).collect::<Vec<_>>(),
        input,
    )
}

pub fn run_local(program: &str, args: &[&str], input: Option<&[u8]>) -> Result<CommandResult> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| anyhow!("{program}: {error}"))?;

    if let Some(input) = input {
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(input)?;
        }
    }

    let output = child.wait_with_output()?;
    Ok(CommandResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        exit_code: output.status.code().unwrap_or(1),
    })
}

pub fn run_local_inherit(program: &str, args: &[&str]) -> Result<i32> {
    let status = Command::new(program).args(args).status()?;
    Ok(status.code().unwrap_or(1))
}

pub fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

pub fn remote_path_expr(value: &str) -> String {
    if value == "~" {
        "\"$HOME\"".to_string()
    } else if let Some(rest) = value.strip_prefix("~/") {
        format!("\"$HOME/{}\"", escape_double_quoted(rest))
    } else {
        shell_quote(value)
    }
}

pub fn target_label<T: SshTarget>(target: &T) -> String {
    target
        .ssh_command()
        .map(str::to_string)
        .unwrap_or_else(|| target.host().to_string())
}

pub fn ssh_args<T: SshTarget>(target: &T, remote_command: &str) -> Result<Vec<String>> {
    let Some(ssh_command) = target.ssh_command() else {
        return Ok(vec![
            "ssh".to_string(),
            target.host().to_string(),
            remote_command.to_string(),
        ]);
    };

    let mut parsed: Vec<String> = parse_shell_words(ssh_command)?
        .into_iter()
        .map(expand_home_arg)
        .collect();
    let Some(program) = parsed.first() else {
        return Err(anyhow!("SSH command is empty"));
    };
    if program != "ssh" && !program.ends_with("/ssh") {
        return Err(anyhow!("SSH command must start with ssh: {ssh_command}"));
    }
    parsed.push(remote_command.to_string());
    Ok(parsed)
}

pub fn ssh_display_command<T: SshTarget>(
    target: &T,
    remote_command: &str,
    ssh_options: &[&str],
) -> Result<String> {
    let args = if let Some(ssh_command) = target.ssh_command() {
        let parsed = parse_shell_words(ssh_command)?;
        let Some((program, rest)) = parsed.split_first() else {
            return Err(anyhow!("SSH command is empty"));
        };
        let mut args = vec![program.clone()];
        args.extend(ssh_options.iter().map(|value| value.to_string()));
        args.extend(rest.iter().cloned());
        args.push(remote_command.to_string());
        args
    } else {
        let mut args = vec!["ssh".to_string()];
        args.extend(ssh_options.iter().map(|value| value.to_string()));
        args.push(target.host().to_string());
        args.push(remote_command.to_string());
        args
    };

    Ok(args
        .into_iter()
        .enumerate()
        .map(|(idx, arg)| if idx == 0 { arg } else { shell_quote(&arg) })
        .collect::<Vec<_>>()
        .join(" "))
}

pub fn parse_shell_words(input: &str) -> Result<Vec<String>> {
    let mut words = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;

    for ch in input.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }

        if ch == '\\' && quote != Some('\'') {
            escaped = true;
            continue;
        }

        if let Some(active_quote) = quote {
            if ch == active_quote {
                quote = None;
            } else {
                current.push(ch);
            }
            continue;
        }

        if ch == '\'' || ch == '"' {
            quote = Some(ch);
            continue;
        }

        if ch.is_whitespace() {
            if !current.is_empty() {
                words.push(std::mem::take(&mut current));
            }
            continue;
        }

        current.push(ch);
    }

    if escaped {
        current.push('\\');
    }
    if quote.is_some() {
        return Err(anyhow!("unterminated quote in SSH command"));
    }
    if !current.is_empty() {
        words.push(current);
    }
    Ok(words)
}

fn escape_double_quoted(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('$', "\\$")
        .replace('`', "\\`")
}

fn expand_home_arg(value: String) -> String {
    if value == "~" {
        home_dir().display().to_string()
    } else if let Some(rest) = value.strip_prefix("~/") {
        home_dir().join(rest).display().to_string()
    } else {
        value
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("~"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug)]
    struct Target {
        host: String,
        ssh_command: Option<String>,
    }

    impl SshTarget for Target {
        fn host(&self) -> &str {
            &self.host
        }

        fn ssh_command(&self) -> Option<&str> {
            self.ssh_command.as_deref()
        }
    }

    #[test]
    fn quotes_shell_values() {
        assert_eq!(shell_quote("a'b"), "'a'\\''b'");
    }

    #[test]
    fn expands_remote_home_paths() {
        assert_eq!(remote_path_expr("~/.cache/x"), "\"$HOME/.cache/x\"");
        assert_eq!(remote_path_expr("/tmp/x"), "'/tmp/x'");
    }

    #[test]
    fn parses_quoted_ssh_commands() {
        assert_eq!(
            parse_shell_words("ssh -i ~/.ssh/example_ed25519 root@203.0.113.10").unwrap(),
            vec!["ssh", "-i", "~/.ssh/example_ed25519", "root@203.0.113.10"]
        );
        assert_eq!(
            parse_shell_words("ssh -o 'ProxyJump jump host' user@example").unwrap(),
            vec!["ssh", "-o", "ProxyJump jump host", "user@example"]
        );
    }

    #[test]
    fn builds_ssh_args_for_host_aliases() {
        let target = Target {
            host: "example-vps".to_string(),
            ssh_command: None,
        };
        assert_eq!(
            ssh_args(&target, "printf ok").unwrap(),
            vec!["ssh", "example-vps", "printf ok"]
        );
    }

    #[test]
    fn builds_ssh_args_for_full_commands() {
        let target = Target {
            host: "ignored".to_string(),
            ssh_command: Some("ssh -i ~/.ssh/example_ed25519 root@203.0.113.10".to_string()),
        };
        let args = ssh_args(&target, "printf ok").unwrap();
        assert_eq!(args[0], "ssh");
        assert_eq!(args.last().unwrap(), "printf ok");
        assert!(args.contains(&"root@203.0.113.10".to_string()));
        assert!(
            args.iter()
                .any(|arg| arg.ends_with("/.ssh/example_ed25519"))
        );
    }
}
