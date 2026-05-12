use anyhow::{Result, bail};

use crate::config::{ConfigOverrides, load_config, resolve_agent_command};
use crate::config_command::run_config_command;
use crate::doctor::run_doctor;
use crate::remote_install::{InstallRemoteOptions, install_remote_helper};

pub fn run_setup_command() -> Result<()> {
    run_config_command(false, false)?;

    let config = load_config(ConfigOverrides::default())?;
    let agent_command = resolve_agent_command(&config, &config.default_agent);

    println!();
    println!("checking local and remote requirements");
    if !run_doctor(&config, &agent_command)? {
        bail!("setup checks failed");
    }

    println!();
    println!("installing remote helper");
    install_remote_helper(&config, &InstallRemoteOptions::default())?;

    println!();
    println!("setup complete");
    Ok(())
}
