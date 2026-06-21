//! OpenCode agent 的 Tauri IPC 命令。
//!
//! 对应原 coding_agent 的命令，但调用 opencode CLI：
//! - `opencode_agent_detect`：检测 opencode 是否已安装
//! - `opencode_agent_run`：跑一轮（测试用，前端不直接调）
//! - `opencode_agent_cancel`：取消运行中的 agent
//! - `opencode_agent_command_risk`：查询某条命令的风险等级

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tauri::State;

use super::guard;
use super::{run_opencode_agent, OpenCodeAgentRequest};

/// 全局 cancel flag（同一时刻只跑一个 agent session）。
static AGENT_CANCEL: std::sync::OnceLock<Arc<AtomicBool>> = std::sync::OnceLock::new();

fn agent_cancel() -> &'static Arc<AtomicBool> {
    AGENT_CANCEL.get_or_init(|| Arc::new(AtomicBool::new(false)))
}

/// 检测 opencode CLI 是否已安装并可用。
#[tauri::command]
pub async fn opencode_agent_detect() -> Result<bool, String> {
    let result = tokio::process::Command::new("opencode")
        .arg("--version")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
        .await;
    match result {
        Ok(output) => Ok(output.status.success()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.to_string()),
    }
}

/// 跑一轮 opencode agent（测试 / 调试用。生产路径走 coordinator 的语音流水线）。
#[tauri::command]
pub async fn opencode_agent_run(
    prompt: String,
    cwd: Option<String>,
    model: Option<String>,
    permission_mode: Option<String>,
) -> Result<String, String> {
    let cancel = Arc::clone(agent_cancel());
    cancel.store(false, Ordering::SeqCst);

    let mode = match permission_mode.as_deref() {
        Some("plan") => super::OpenCodeAgentPermissionMode::Plan,
        Some("default") => super::OpenCodeAgentPermissionMode::Default,
        Some("bypassPermissions") => super::OpenCodeAgentPermissionMode::BypassPermissions,
        _ => super::OpenCodeAgentPermissionMode::AcceptEdits,
    };

    let mut req = OpenCodeAgentRequest::new("manual", prompt);
    req.cwd = cwd.map(std::path::PathBuf::from);
    req.model = model;
    req.permission_mode = mode;

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let run_handle = tokio::spawn(async move {
        run_opencode_agent("opencode", req, tx, cancel).await
    });

    let mut final_text = String::new();
    while let Some(ev) = rx.recv().await {
        use super::OpenCodeAgentEvent as E;
        match ev {
            E::Completed { text, .. } => final_text = text,
            E::Error { message } => return Err(message),
            E::Cancelled => return Err("agent cancelled".to_string()),
            _ => {}
        }
    }

    match run_handle.await {
        Ok(Ok(())) => Ok(final_text),
        Ok(Err(e)) => Err(e.to_string()),
        Err(e) => Err(format!("agent task panicked: {e}")),
    }
}

/// 取消运行中的 opencode agent。
#[tauri::command]
pub fn opencode_agent_cancel() -> Result<(), String> {
    agent_cancel().store(true, Ordering::SeqCst);
    Ok(())
}

/// 查询某条命令的风险等级（供前端在审批卡里展示）。
#[tauri::command]
pub fn opencode_agent_command_risk(command: String) -> Result<guard::CommandRisk, String> {
    Ok(guard::classify_command(&command))
}
