use anyhow::{Result, bail};

use crate::config::{config_path, ensure_config_file};
use crate::ssh::{parse_shell_words, run_local, run_local_inherit};

pub fn run_config_command(print_path: bool, editor: Option<&str>) -> Result<()> {
    if print_path {
        println!("{}", config_path().display());
        return Ok(());
    }

    let path = ensure_config_file()?;
    let path_string = path.display().to_string();
    let editor_command = editor
        .map(str::to_string)
        .or_else(|| std::env::var("VISUAL").ok())
        .or_else(|| std::env::var("EDITOR").ok());

    if let Some(editor_command) = editor_command.filter(|value| !value.trim().is_empty()) {
        let parts = parse_shell_words(&editor_command)?;
        let Some((program, args)) = parts.split_first() else {
            bail!("editor command is empty");
        };
        let mut full_args = args.iter().map(String::as_str).collect::<Vec<_>>();
        full_args.push(&path_string);
        let code = run_local_inherit(program, &full_args)?;
        if code != 0 {
            bail!("editor exited with code {code}");
        }
        return Ok(());
    }

    if cfg!(target_os = "macos") {
        let result = run_local("open", &["-t", &path_string], None)?;
        if result.exit_code != 0 {
            bail!("{}", result.stderr.trim());
        }
        println!("opened {path_string}");
    } else {
        println!("{path_string}");
    }
    Ok(())
}

