import Foundation

enum Demo {
    static var session: Session {
        let text = """
        # 待办 App 开发方案

        ## 1. 产品目标
        为个人用户提供一个轻量的待办工具，帮助用户快速记录任务、安排今天的工作，并回顾完成情况。

        ## 2. 核心功能
        - 快速添加任务，支持标题、备注和截止日期。
        - 通过 **今天、计划、已完成** 三个视图管理任务。
        - 支持项目分组与标签，每个任务可关联多个标签。
        - 到期时发送提醒，默认每天上午 9 点汇总通知。
        - 支持拖拽排序，已完成任务在 30 天后自动删除。

        ## 3. 技术选型
        - 客户端使用 SwiftUI，优先支持 macOS 14 及以上版本。
        - 本地数据使用 SwiftData，任务模型为 `TaskItem`。
        - 第一版接入 CloudKit，实现多设备实时同步。
        - 使用 UserNotifications 实现本地提醒。

        ## 4. 交互设计
        主界面采用侧边栏与任务列表两栏布局。通过快捷键 `⌘N` 创建任务，按回车保存；点击任务可展开备注和日期设置。

        ## 5. 开发计划
        - 第一周：数据模型、任务增删改查和基础界面。
        - 第二周：项目分组、标签、提醒与云同步。
        - 第三周：键盘操作、无障碍适配与测试发布。

        ## 6. 验收标准
        创建任务后立即出现在列表中；重启应用后数据保留；离线状态可以继续编辑，联网后自动同步。
        """
        let pairs = [
            ("已完成任务在 30 天后自动删除", "不要自动删除。默认保留已完成任务，提供手动归档和清理入口。"),
            ("第一版接入 CloudKit，实现多设备实时同步。", "第一版先完成本地闭环，云同步放到下一版。\n请补充本地数据备份与恢复方案。"),
            ("第二周：项目分组、标签、提醒与云同步。", "减少第二周的范围，优先完成提醒和键盘操作。标签可以后置。")
        ]
        let comments = pairs.map { quote, body in
            let range = (text as NSString).range(of: quote)
            return Comment(location: range.location, length: range.length, quote: quote, body: body)
        }
        return Session(text: text, comments: comments, general: "请按单人两周可交付的范围重新规划，明确第一版边界与验收步骤。")
    }
}
