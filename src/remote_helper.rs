use anyhow::Result;

use crate::config::AppConfig;
use crate::ssh::{CommandResult, remote_path_expr, run_ssh, shell_quote};

pub fn run_remote_helper(
    config: &AppConfig,
    args: &[String],
    input: Option<&[u8]>,
) -> Result<CommandResult> {
    let command = std::iter::once(remote_path_expr(&config.remote_helper_path))
        .chain(args.iter().map(|arg| shell_quote(arg)))
        .collect::<Vec<_>>()
        .join(" ");
    run_ssh(config, &command, input)
}

