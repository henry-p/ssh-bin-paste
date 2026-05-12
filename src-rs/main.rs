use anyhow::Result;
use clap::{Args, Parser, Subcommand};
use ssh_bin_paste::config::{ConfigOverrides, load_config, resolve_agent_command};
use ssh_bin_paste::config_command::run_config_command;
use ssh_bin_paste::daemon::run_daemon;
use ssh_bin_paste::doctor::run_doctor;
use ssh_bin_paste::panes::{list_panes, print_panes, select_and_save_pane};
use ssh_bin_paste::paste::paste_clipboard_image;
use ssh_bin_paste::remote_cache::{cleanup_remote_images, remote_cleanup_daemon};
use ssh_bin_paste::remote_install::{InstallRemoteOptions, install_remote_helper};
use ssh_bin_paste::start::start_managed_agent;

#[derive(Debug, Parser)]
#[command(version, about = "Paste local clipboard images into remote terminal agents over SSH.")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    Config(ConfigArgs),
    Doctor(DoctorArgs),
    InstallRemote(InstallRemoteArgs),
    Start(StartArgs),
    Panes(PanesArgs),
    Paste(PasteArgs),
    Cleanup(CleanupArgs),
    CleanupDaemon(CleanupDaemonArgs),
    Daemon(DaemonArgs),
}

#[derive(Debug, Args, Clone)]
struct RemoteArgs {
    #[arg(long, default_value = "example-vps", help = "SSH host alias")]
    host: String,
    #[arg(
        long,
        help = "Full SSH command, for example: ssh -i ~/.ssh/key user@host"
    )]
    ssh: Option<String>,
}

impl RemoteArgs {
    fn load_config(&self) -> Result<ssh_bin_paste::config::AppConfig> {
        load_config(ConfigOverrides {
            host: Some(self.host.clone()),
            ssh_command: self.ssh.clone(),
        })
    }
}

#[derive(Debug, Args)]
struct ConfigArgs {
    #[arg(long, help = "Print the config file path without opening it")]
    path: bool,
    #[arg(long, help = "Editor command to use")]
    editor: Option<String>,
}

#[derive(Debug, Args)]
struct DoctorArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long, default_value = "codex", help = "Agent profile or command")]
    agent: String,
}

#[derive(Debug, Args)]
struct InstallRemoteArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long = "no-cleanup-daemon", action = clap::ArgAction::SetFalse, default_value_t = true)]
    cleanup_daemon: bool,
    #[arg(long, default_value_t = 86_400)]
    cleanup_max_age_seconds: u64,
    #[arg(long, default_value_t = 300)]
    cleanup_interval_seconds: u64,
}

#[derive(Debug, Args)]
struct StartArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long, help = "Agent profile or command")]
    agent: String,
    #[arg(long, help = "Managed tmux session name")]
    session: Option<String>,
}

#[derive(Debug, Args)]
struct PanesArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long, help = "Interactively save the target pane")]
    select: bool,
    #[arg(long, help = "Save this target pane")]
    target: Option<String>,
}

#[derive(Debug, Args)]
struct PasteArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long, help = "tmux target pane id")]
    target: Option<String>,
}

#[derive(Debug, Args)]
struct CleanupArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long, default_value_t = 86_400, help = "Delete images older than this many seconds")]
    max_age_seconds: u64,
}

#[derive(Debug, Args)]
struct CleanupDaemonArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(help = "start, stop, or status")]
    action: String,
}

#[derive(Debug, Args)]
struct DaemonArgs {
    #[command(flatten)]
    remote: RemoteArgs,
    #[arg(long, help = "Intercept normal paste in allowlisted terminal apps")]
    hijack_paste: bool,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    match Cli::parse().command {
        Commands::Config(args) => run_config_command(args.path, args.editor.as_deref()),
        Commands::Doctor(args) => {
            let config = args.remote.load_config()?;
            let agent_command = resolve_agent_command(&config, &args.agent);
            let ok = run_doctor(&config, &agent_command)?;
            if !ok {
                std::process::exit(1);
            }
            Ok(())
        }
        Commands::InstallRemote(args) => {
            let config = args.remote.load_config()?;
            install_remote_helper(
                &config,
                &InstallRemoteOptions {
                    cleanup_daemon: Some(args.cleanup_daemon),
                    cleanup_max_age_seconds: Some(args.cleanup_max_age_seconds),
                    cleanup_interval_seconds: Some(args.cleanup_interval_seconds),
                },
            )
        }
        Commands::Start(args) => {
            let config = args.remote.load_config()?;
            start_managed_agent(&config, &args.agent, args.session.as_deref())
        }
        Commands::Panes(args) => {
            let config = args.remote.load_config()?;
            let panes = list_panes(&config)?;
            if let Some(target) = args.target.as_deref() {
                select_and_save_pane(&config, &panes, Some(target))?;
            } else if args.select {
                select_and_save_pane(&config, &panes, None)?;
            } else {
                print_panes(&panes);
            }
            Ok(())
        }
        Commands::Paste(args) => {
            let config = args.remote.load_config()?;
            paste_clipboard_image(&config, args.target.as_deref())
        }
        Commands::Cleanup(args) => {
            let config = args.remote.load_config()?;
            cleanup_remote_images(&config, args.max_age_seconds)
        }
        Commands::CleanupDaemon(args) => {
            let config = args.remote.load_config()?;
            remote_cleanup_daemon(&config, &args.action)
        }
        Commands::Daemon(args) => {
            let config = args.remote.load_config()?;
            run_daemon(&config, args.hijack_paste || config.daemon.hijack_paste)
        }
    }
}

