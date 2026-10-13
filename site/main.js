(() => {
  /* Reveal on scroll */
  const io = "IntersectionObserver" in window
    ? new IntersectionObserver((es) => es.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add("is-in"); io.unobserve(e.target); }
      }), { threshold: 0.15 })
    : null;
  document.querySelectorAll("[data-in]").forEach((el) => {
    if (io) io.observe(el); else el.classList.add("is-in");
  });

  /* Demo de desenho */
  const stage = document.getElementById("stage");
  const canvas = document.getElementById("board");
  if (!stage || !canvas) return;
  const ctx = canvas.getContext("2d");
  const hint = document.getElementById("hint");

  const state = { tool: "pen", color: "#b7f34a", ghost: false, items: [], cur: null, hover: false };
  const GHOST_MS = 3000, FADE_MS = 600;
  let w = 0, h = 0, raf = 0;

  const resize = () => {
    const r = stage.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = r.width; h = r.height;
    canvas.width = w * dpr; canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    render();
  };
  new ResizeObserver(resize).observe(stage);

  const pos = (e) => {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  const smooth = (pts) => {
    // media móvel curta para tirar o tremido do traço
    if (pts.length < 3) return pts;
    return pts.map((p, i) => {
      const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
      return { x: (a.x + p.x + b.x) / 3, y: (a.y + p.y + b.y) / 3 };
    });
  };

  const drawItem = (it, alpha = 1) => {
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.lineCap = "round"; ctx.lineJoin = "round";
    ctx.strokeStyle = it.color; ctx.fillStyle = it.color;
    if (it.type === "pen" || it.type === "hl") {
      ctx.lineWidth = it.type === "hl" ? 20 : 4;
      if (it.type === "hl") ctx.globalAlpha = alpha * 0.4;
      const pts = it.type === "pen" ? smooth(it.pts) : it.pts;
      ctx.beginPath();
      pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      if (pts.length === 1) ctx.lineTo(pts[0].x + 0.1, pts[0].y);
      ctx.stroke();
    } else if (it.type === "arrow") {
      const { a, b } = it;
      const ang = Math.atan2(b.y - a.y, b.x - a.x), s = 16;
      ctx.lineWidth = 4;
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(b.x, b.y);
      ctx.lineTo(b.x - s * Math.cos(ang - 0.45), b.y - s * Math.sin(ang - 0.45));
      ctx.moveTo(b.x, b.y);
      ctx.lineTo(b.x - s * Math.cos(ang + 0.45), b.y - s * Math.sin(ang + 0.45));
      ctx.stroke();
    } else if (it.type === "rect") {
      ctx.lineWidth = 4;
      ctx.strokeRect(it.a.x, it.a.y, it.b.x - it.a.x, it.b.y - it.a.y);
    } else if (it.type === "oval") {
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.ellipse((it.a.x + it.b.x) / 2, (it.a.y + it.b.y) / 2,
        Math.abs(it.b.x - it.a.x) / 2, Math.abs(it.b.y - it.a.y) / 2, 0, 0, Math.PI * 2);
      ctx.stroke();
    } else if (it.type === "text") {
      ctx.font = '600 22px "Geist", sans-serif';
      ctx.textBaseline = "top";
      ctx.fillText(it.text, it.a.x, it.a.y);
    }
    ctx.restore();
  };

  const alphaFor = (it, now) => {
    if (!it.expires) return 1;
    const left = it.expires - now;
    return left <= 0 ? 0 : Math.min(1, left / FADE_MS);
  };

  const render = () => {
    ctx.clearRect(0, 0, w, h);
    const now = performance.now();
    state.items = state.items.filter((it) => {
      if (it.expires && it.expires <= now) { if (it.el) it.el.remove(); return false; }
      return true;
    });
    state.items.forEach((it) => {
      const a = alphaFor(it, now);
      if (it.el) it.el.style.opacity = a;
      drawItem(it, a);
    });
    if (state.cur && state.cur.type !== "blur") drawItem(state.cur);
    raf = 0;
    if (state.items.some((it) => it.expires)) raf = requestAnimationFrame(render);
  };
  const schedule = () => { if (!raf) raf = requestAnimationFrame(render); };

  const bbox = (it) => {
    if (it.pts) {
      const xs = it.pts.map((p) => p.x), ys = it.pts.map((p) => p.y);
      return { x1: Math.min(...xs), y1: Math.min(...ys), x2: Math.max(...xs), y2: Math.max(...ys) };
    }
    const a = it.a, b = it.b || { x: a.x + 120, y: a.y + 28 };
    return { x1: Math.min(a.x, b.x), y1: Math.min(a.y, b.y), x2: Math.max(a.x, b.x), y2: Math.max(a.y, b.y) };
  };

  const eraseAt = (p) => {
    const pad = 10;
    const hit = [...state.items].reverse().find((it) => {
      const b = bbox(it);
      if (it.pts) return it.pts.some((q) => Math.hypot(q.x - p.x, q.y - p.y) < 14);
      return p.x >= b.x1 - pad && p.x <= b.x2 + pad && p.y >= b.y1 - pad && p.y <= b.y2 + pad;
    });
    if (hit) {
      if (hit.el) hit.el.remove();
      state.items.splice(state.items.indexOf(hit), 1);
      render();
    }
  };

  const commit = (it) => {
    if (state.ghost) it.expires = performance.now() + GHOST_MS + FADE_MS;
    state.items.push(it);
    hint.classList.add("is-gone");
    render();
  };

  const snap = (a, b) => {
    const dx = b.x - a.x, dy = b.y - a.y, len = Math.hypot(dx, dy);
    const ang = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
    return { x: a.x + len * Math.cos(ang), y: a.y + len * Math.sin(ang) };
  };

  let blurPreview = null;
  const placeBlur = (el, a, b) => {
    el.style.left = Math.min(a.x, b.x) + "px";
    el.style.top = Math.min(a.y, b.y) + "px";
    el.style.width = Math.abs(b.x - a.x) + "px";
    el.style.height = Math.abs(b.y - a.y) + "px";
  };

  const startText = (p) => {
    const input = document.createElement("input");
    input.className = "txt-input";
    input.style.left = p.x + "px"; input.style.top = p.y + "px";
    input.style.color = state.color;
    input.setAttribute("aria-label", "Texto");
    stage.appendChild(input);
    input.focus();
    let done = false;
    const finish = (ok) => {
      if (done) return; done = true;
      const text = input.value.trim();
      input.remove();
      if (ok && text) commit({ type: "text", a: { x: p.x + 4, y: p.y + 2 }, text, color: state.color });
    };
    input.addEventListener("keydown", (e) => {
      e.stopPropagation();
      if (e.key === "Enter") finish(true);
      if (e.key === "Escape") finish(false);
    });
    input.addEventListener("blur", () => finish(true));
  };

  canvas.addEventListener("pointerdown", (e) => {
    const p = pos(e);
    if (state.tool === "text") { e.preventDefault(); startText(p); return; }
    canvas.setPointerCapture(e.pointerId);
    if (state.tool === "erase") { state.cur = { type: "erase" }; eraseAt(p); return; }
    if (state.tool === "pen" || state.tool === "hl") {
      state.cur = { type: state.tool, pts: [p], color: state.color };
    } else if (state.tool === "blur") {
      state.cur = { type: "blur", a: p, b: p };
      blurPreview = document.createElement("div");
      blurPreview.className = "blurbox";
      stage.insertBefore(blurPreview, canvas.nextSibling);
      placeBlur(blurPreview, p, p);
    } else {
      state.cur = { type: state.tool, a: p, b: p, color: state.color, shift: e.shiftKey };
    }
    render();
  });

  canvas.addEventListener("pointermove", (e) => {
    const c = state.cur; if (!c) return;
    const p = pos(e);
    if (c.type === "erase") return eraseAt(p);
    if (c.pts) c.pts.push(p);
    else if (c.type === "blur") { c.b = p; placeBlur(blurPreview, c.a, p); }
    else {
      let b = p;
      if (e.shiftKey) {
        if (c.type === "arrow") b = snap(c.a, p);
        else { const s = Math.max(Math.abs(p.x - c.a.x), Math.abs(p.y - c.a.y)); b = { x: c.a.x + Math.sign(p.x - c.a.x || 1) * s, y: c.a.y + Math.sign(p.y - c.a.y || 1) * s }; }
      }
      c.b = b;
    }
    render();
  });

  const end = () => {
    const c = state.cur; state.cur = null;
    if (!c || c.type === "erase") return;
    if (c.type === "blur") {
      if (Math.abs(c.b.x - c.a.x) < 6 || Math.abs(c.b.y - c.a.y) < 6) { blurPreview.remove(); }
      else {
        c.el = blurPreview;
        if (state.ghost) c.expires = performance.now() + GHOST_MS + FADE_MS;
        state.items.push(c); hint.classList.add("is-gone"); render();
      }
      blurPreview = null; return;
    }
    commit(c);
  };
  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", end);

  /* Barra de ferramentas */
  const toolBtns = [...stage.querySelectorAll("[data-tool]")];
  const setTool = (t) => {
    state.tool = t;
    toolBtns.forEach((b) => b.classList.toggle("is-on", b.dataset.tool === t));
    canvas.style.cursor = t === "text" ? "text" : "crosshair";
  };
  toolBtns.forEach((b) => b.addEventListener("click", () => setTool(b.dataset.tool)));

  const ghostBtn = document.getElementById("ghost");
  const setGhost = (on) => {
    state.ghost = on;
    ghostBtn.setAttribute("aria-pressed", String(on));
  };
  ghostBtn.addEventListener("click", () => setGhost(!state.ghost));

  const undo = () => {
    const it = state.items.pop();
    if (it && it.el) it.el.remove();
    render();
  };
  const clear = () => {
    state.items.forEach((it) => it.el && it.el.remove());
    state.items = [];
    render();
  };
  document.getElementById("undo").addEventListener("click", undo);
  document.getElementById("clear").addEventListener("click", clear);

  const swatches = [...stage.querySelectorAll(".sw")];
  swatches.forEach((s) => s.addEventListener("click", () => {
    state.color = s.dataset.color;
    swatches.forEach((x) => { x.classList.toggle("is-on", x === s); x.setAttribute("aria-checked", String(x === s)); });
  }));

  /* Atalhos de teclado (só enquanto o mouse está sobre a demo ou ela tem foco) */
  stage.addEventListener("pointerenter", () => (state.hover = true));
  stage.addEventListener("pointerleave", () => (state.hover = false));
  const keyMap = { p: "pen", h: "hl", a: "arrow", r: "rect", o: "oval", t: "text", d: "blur", e: "erase" };
  document.addEventListener("keydown", (e) => {
    if (!(state.hover || stage.contains(document.activeElement))) return;
    if (e.target instanceof HTMLInputElement) return;
    const k = e.key.toLowerCase();
    if ((e.metaKey || e.ctrlKey) && k === "z") { e.preventDefault(); undo(); return; }
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (keyMap[k]) { e.preventDefault(); setTool(keyMap[k]); }
    else if (k === "g") setGhost(!state.ghost);
    else if (k >= "1" && k <= "5") swatches[Number(k) - 1].click();
  });

  resize();
})();
