"""Decompile a Peter program tree into readable pseudocode.

Usage: uv run --no-project python decompile.py ../stress_relief.exe > ../re/program.txt
"""

import re
import sys

from petprg import B, LANG_EN, Node, Program

VAR_TYPES = {
    "real", "logic", "sprite", "sound", "background", "picture", "map", "text",
    "sprite_x", "sprite_y", "sprite_dir", "sprite_vis", "sprite_move", "sprite_phase", "sprite_status",
    "list_index", "list_auto",
}
BINOPS = {"+", "-", "*", "/", "<", ">", "<=", ">=", "=", "<>", "and", "or", "mod", "bit_and"}
LITERALS = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-1", "true", "false"}


class Decompiler:
    def __init__(self, prog: Program):
        self.p = prog
        self.out: list[str] = []
        self.local_owner: dict[int, Node] = {}
        for g in prog.nodes[B["GLOBAL"]]:
            if prog.base_func(g) == "function" and g.dat_block == B["LOCAL"]:
                self.local_owner[g.dat_index] = g

    def name(self, n: Node) -> str:
        return self.p.label(n, LANG_EN)

    def var(self, n: Node) -> str:
        r = self.p.ref(n)
        tgt = r if isinstance(r, Node) else n
        scope = {B["GLOBAL"]: "G", B["LOCAL"]: "L"}.get(tgt.block, "?")
        return f"{self.name(tgt)!s}@{scope}{tgt.index}"

    def comment(self, n: Node) -> str:
        return f"  # {self.p.text(n.name)}" if n.name >= 0 else ""

    def expr(self, n: Node) -> str:
        f = self.p.base_func(n)
        kids = n.children
        r = self.p.ref(n)
        if f == "num":
            raw = self.p.text(n.name, LANG_EN).strip()
            m = re.match(r"^(\$?[-0-9a-fA-F.]+)\s*(.*)$", raw)
            if not m:
                return raw
            val, note = m.groups()
            if val.startswith("$"):
                val = "0x" + val[1:]
            return f"{val} /*{note}*/" if note else val
        if f == "text_const":
            return repr(self.p.text(n.name))
        if f in LITERALS and not kids:
            return f
        if isinstance(r, Node) and r.block in (B["GLOBAL"], B["LOCAL"]):
            if f == "function":
                return f"{self.var(n)}({self.call_args(kids)})"
            return self.var(n)
        if f in BINOPS:
            if len(kids) == 1:
                return f"{f}{self.expr(kids[0])}"
            return "(" + f" {f} ".join(self.expr(c) for c in kids) + ")"
        if not kids:
            return f
        return f"{f}(" + ", ".join(self.arg(f, c) for c in kids) + ")"

    def call_args(self, kids: list) -> str:
        out = []
        for k in kids:
            if k.children:
                out.append(f"{self.var(k)}={self.expr(k.children[0])}")
            else:
                out.append(self.expr(k))
        return ", ".join(out)

    def is_param(self, parent: str, f: str) -> bool:
        return f.startswith(parent + "_") or f in ("graph_color", "graph_width") or (
            parent.startswith("background") and f.startswith("background_"))

    def arg(self, parent: str, c: Node) -> str:
        f = self.p.base_func(c)
        if isinstance(self.p.ref(c), str) and self.is_param(parent, f):
            return f"{f}={self.expr(c.children[0])}" if c.children else f"{f}=<default>"
        return self.expr(c)

    def body(self, n: Node, d: int):
        for k in n.children:
            if self.p.base_func(k) == "while_body":
                for s in k.children:
                    self.stmt(s, d)
            else:
                self.stmt(k, d)

    def emit(self, depth: int, s: str):
        self.out.append("    " * depth + s)

    def stmt(self, n: Node, d: int):
        f = self.p.base_func(n)
        r = self.p.ref(n)
        kids = n.children
        c = self.comment(n)
        if f == "group":
            self.emit(d, f"# --- {self.p.text(n.name) or 'group'} ---")
            for k in kids:
                self.stmt(k, d)
            return
        if f == "if":
            cond = next((k for k in kids if self.p.base_func(k) == "if_cond"), None)
            then = next((k for k in kids if self.p.base_func(k) == "then"), None)
            els = next((k for k in kids if self.p.base_func(k) == "else"), None)
            self.emit(d, f"if {self.expr(cond.children[0]) if cond and cond.children else 'true'}:{c}")
            for k in (then.children if then else []):
                self.stmt(k, d + 1)
            if els and els.children:
                self.emit(d, "else:")
                for k in els.children:
                    self.stmt(k, d + 1)
            return
        if f == "while":
            cond = next((k for k in kids if self.p.base_func(k) == "while_cond"), None)
            body = next((k for k in kids if self.p.base_func(k) == "while_body"), None)
            self.emit(d, f"while {self.expr(cond.children[0]) if cond and cond.children else 'true'}:{c}")
            for k in (body.children if body else []):
                self.stmt(k, d + 1)
            return
        if f == "repeat":
            num = next((k for k in kids if self.p.base_func(k) == "repeat_num"), None)
            self.emit(d, f"repeat {self.expr(num.children[0]) if num and num.children else '?'} times:{c}")
            for k in kids:
                if k is not num:
                    self.body(k, d + 1) if self.p.base_func(k) == "while_body" else self.stmt(k, d + 1)
            return
        if f == "case":
            ex = next((k for k in kids if self.p.base_func(k) == "case_expr"), None)
            self.emit(d, f"switch {self.expr(ex.children[0]) if ex and ex.children else '?'}:{c}")
            for k in kids:
                kf = self.p.base_func(k)
                if kf == "case_on":
                    vals = [self.expr(e.children[0]) for e in k.children if self.p.base_func(e) == "case_equ" and e.children]
                    self.emit(d + 1, f"case {', '.join(vals)}:{self.comment(k)}")
                    for s in k.children:
                        if self.p.base_func(s) != "case_equ":
                            self.stmt(s, d + 2)
                elif kf == "default":
                    if k.children:
                        self.emit(d + 1, f"default:{self.comment(k)}")
                        for s in k.children:
                            self.stmt(s, d + 2)
            return
        if isinstance(r, Node) and r.block in (B["GLOBAL"], B["LOCAL"]):
            if f == "function":
                self.emit(d, f"call {self.var(n)}({self.call_args(kids)}){c}")
            elif kids:
                self.emit(d, f"{self.var(n)} = {self.expr(kids[0])}{c}")
            else:
                self.emit(d, f"{self.var(n)}  # bare{c}")
            return
        if f in VAR_TYPES or f in ("list_size",):
            self.emit(d, f"{f}({', '.join(self.expr(k) for k in kids)}){c}")
            return
        args = ", ".join(self.arg(f, k) for k in kids)
        self.emit(d, f"{f}({args}){c}")

    def function(self, local_root: Node):
        owner = self.local_owner.get(local_root.index)
        title = self.name(owner) + f"@G{owner.index}" if owner else "<main>"
        ins, outs, locs = [], [], []
        for k in local_root.children:
            kf = self.p.base_func(k)
            if kf == "iparam":
                ins = [f"{self.name(x)}@L{x.index}" for x in k.children if x.name >= 0]
            elif kf == "oparam":
                outs = [f"{self.name(x)}@L{x.index}" for x in k.children if x.name >= 0]
            else:
                locs.extend(self._decls(k))
        self.emit(0, f"def {title}({', '.join(ins)}) -> ({', '.join(outs)}):")
        for l in locs:
            self.emit(1, f"local {l}")
        body_root = self.p.nodes[B["PROGRAM"]][local_root.dat_index]
        for k in body_root.children:
            self.stmt(k, 1)
        self.emit(0, "")

    def _decls(self, n: Node) -> list[str]:
        f = self.p.base_func(n)
        if f == "group":
            return [d for k in n.children for d in self._decls(k)]
        init = ""
        if n.dat_block == B["REAL"] and n.dat_index >= 0:
            init = f" = {self.p.reals[n.dat_index]}"
        elif n.dat_block == B["BOOL"] and n.dat_index >= 0:
            init = f" = {bool(self.p.bools[n.dat_index])}"
        else:
            init = f" [{f} dat={n.dat_block},{n.dat_index}]"
        return [f"{self.name(n)}@L{n.index}: {f}{init}"]

    def globals_(self):
        self.emit(0, "### GLOBALS")

        def walk(n: Node, d: int):
            f = self.p.base_func(n)
            init = ""
            if n.dat_block == B["REAL"] and n.dat_index >= 0:
                init = f" = {self.p.reals[n.dat_index]}"
            elif n.dat_block == B["BOOL"] and n.dat_index >= 0:
                init = f" = {bool(self.p.bools[n.dat_index])}"
            elif n.dat_block >= 0:
                init = f" [{self.p.blocks[n.dat_block].name}#{n.dat_index}]"
            self.emit(d, f"{self.name(n)}@G{n.index}: {f}{init}")
            for k in n.children:
                walk(k, d + 1)

        for r in self.p.roots[B["GLOBAL"]]:
            walk(r, 0)
        self.emit(0, "")

    def run(self) -> str:
        self.globals_()
        for root in self.p.roots[B["LOCAL"]]:
            self.function(root)
        return "\n".join(self.out)


if __name__ == "__main__":
    print(Decompiler(Program(sys.argv[1])).run())
