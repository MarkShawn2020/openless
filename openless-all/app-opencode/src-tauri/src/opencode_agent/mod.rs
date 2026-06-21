//! OpenCode Agent 后端模块。
//!
//! 用 `opencode` CLI（开源 AI 编码 agent）替代原来的 `claude` CLI，提供：
//! - 无头非交互模式（`opencode run` / `opencode -p`）
//! - 流式 stdout 解析（Delta / ToolUse / Completed / Error / Cancelled）
//! - 护栏（deny 高风险命令模式）
//! - git 快照（运行前 stash，便于回滚）
//!
//! 模块结构：
//! - `mod.rs`：核心类型 + CLI 调用 + git 快照
//! - `commands.rs`：Tauri IPC 命令（detect / run / cancel / command_risk）
//! - `guard.rs`：护栏规则（deny 清单 + 高风险模式 + 等价组）
//! - `stream.rs`：opencode stdout 流式解析

pub mod commands;
pub mod guard;
pub mod stream;

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;

/// OpenCode 权限模式（对应 opencode CLI 的 `--mode` 参数）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpenCodeAgentPermissionMode {
    /// 计划模式：只读，不执行任何写操作。
    Plan,
    /// 默认模式：每个写操作都要确认（headless 下等同于 deny）。
    Default,
    /// 接受所有编辑：自动放行文件写操作，但保留护栏 deny。
    AcceptEdits,
    /// 绕过所有权限（语音路径禁止，自动降级为 AcceptEdits）。
    BypassPermissions,
}

impl OpenCodeAgentPermissionMode {
    /// 返回 opencode CLI 的 `--mode` 参数值。
    pub fn as_cli_arg(self) -> &'static str {
        match self {
            Self::Plan => "plan",
            Self::Default => "default",
            Self::AcceptEdits => "acceptEdits",
            Self::BypassPermissions => "bypassPermissions",
        }
    }
}

/// OpenCode agent 运行时事件（流式输出解析后投递到 channel）。
#[derive(Debug, Clone)]
pub enum OpenCodeAgentEvent {
    /// agent 已启动（进程 spawn 成功）。
    Started { session_id: String },
    /// 文本增量（assistant 回复的流式片段）。
    Delta { text: String },
    /// 工具调用（Bash / Read / Edit / Write / Glob / Grep / WebSearch）。
    ToolUse { name: String },
    /// 整轮完成，携带最终文本和（可选）成本。
    Completed { text: String, cost_usd: Option<f64> },
    /// 运行出错（CLI 退出码非 0 / 解析失败 / 超时）。
    Error { message: String },
    /// 被取消（cancel flag 触发 / 进程被 kill）。
    Cancelled,
}

/// OpenCode agent 错误。
#[derive(Debug)]
pub enum OpenCodeAgentError {
    /// CLI 二进制找不到（未安装 / 不在 PATH）。
    BinaryNotFound,
    /// 进程 spawn 失败。
    SpawnFailed(String),
    /// 运行被取消。
    Cancelled,
    /// 其它错误（超时 / IO / 解析）。
    Other(String),
}

impl std::fmt::Display for OpenCodeAgentError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::BinaryNotFound => write!(f, "opencode CLI 未找到（确认已安装并加入 PATH）"),
            Self::SpawnFailed(msg) => write!(f, "opencode 进程启动失败: {msg}"),
            Self::Cancelled => write!(f, "opencode 运行已取消"),
            Self::Other(msg) => write!(f, "opencode 运行出错: {msg}"),
        }
    }
}

impl std::error::Error for OpenCodeAgentError {}

/// 一轮 OpenCode agent 请求。
#[derive(Debug, Clone)]
pub struct OpenCodeAgentRequest {
    /// 会话标签（日志/快照命名用，不传给 CLI）。
    pub label: String,
    /// 用户指令（语音转写后的文本）。
    pub prompt: String,
    /// 工作目录（None = 当前目录）。
    pub cwd: Option<std::path::PathBuf>,
    /// 模型名（None = opencode 默认）。
    pub model: Option<String>,
    /// 权限模式。
    pub permission_mode: OpenCodeAgentPermissionMode,
    /// 护栏配置文件路径（JSON，传给 `--settings`）。
    pub settings_json_path: Option<std::path::PathBuf>,
    /// 允许的工具列表（`Bash` / `Read` / `Edit` / ...）。
    pub allowed_tools: Vec<String>,
    /// 预算上限（美元）。
    pub max_budget_usd: Option<f64>,
    /// 超时（秒）。
    pub timeout_secs: u64,
    /// 是否持久化会话（保存供下轮 `--continue`）。
    pub session_persistence: bool,
    /// 本轮是否续接上一轮会话（`--continue`）。
    pub continue_session: bool,
}

impl OpenCodeAgentRequest {
    pub fn new(label: impl Into<String>, prompt: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            prompt: prompt.into(),
            cwd: None,
            model: None,
            permission_mode: OpenCodeAgentPermissionMode::AcceptEdits,
            settings_json_path: None,
            allowed_tools: Vec::new(),
            max_budget_usd: None,
            timeout_secs: 300,
            session_persistence: false,
            continue_session: false,
        }
    }
}

/// 构造语音 agent 的自主指令 prompt（让 opencode 直接执行用户语音指令，不问确认）。
pub fn autonomous_prompt(user_instruction: &str) -> String {
    format!(
        "你是一个语音驱动的电脑控制 agent。用户通过语音下达指令，你直接执行，不要询问确认。\n\
         执行完毕后，用一句话总结你做了什么。如果指令不明确，按最合理的解释执行。\n\n\
         用户指令：{user_instruction}"
    )
}

/// 在 cwd 跑一次 git stash create，返回 stash 的 SHA（可用于 `git stash apply` 回滚）。
/// cwd 不是 git 仓库时返回 None（无副作用）。
pub fn create_git_snapshot(cwd: &Path) -> Option<String> {
    let output = std::process::Command::new("git")
        .arg("stash")
        .arg("create")
        .current_dir(cwd)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let sha = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if sha.is_empty() {
        None
    } else {
        Some(sha)
    }
}

/// 跑一轮 opencode agent，把事件流式投递到 `tx`，直到进程结束。
///
/// `binary` 通常是 `"opencode"`；`cancel` 为 true 时尽快终止进程。
pub async fn run_opencode_agent(
    binary: &str,
    req: OpenCodeAgentRequest,
    tx: mpsc::UnboundedSender<OpenCodeAgentEvent>,
    cancel: Arc<AtomicBool>,
) -> Result<(), OpenCodeAgentError> {
    use stream::parse_opencode_line;

    // 构造命令行。opencode 的非交互模式：`opencode run <prompt>`，配合 `--format json` 流式输出。
    //
    // 注意：opencode CLI 的 flags 与 claude CLI 不同：
    // - 输出格式用 `--format json`（不是 `--json`）。
    // - 没有 `--mode` / `--settings` / `--tools` flags；权限模式、deny 清单、工具白名单
    //   通过 `OPENCODE_CONFIG` 环境变量指向一个临时 opencode.json 配置文件
    //   （见 `dictation.rs::run_opencode_once`，它生成配置并设置 `req.settings_json_path`）。
    // - `--model` 格式为 `provider/model`（如 `anthropic/claude-sonnet-4`）。
    // - `--continue` 续接上一个会话。
    // - `--dir` 指定工作目录（等价于 `current_dir`，这里用 `current_dir` 更直接）。
    let mut cmd = Command::new(binary);
    cmd.arg("run")
        .arg("--format")
        .arg("json")
        .arg(&req.prompt)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .kill_on_drop(true);

    if let Some(cwd) = &req.cwd {
        cmd.current_dir(cwd);
    }
    if let Some(model) = &req.model {
        cmd.arg("--model").arg(model);
    }
    if req.continue_session {
        cmd.arg("--continue");
    }
    // 权限配置：通过 OPENCODE_CONFIG 环境变量传给 opencode 子进程。
    // opencode 会加载这个配置文件，覆盖项目根目录的 opencode.json。
    if let Some(config_path) = &req.settings_json_path {
        cmd.env("OPENCODE_CONFIG", config_path);
    }

    let session_id = uuid::Uuid::new_v4().to_string();
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Err(OpenCodeAgentError::BinaryNotFound);
        }
        Err(e) => return Err(OpenCodeAgentError::SpawnFailed(e.to_string())),
    };

    let _ = tx.send(OpenCodeAgentEvent::Started {
        session_id: session_id.clone(),
    });

    let stdout = child.stdout.take().ok_or_else(|| {
        OpenCodeAgentError::Other("无法读取 opencode stdout".to_string())
    })?;
    let stderr = child.stderr.take();

    let cancel_for_reader = Arc::clone(&cancel);
    let tx_for_reader = tx.clone();
    let reader_handle = tokio::spawn(async move {
        let reader = BufReader::new(stdout);
        let mut lines = reader.lines();
        let mut final_text = String::new();
        let mut cost_usd: Option<f64> = None;

        while let Ok(Some(line)) = lines.next_line().await {
            if cancel_for_reader.load(Ordering::Relaxed) {
                let _ = tx_for_reader.send(OpenCodeAgentEvent::Cancelled);
                return (final_text, cost_usd, true);
            }
            if line.trim().is_empty() {
                continue;
            }
            match parse_opencode_line(&line) {
                Some(stream::OpenCodeStreamEvent::Delta { text }) => {
                    final_text.push_str(&text);
                    let _ = tx_for_reader.send(OpenCodeAgentEvent::Delta { text });
                }
                Some(stream::OpenCodeStreamEvent::ToolUse { name }) => {
                    let _ = tx_for_reader.send(OpenCodeAgentEvent::ToolUse { name });
                }
                Some(stream::OpenCodeStreamEvent::StepFinish { cost }) => {
                    // 累加每步成本（多步会多次触发）。
                    if let Some(c) = cost {
                        cost_usd = Some(cost_usd.map_or(c, |prev| prev + c));
                    }
                }
                Some(stream::OpenCodeStreamEvent::Completed { text, cost }) => {
                    // session.idle：整轮完成。text/cost 在 stream.rs 里为空，
                    // 用我们累积的 final_text 和 cost_usd。
                    if !text.is_empty() {
                        final_text = text;
                    }
                    if let Some(c) = cost {
                        cost_usd = Some(c);
                    }
                }
                Some(stream::OpenCodeStreamEvent::Error { message }) => {
                    let _ = tx_for_reader.send(OpenCodeAgentEvent::Error { message });
                }
                None => {
                    // 无法解析的行：忽略（opencode 可能输出非 JSON 的日志行）。
                    log::debug!("[opencode] 未解析的行: {line}");
                }
            }
        }
        (final_text, cost_usd, false)
    });

    // stderr 读取（仅日志，不投递事件）。
    if let Some(stderr) = stderr {
        let _ = tokio::spawn(async move {
            let reader = BufReader::new(stderr);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                log::debug!("[opencode:stderr] {line}");
            }
        });
    }

    // 等待进程结束，同时检查 cancel flag。
    let timeout = std::time::Duration::from_secs(req.timeout_secs);
    let wait_fut = async {
        loop {
            if cancel.load(Ordering::Relaxed) {
                let _ = child.kill().await;
                return Ok(());
            }
            match tokio::time::timeout(std::time::Duration::from_millis(200), child.wait()).await {
                Ok(Ok(_status)) => return Ok(()),
                Ok(Err(e)) => return Err(e),
                Err(_) => continue, // timeout on wait, loop and recheck cancel
            }
        }
    };
    let _ = tokio::time::timeout(timeout, wait_fut).await;

    // 超时或 cancel：确保进程被 kill。
    let _ = child.kill().await;

    let (final_text, cost_usd, was_cancelled) = reader_handle.await.unwrap_or_default();

    if was_cancelled || cancel.load(Ordering::Relaxed) {
        let _ = tx.send(OpenCodeAgentEvent::Cancelled);
        return Err(OpenCodeAgentError::Cancelled);
    }

    let _ = tx.send(OpenCodeAgentEvent::Completed {
        text: final_text,
        cost_usd,
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permission_mode_cli_arg() {
        assert_eq!(OpenCodeAgentPermissionMode::Plan.as_cli_arg(), "plan");
        assert_eq!(
            OpenCodeAgentPermissionMode::AcceptEdits.as_cli_arg(),
            "acceptEdits"
        );
        assert_eq!(
            OpenCodeAgentPermissionMode::BypassPermissions.as_cli_arg(),
            "bypassPermissions"
        );
    }

    #[test]
    fn autonomous_prompt_includes_instruction() {
        let p = autonomous_prompt("打开浏览器");
        assert!(p.contains("打开浏览器"));
        assert!(p.contains("语音"));
    }

    #[test]
    fn request_new_defaults() {
        let req = OpenCodeAgentRequest::new("test", "hello");
        assert_eq!(req.label, "test");
        assert_eq!(req.prompt, "hello");
        assert_eq!(req.timeout_secs, 300);
        assert!(!req.continue_session);
        assert_eq!(
            req.permission_mode,
            OpenCodeAgentPermissionMode::AcceptEdits
        );
    }
}
