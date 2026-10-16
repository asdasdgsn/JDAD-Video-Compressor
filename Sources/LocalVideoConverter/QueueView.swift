import SwiftUI
import AppKit
import ConverterCore
struct QueueView: View {
    @ObservedObject var queue: QueueStore
    @ObservedObject var model: AppModel
    @State private var log: String?
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text(model.t("任务与历史","QUEUE & HISTORY")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(queue.items.count)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if queue.running { Button(model.t("取消当前","Cancel current")) { queue.cancelCurrent() }.controlSize(.small) }
                else if queue.items.contains(where:{$0.status == .waiting}) { Button(model.t("继续队列","Resume queue")) { queue.start() }.controlSize(.small) }
                Button(model.t("清理记录","Clear history")) { queue.clearFinished() }.controlSize(.small)
            }.padding(16)
            if queue.items.isEmpty {
                VStack(spacing:10) { Image(systemName:"checklist").font(.system(size:28,weight:.light));Text(model.t("准备好，开始你的第一次转换","Ready for your first conversion")).font(.caption);Text(model.t("选择文件和设置，然后点击「开始处理」","Choose media and settings, then start processing")).font(.caption2) }.foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing:0) {
                        ForEach(queue.items.reversed()) { item in
                            HStack(alignment:.top,spacing:10) {
                                Image(systemName:icon(item.status)).foregroundStyle(color(item.status)).frame(width:22).padding(.top,4)
                                VStack(alignment:.leading,spacing:6) {
                                    HStack { Text(item.title).font(.system(size:12,weight:.medium)).lineLimit(1);Spacer();Text(status(item.status)).font(.caption2).foregroundStyle(color(item.status)) }
                                    if item.status == .running { ProgressView(value:item.progress).tint(Color.accentColor); HStack { Text("\(Int(item.progress*100))%"); if let start=item.started { Text(start,style:.relative) } }.font(.caption2).foregroundStyle(.secondary) }
                                    else { Text(item.output.lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                    if !item.error.isEmpty { Button { log=item.error } label:{ Text(item.error.components(separatedBy:"\n").last ?? item.error).font(.caption2).lineLimit(1).foregroundStyle(.orange) }.buttonStyle(.plain) }
                                }
                                if item.status == .completed {
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.output]) } label:{Image(systemName:"folder")}.buttonStyle(.plain).help(model.t("显示输出","Reveal output"))
                                } else if [.failed,.cancelled,.interrupted].contains(item.status) {
                                    Button {queue.retry(id:item.id)} label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.plain).help(model.t("重试","Retry"))
                                } else if item.status == .waiting {
                                    Button {queue.cancelWaiting(id:item.id)} label:{Image(systemName:"xmark")}.buttonStyle(.plain)
                                }
                            }.padding(.horizontal,18).padding(.vertical,12)
                            Divider().padding(.leading,50)
                        }
                    }
                }
            }
            if !queue.notice.isEmpty { Text(queue.notice).font(.caption2).foregroundStyle(.orange).padding(10).textSelection(.enabled) }
        }
        .sheet(isPresented:Binding(get:{log != nil},set:{if !$0 {log=nil}})) {
            VStack(alignment:.leading,spacing:14) { Text(model.t("任务诊断","Task diagnostic")).font(.headline);ScrollView { Text(log ?? "").font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) };Button(model.t("关闭","Close")){log=nil}.frame(maxWidth:.infinity,alignment:.trailing) }.padding(24).frame(width:650,height:400)
        }
    }
    func icon(_ s:QueueStatus)->String {switch s {case .waiting:return "clock";case .running:return "arrow.triangle.2.circlepath";case .completed:return "checkmark.circle.fill";case .failed:return "exclamationmark.circle.fill";case .cancelled:return "stop.circle";case .interrupted:return "pause.circle"}}
    func color(_ s:QueueStatus)->Color {switch s {case .completed:return .green;case .failed:return .orange;case .running:return .accentColor;default:return .secondary}}
    func status(_ s:QueueStatus)->String {switch s {case .waiting:return model.t("等待中","Waiting");case .running:return model.t("处理中","Processing");case .completed:return model.t("已完成","Completed");case .failed:return model.t("失败","Failed");case .cancelled:return model.t("已取消","Cancelled");case .interrupted:return model.t("已中断","Interrupted")}}
}
