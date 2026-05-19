import SwiftUI

struct VimCheatsheetView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Movement") {
                    row("h j k l", "left / down / up / right (visual lines)")
                    row("w / b", "start of next / previous word")
                    row("e / ge", "end of current / previous word")
                    row("W B E", "WORD variants (whitespace-only separators)")
                    row("0 / ^", "line start / first non-blank")
                    row("$", "line end")
                    row("{ / }", "previous / next paragraph (blank line)")
                    row("%", "matching ( ) [ ] { } bracket")
                    row("gg / G", "top / bottom of buffer")
                    row("arrows", "same as h j k l")
                    row("Nx", "count prefix repeats: 5w, 3l, 2dd…")
                }
                section("Insert mode") {
                    row("i / a", "insert before / after cursor")
                    row("I / A", "insert at line start / line end")
                    row("o / O", "open new line below / above")
                    row("Esc", "back to normal mode")
                }
                section("Delete") {
                    row("x", "delete character")
                    row("dd", "delete line (Ndd for N lines)")
                    row("dw / de", "delete word / through end of word")
                    row("db / d0 / d$", "delete back / to line start / end")
                    row("D", "delete to end of line")
                }
                section("Change") {
                    row("cc", "empty line, enter insert")
                    row("cw / ce", "change word (delete + insert)")
                    row("c0 / c$ / c^", "change to line start / end / first non-blank")
                    row("C", "change to end of line")
                    row("s", "substitute char (delete + insert)")
                }
                section("Replace") {
                    row("r<x>", "replace one character with x")
                    row("Nr<x>", "replace N characters with x")
                    row("R", "overstrike mode — overwrite until Esc")
                }
                section("Visual selection") {
                    row("v", "char-wise visual mode")
                    row("V", "line-wise visual mode")
                    row("Esc", "exit visual mode")
                    row("d / x", "delete selection")
                    row("y", "yank selection")
                    row("c", "change selection (delete + insert)")
                }
                section("Search") {
                    row("/<term>", "search forward (Enter to commit)")
                    row("n / N", "next / previous match")
                    row("Esc", "cancel search input")
                }
                section("Find in line") {
                    row("f<x>", "next occurrence of x on this line")
                    row("F<x>", "previous occurrence of x")
                    row("t<x>", "next x, land just before it")
                    row("T<x>", "previous x, land just after it")
                    row("; / ,", "repeat last find / reverse")
                }
                section("Repeat") {
                    row(".", "repeat last text-changing command")
                }
                section("Other") {
                    row("~", "toggle case of character under cursor")
                }
                section("Yank & paste") {
                    row("yy", "yank current line (Nyy for N lines)")
                    row("yw / ye", "yank word")
                    row("p / P", "paste after / before")
                    row("Np", "paste N times")
                }
                section("Undo / redo") {
                    row("u", "undo")
                    row("Ctrl-r", "redo")
                }
                section("Command line") {
                    row(":q  /  :vim", "exit vim mode")
                    row(":w", "save entry (stay in vim)")
                    row(":wq", "save + exit vim")
                    row("Esc", "cancel command line")
                }
                section("Exit vim") {
                    row("Click VIM pill", "exit and return to normal editing")
                    row("Type /vim again", "toggle off (insert mode only)")
                }
            }
            .padding(14)
        }
        .frame(width: 340, height: 420)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ cmd: String, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(cmd)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
