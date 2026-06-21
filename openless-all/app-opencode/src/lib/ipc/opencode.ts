import { invokeOrMock } from "./shared"

/** 用户点 ✕ / 按 Esc 关闭 OpenCode 浮窗（隐藏窗口）。 */
export function opencodeWindowDismiss(): Promise<void> {
    return invokeOrMock("opencode_window_dismiss", undefined, () => undefined)
}

/** 内联审批卡的 Approve / Deny 回执。token 关联到等待中的拦截动作。 */
export function opencodeApprove(
    token: string,
    approved: boolean,
): Promise<void> {
    return invokeOrMock(
        "opencode_approve",
        { token, approved },
        () => undefined,
    )
}

/** 前端按内容测高后回传，后端 clamp + bottom-anchored 重新摆放浮窗。 */
export function opencodeWindowResize(height: number): Promise<void> {
    return invokeOrMock(
        "opencode_window_resize",
        { height },
        () => undefined,
    )
}
