import Foundation

/// Labels for the menus, alerts and the play room; what the characters say lives in the Dialogue files.
enum UIText {
    case characters, playRoom, agentCharacters, chooseAgents
    case hideAll, showAll
    case agentIdle, agentWorking, agentDone, agentNeedsYou
    case hookInstalled, installHook
    case finderBlocked, openAutomation, sortByLocked, turnOffSortBy, quit
    case showRoom, scenery, inRoom, editRoom, done, roomHint, politics
    case sceneCozy, sceneKimetsu, sceneOnePiece, sceneAttackOnTitan, sceneJujutsuKaisen, sceneHunterXHunter, sceneUnitedNations
    /// "%@" is the path of Claude Code's settings file.
    case hookQuestion, hookExplain, install, cancel, hookDone, hookDoneInfo, hookFailed
    /// "%@" is the permission error code.
    case finderNotAllowed
    /// "%@" is a version number (the current one, or the one available).
    case checkUpdates, upToDate, updateAvailable
    case checkingUpdates, installingUpdate, updateFailed
    /// "%@" is the folder the app is in.
    case updateNoPermission
}

/// `key` in the current language, falling back to Vietnamese; "%@" becomes `argument`.
func ui(_ key: UIText, _ argument: String = "") -> String {
    let text = uiTexts[Language.current]?[key] ?? uiTexts[.vi]?[key] ?? ""
    return text.replacingOccurrences(of: "%@", with: argument)
}

private let uiTexts: [Language: [UIText: String]] = [
    .vi: [
        .hideAll: "Ẩn tất cả",
        .showAll: "Hiện tất cả",
        .characters: "Nhân vật",
        .playRoom: "Phòng chơi",
        .agentCharacters: "Nhân vật cho AI agent",
        .chooseAgents: "Chọn agent",
        .agentIdle: "rảnh",
        .agentWorking: "đang làm",
        .agentDone: "xong, chờ bạn",
        .agentNeedsYou: "cần bạn duyệt",
        .hookInstalled: "✓ Đã cài hook trạng thái cho Claude Code",
        .installHook: "Cài hook trạng thái cho Claude Code…",
        .finderBlocked: "⚠️ Chưa điều khiển được Finder",
        .openAutomation: "Mở cài đặt quyền Automation…",
        .sortByLocked: "⚠️ Desktop đang bật Sort By — icon bị khoá",
        .turnOffSortBy: "Tắt Sort By trên Desktop",
        .quit: "Thoát OllieBoard",
        .showRoom: "Hiện phòng chơi",
        .scenery: "Phong cảnh",
        .inRoom: "Ở trong phòng:",
        .editRoom: "Chỉnh vị trí và kích thước phòng",
        .done: "Xong",
        .roomHint: "Kéo để di chuyển · kéo góc ↘ để đổi kích thước",
        .politics: "Chính trị",
        .sceneCozy: "Phòng ấm cúng (mặc định)",
        .sceneKimetsu: "Kimetsu no Yaiba — Đêm hoa tử đằng",
        .sceneOnePiece: "One Piece — Boong tàu Thousand Sunny",
        .sceneAttackOnTitan: "Attack on Titan — Tường Maria",
        .sceneJujutsuKaisen: "Jujutsu Kaisen — Trường Chú thuật Tokyo",
        .sceneHunterXHunter: "Hunter x Hunter — Đảo Cá Voi",
        .sceneUnitedNations: "Chính trị — Phòng họp Liên Hợp Quốc",
        .hookQuestion: "Cài hook trạng thái cho Claude Code?",
        .hookExplain: """
        OllieBoard sẽ thêm hook vào %@ để biết chính xác khi nào Claude Code đang làm, \
        đã xong hay cần bạn duyệt. Các hook hiện có được giữ nguyên; bản cũ được sao lưu thành settings.json.ollieboard-backup.
        """,
        .install: "Cài đặt",
        .cancel: "Huỷ",
        .hookDone: "Đã cài hook",
        .hookDoneInfo: "Áp dụng cho các phiên Claude Code mở từ bây giờ (phiên đang chạy cần khởi động lại).",
        .hookFailed: "Không cài được hook",
        .finderNotAllowed: "OllieBoard chưa được phép điều khiển Finder (%@).",
        .checkUpdates: "Kiểm tra cập nhật (đang dùng bản %@)",
        .upToDate: "✓ Đã là bản mới nhất (%@)",
        .updateAvailable: "⬆️ Cập nhật lên bản %@",
        .checkingUpdates: "Đang kiểm tra cập nhật…",
        .installingUpdate: "Đang tải và cài bản cập nhật…",
        .updateFailed: "Không cập nhật được",
        .updateNoPermission: "OllieBoard không có quyền ghi vào %@. Hãy tải bản mới từ trang Releases và cài thủ công.",
    ],
    .en: [
        .hideAll: "Hide all",
        .showAll: "Show all",
        .characters: "Characters",
        .playRoom: "Play room",
        .agentCharacters: "Characters for AI agents",
        .chooseAgents: "Choose agents",
        .agentIdle: "idle",
        .agentWorking: "working",
        .agentDone: "done, waiting for you",
        .agentNeedsYou: "needs your approval",
        .hookInstalled: "✓ Claude Code status hook installed",
        .installHook: "Install the Claude Code status hook…",
        .finderBlocked: "⚠️ Can't control Finder",
        .openAutomation: "Open Automation settings…",
        .sortByLocked: "⚠️ Desktop Sort By is on — icons are locked",
        .turnOffSortBy: "Turn off Sort By on the Desktop",
        .quit: "Quit OllieBoard",
        .showRoom: "Show the play room",
        .scenery: "Scenery",
        .inRoom: "In the room:",
        .editRoom: "Move and resize the room",
        .done: "Done",
        .roomHint: "Drag to move · drag the ↘ corner to resize",
        .politics: "Politics",
        .sceneCozy: "Cozy room (default)",
        .sceneKimetsu: "Kimetsu no Yaiba — Wisteria night",
        .sceneOnePiece: "One Piece — Thousand Sunny deck",
        .sceneAttackOnTitan: "Attack on Titan — Wall Maria",
        .sceneJujutsuKaisen: "Jujutsu Kaisen — Tokyo Jujutsu High",
        .sceneHunterXHunter: "Hunter x Hunter — Whale Island",
        .sceneUnitedNations: "Politics — UN General Assembly hall",
        .hookQuestion: "Install the Claude Code status hook?",
        .hookExplain: """
        OllieBoard will add hooks to %@ so it knows exactly when Claude Code is working, \
        done or waiting for your approval. Your existing hooks are kept; the old file is backed up as settings.json.ollieboard-backup.
        """,
        .install: "Install",
        .cancel: "Cancel",
        .hookDone: "Hook installed",
        .hookDoneInfo: "It applies to Claude Code sessions started from now on (running sessions need a restart).",
        .hookFailed: "Couldn't install the hook",
        .finderNotAllowed: "OllieBoard isn't allowed to control Finder (%@).",
        .checkUpdates: "Check for updates (using %@)",
        .upToDate: "✓ Up to date (%@)",
        .updateAvailable: "⬆️ Update to %@",
        .checkingUpdates: "Checking for updates…",
        .installingUpdate: "Downloading and installing the update…",
        .updateFailed: "Couldn't update",
        .updateNoPermission: "OllieBoard can't write to %@. Download the new version from the Releases page and install it by hand.",
    ],
    .ja: [
        .hideAll: "すべて隠す",
        .showAll: "すべて表示",
        .characters: "キャラクター",
        .playRoom: "プレイルーム",
        .agentCharacters: "AIエージェントのキャラクター",
        .chooseAgents: "エージェントを選ぶ",
        .agentIdle: "待機中",
        .agentWorking: "作業中",
        .agentDone: "完了・あなたを待っています",
        .agentNeedsYou: "承認が必要です",
        .hookInstalled: "✓ Claude Code の状態フックをインストール済み",
        .installHook: "Claude Code の状態フックをインストール…",
        .finderBlocked: "⚠️ Finder を操作できません",
        .openAutomation: "オートメーションの設定を開く…",
        .sortByLocked: "⚠️ デスクトップの「並べ替え」がオン — アイコンが固定されています",
        .turnOffSortBy: "デスクトップの「並べ替え」をオフにする",
        .quit: "OllieBoard を終了",
        .showRoom: "プレイルームを表示",
        .scenery: "背景",
        .inRoom: "部屋にいるキャラ:",
        .editRoom: "部屋の位置とサイズを変更",
        .done: "完了",
        .roomHint: "ドラッグで移動 · ↘ の角をドラッグでサイズ変更",
        .politics: "政治",
        .sceneCozy: "くつろぎの部屋（デフォルト）",
        .sceneKimetsu: "鬼滅の刃 — 藤の花の夜",
        .sceneOnePiece: "ONE PIECE — サウザンド・サニー号の甲板",
        .sceneAttackOnTitan: "進撃の巨人 — ウォール・マリア",
        .sceneJujutsuKaisen: "呪術廻戦 — 東京都立呪術高専",
        .sceneHunterXHunter: "HUNTER×HUNTER — くじら島",
        .sceneUnitedNations: "政治 — 国連総会議場",
        .hookQuestion: "Claude Code の状態フックをインストールしますか？",
        .hookExplain: """
        OllieBoard は %@ にフックを追加し、Claude Code が作業中か、完了したか、承認待ちかを正確に把握します。\
        既存のフックはそのまま残り、元のファイルは settings.json.ollieboard-backup としてバックアップされます。
        """,
        .install: "インストール",
        .cancel: "キャンセル",
        .hookDone: "フックをインストールしました",
        .hookDoneInfo: "これから開始する Claude Code のセッションに適用されます（実行中のセッションは再起動が必要です）。",
        .hookFailed: "フックをインストールできませんでした",
        .finderNotAllowed: "OllieBoard には Finder を操作する権限がありません（%@）。",
        .checkUpdates: "アップデートを確認（現在 %@）",
        .upToDate: "✓ 最新バージョンです（%@）",
        .updateAvailable: "⬆️ %@ にアップデート",
        .checkingUpdates: "アップデートを確認中…",
        .installingUpdate: "アップデートをダウンロードしてインストール中…",
        .updateFailed: "アップデートできませんでした",
        .updateNoPermission: "OllieBoard は %@ に書き込めません。Releases ページから新しいバージョンをダウンロードして手動でインストールしてください。",
    ],
]
