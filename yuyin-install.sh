#!/usr/bin/env bash
# 一键安装「语音」：所有文件都放在主文件夹里的「语音」文件夹（可见，包括虚拟环境 venv）
set -e
APP="$HOME/语音"

# 卸载：bash yuyin-install.sh uninstall
if [ "$1" = "uninstall" ]; then
  D="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
  rm -rf "$APP"
  rm -f "$HOME/.local/share/applications/yuyin.desktop" "$D/yuyin.desktop"
  echo "✅ 已彻底卸载「语音」（程序、虚拟环境、图标都已删除）。"
  exit 0
fi

echo "== 1/5 安装系统组件（需要输入开机密码）=="
sudo apt install -y python3-venv python3-tk xclip xdotool libportaudio2

echo "== 2/5 清理旧版 =="
DESK="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
rm -rf "$HOME/.local/share/shuohua"
rm -f "$HOME/.local/share/applications/shuohua.desktop" "$DESK/shuohua.desktop"

echo "== 3/5 写入程序文件 =="
mkdir -p "$APP"
cat > "$APP/yuyin.py" << 'PYEOF'
#!/usr/bin/env python3
# 说话变文字：实时预览字幕 + 说完后精准修正 + 自动复制/粘贴
import threading, subprocess, time, json, os
import numpy as np
import sounddevice as sd
import tkinter as tk
import customtkinter as ctk
from faster_whisper import WhisperModel

SR = 16000
# ---------- 准确度设置（想更准就往下调这几项，代价是更慢）----------
FINAL_MODEL = "small"       # 最终结果用的模型：base(快) → small(更准) → medium(最准，最慢)
BEAM_SIZE = 5               # 搜索宽度：1 最快，5 更准
HINT_WORDS = ""             # 你常说的词，用逗号隔开，例如："点货, 发货单, 青光眼"
# -------------------------------------------------------------------
LIVE_MODEL = "tiny"         # 实时预览用的模型（更快）
LIVE_PREVIEW = True         # 电脑太卡就改成 False
ALPHA = 0.92                # 窗口透明度，越小越透明
OUTPUT_CHINESE = "simplified"   # "simplified" 简体 / "traditional" 繁體

# 识别精度档位（在软件里点「⚙ 设置」就能切换，会自动记住）
LEVELS = {"快": ("base", 1), "标准": ("small", 5), "高": ("medium", 5)}
CONF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "settings.json")
cur_level = "标准"
try:
    _c = json.load(open(CONF, encoding="utf-8"))
    if _c.get("level") in LEVELS:
        cur_level = _c["level"]
    LIVE_PREVIEW = bool(_c.get("preview", LIVE_PREVIEW))
    HINT_WORDS = str(_c.get("hint", HINT_WORDS))
except Exception:
    pass
FINAL_MODEL, BEAM_SIZE = LEVELS[cur_level]

try:
    from opencc import OpenCC
    _cc = OpenCC("t2s" if OUTPUT_CHINESE == "simplified" else "s2t")
    conv = _cc.convert
except Exception:
    conv = lambda s: s

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

GREEN, RED, GRAY = "#2FA572", "#D9534F", "#555555"

live_model = final_model = None
loaded_final = None
frames = []
stream = None
recording = False
last_win = None
live_thread = None
pasted_win = None   # 上一次自动粘贴去的窗口
pasted_len = 0      # 上一次粘贴的字数

root = ctk.CTk()
root.title("语音")
root.geometry("360x232+40+40")
root.attributes("-topmost", True)
try:
    root.attributes("-alpha", ALPHA)
except Exception:
    pass

top = ctk.CTkFrame(root, fg_color="transparent")
top.pack(fill="x", padx=14, pady=(6, 0))
cfg_btn = ctk.CTkButton(top, text="⚙ 设置", width=72, height=26, font=("Sans", 12),
                        corner_radius=10, fg_color="#444444", hover_color="#666666",
                        command=lambda: open_settings())
cfg_btn.pack(side="right")
status = ctk.CTkLabel(top, text="正在加载模型…", font=("Sans", 12), wraplength=250,
                      justify="left", anchor="w")
status.pack(side="left", fill="x", expand=True)

row = ctk.CTkFrame(root, fg_color="transparent")
row.pack(fill="x", padx=14, pady=2)

btn = ctk.CTkButton(row, text="加载中…", font=("Sans", 17, "bold"), height=40,
                    corner_radius=16, state="disabled", fg_color=GRAY)
btn.pack(side="left", fill="x", expand=True)

sw = ctk.CTkSwitch(root, text="识别完自动粘贴到刚才的窗口", font=("Sans", 12))
sw.select()
sw.pack(side="bottom", pady=(2, 6))

clr = ctk.CTkButton(row, text="🗑 清除", font=("Sans", 13), width=72, height=40,
                    corner_radius=12, fg_color="#444444", hover_color="#666666",
                    command=lambda: clear_all())
clr.pack(side="left", padx=(6, 0))

box = ctk.CTkTextbox(root, font=("Sans", 16), corner_radius=10, wrap="word",
                     activate_scrollbars=True)
box.pack(fill="both", expand=True, padx=14, pady=6)
box._textbox.tag_config("draft", foreground="#9aa0a6")


def load_models():
    global live_model, final_model, loaded_final
    name = FINAL_MODEL
    if name != loaded_final:
        final_model = WhisperModel(name, device="cpu", compute_type="int8", cpu_threads=4)
        loaded_final = name
    if LIVE_PREVIEW and live_model is None:
        live_model = WhisperModel(LIVE_MODEL, device="cpu", compute_type="int8", cpu_threads=4)
    root.after(0, ready)


def ready():
    btn.configure(text="🎤 点击说话", state="normal", fg_color=GREEN)
    status.configure(text=f"准备好了（精度：{cur_level}），点绿色按钮说话。")


def poll_window():
    global last_win
    try:
        if root.focus_displayof() is None:
            out = subprocess.run(["xdotool", "getactivewindow"],
                                 capture_output=True, text=True).stdout.strip()
            if out:
                last_win = out
    except Exception:
        pass
    root.after(500, poll_window)


def callback(indata, n, t, s):
    frames.append(indata.copy())


def show(text, tag):
    box.delete("1.0", "end")
    box.insert("end", text, tag)
    box.see("end")   # 文字太多时自动滚到最新一行


def live_loop():
    last_n = 0
    while recording:
        snap = list(frames)
        total = sum(len(f) for f in snap)
        if total - last_n < SR * 1.0:
            time.sleep(0.2)
            continue
        last_n = total
        audio = np.concatenate(snap).flatten()[-SR * 25:]
        segs, _ = live_model.transcribe(audio, language="zh", beam_size=1, best_of=1,
                                        temperature=0.0, condition_on_previous_text=False,
                                        vad_filter=True)
        text = conv("".join(s.text for s in segs).strip())
        if recording and text:
            root.after(0, lambda t=text: show(t, "draft"))


def toggle():
    global recording, stream, frames, live_thread
    if not recording:
        frames = []
        stream = sd.InputStream(samplerate=SR, channels=1, dtype="float32", callback=callback)
        stream.start()
        recording = True
        btn.configure(text="⏹ 说完了，点这里", fg_color=RED)
        status.configure(text="🔴 正在听…灰色字是预览，说完会自动修正。" if LIVE_PREVIEW
                         else "🔴 正在听…说完请再点一下。")
        box.delete("1.0", "end")
        if LIVE_PREVIEW:
            live_thread = threading.Thread(target=live_loop, daemon=True)
            live_thread.start()
    else:
        stream.stop(); stream.close()
        recording = False
        btn.configure(text="修正中…", state="disabled", fg_color=GRAY)
        status.configure(text="正在精准修正文字…")
        threading.Thread(target=final_pass, daemon=True).start()


def final_pass():
    if live_thread:
        live_thread.join()
    if not frames:
        root.after(0, lambda: finish(""))
        return
    audio = np.concatenate(frames).flatten()
    peak = float(np.abs(audio).max())          # 声音太小就自动放大，识别更准
    if peak > 0:
        audio = audio * min(0.9 / peak, 8.0)
    lang = "简体中文" if OUTPUT_CHINESE == "simplified" else "繁體中文"
    prompt = f"以下是普通话的句子，使用{lang}和标点符号。" + (HINT_WORDS or "")
    segs, _ = final_model.transcribe(audio, language="zh", initial_prompt=prompt,
                                     beam_size=BEAM_SIZE, best_of=5,
                                     temperature=[0.0, 0.2, 0.4],
                                     condition_on_previous_text=False, vad_filter=True,
                                     vad_parameters=dict(min_silence_duration_ms=500))
    text = conv("".join(s.text for s in segs).strip())
    root.after(0, lambda: finish(text))


def clear_all():
    """清空小窗口；并把刚才自动粘贴出去的字，在原窗口里用退格键删掉"""
    global pasted_win, pasted_len
    if recording:
        return
    box.delete("1.0", "end")
    msg = "🗑 已清空，可以重新说话。"
    if pasted_win and pasted_len > 0:
        try:
            subprocess.run(["xdotool", "windowactivate", "--sync", pasted_win])
            time.sleep(0.2)
            n = min(pasted_len, 2000)
            subprocess.run(["xdotool", "key", "--clearmodifiers"] + ["BackSpace"] * n)
            msg = "🗑 已删除刚才粘贴的文字，可以重新说话。"
        except Exception:
            pass
    pasted_win, pasted_len = None, 0
    status.configure(text=msg)


def finish(text):
    global pasted_win, pasted_len
    btn.configure(text="🎤 点击说话", state="normal", fg_color=GREEN)
    if not text:
        status.configure(text="没听清，请再点一次说话。")
        return
    show(text, "final")
    subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode())
    msg = "✅ 已复制，按 Ctrl+V 可粘贴。"
    if sw.get() == 1 and last_win:
        try:
            subprocess.run(["xdotool", "windowactivate", "--sync", last_win])
            time.sleep(0.2)
            subprocess.run(["xdotool", "key", "--clearmodifiers", "ctrl+v"])
            msg = "✅ 已粘贴到刚才的窗口，也已复制。"
            pasted_win, pasted_len = last_win, len(text)
        except Exception:
            pass
    status.configure(text=msg)


def apply_settings(level, preview, hint):
    global cur_level, FINAL_MODEL, BEAM_SIZE, LIVE_PREVIEW, HINT_WORDS
    cur_level = level
    FINAL_MODEL, BEAM_SIZE = LEVELS[level]
    LIVE_PREVIEW = preview
    HINT_WORDS = hint
    try:
        with open(CONF, "w", encoding="utf-8") as f:
            json.dump({"level": level, "preview": preview, "hint": hint}, f, ensure_ascii=False)
    except Exception:
        pass
    if FINAL_MODEL != loaded_final or (LIVE_PREVIEW and live_model is None):
        btn.configure(text="切换中…", state="disabled", fg_color=GRAY)
        status.configure(text="正在切换识别精度…第一次用要下载模型，请稍等。")
        threading.Thread(target=load_models, daemon=True).start()
    else:
        status.configure(text=f"已保存设置（精度：{cur_level}）。")


def open_settings():
    if recording:
        return
    win = ctk.CTkToplevel(root)
    win.title("设置")
    win.geometry("340x340+60+60")
    win.attributes("-topmost", True)
    win.after(150, win.lift)
    descs = {"快": "base 模型：最快，准确度一般。",
             "标准": "small 模型：更准，大约慢 3 倍（第一次要下载约 460MB）。",
             "高": "medium 模型：最准也最慢，旧电脑可能要等很久（第一次要下载约 1.5GB）。"}
    ctk.CTkLabel(win, text="识别精度（越高越准，但越慢）", font=("Sans", 14, "bold")).pack(pady=(14, 6))
    seg = ctk.CTkSegmentedButton(win, values=list(LEVELS.keys()),
                                 command=lambda v: desc.configure(text=descs[v]))
    seg.set(cur_level)
    seg.pack(padx=20, fill="x")
    desc = ctk.CTkLabel(win, text=descs[cur_level], font=("Sans", 12), wraplength=300)
    desc.pack(pady=6)
    sw_prev = ctk.CTkSwitch(win, text="显示说话时的灰色实时预览", font=("Sans", 12))
    if LIVE_PREVIEW:
        sw_prev.select()
    sw_prev.pack(pady=(6, 2))
    ctk.CTkLabel(win, text="（关掉后，文字只在说完时出现一次）", font=("Sans", 11),
                 text_color="#9aa0a6").pack()
    ctk.CTkLabel(win, text="常用词（用逗号隔开，帮助识别专有名词）",
                 font=("Sans", 12)).pack(pady=(10, 2))
    ent = ctk.CTkEntry(win, font=("Sans", 13))
    ent.insert(0, HINT_WORDS)
    ent.pack(padx=20, fill="x")

    def save():
        apply_settings(seg.get(), sw_prev.get() == 1, ent.get().strip())
        win.destroy()
    ctk.CTkButton(win, text="保存", height=36, command=save).pack(pady=14, padx=20, fill="x")


btn.configure(command=toggle)
threading.Thread(target=load_models, daemon=True).start()
poll_window()
root.mainloop()
PYEOF
cat > "$APP/yuyin.svg" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" xmlns:c2pa="http://c2pa.org/manifest"><metadata><c2pa:manifest>AAAWgmp1bWIAAAAeanVtZGMycGEAEQAQgAAAqgA4m3EDYzJwYQAAABZcanVtYgAAAEdqdW1kYzJtYQARABCAAACqADibcQN1cm46YzJwYTo1NDk2ZGExMS1lY2EzLTRlYjEtYjEyNS04YWIxZDJlNGZkM2QAAAADl2p1bWIAAAApanVtZGMyYXMAEQAQgAAAqgA4m3EDYzJwYS5hc3NlcnRpb25zAAAAALxqdW1iAAAARGp1bWRjYm9yABEAEIAAAKoAOJtxE2MycGEuaW5ncmVkaWVudC52MwAAAAAYYzJzaLhOrDgUKGvVmaPAnJpvOTYAAABwY2JvcqNpZGM6Zm9ybWF0bWltYWdlL3N2Zyt4bWxqaW5zdGFuY2VJRHgseG1wOmlpZDpkZGZkNDQyOC1iMDY3LTQwZjctYWVhMS1iODk3OGFmZGE4MmVscmVsYXRpb25zaGlwaHBhcmVudE9mAAAB4mp1bWIAAABBanVtZGNib3IAEQAQgAAAqgA4m3ETYzJwYS5hY3Rpb25zLnYyAAAAABhjMnNo9+2GbYj1zFgoET3jguu3ygAAAZljYm9yomdhY3Rpb25zgqJmYWN0aW9ua2MycGEub3BlbmVkanBhcmFtZXRlcnOha2luZ3JlZGllbnRzgaJjdXJseC1zZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmluZ3JlZGllbnQudjNkaGFzaFggBtEIdIaSglnvqgLetroFXfHO7Dyh3sH5M2rmRGCZfzSkZmFjdGlvbngdY29tLmFudGhyb3BpYy5jbGF1ZGUucHJvdmlkZWRqcGFyYW1ldGVyc6F4H2NvbS5hbnRocm9waWMub3JpZ2luLWNvbmZpZGVuY2VndW5rbm93bmtkZXNjcmlwdGlvbnhmQ2xhdWRlIHByb3ZpZGVkIHRoaXMgZmlsZSBhdCB0aGUgcmVxdWVzdCBvZiBhIHVzZXIgYW5kIG1heSBoYXZlIGNyZWF0ZWQgb3IgbW9kaWZpZWQgdGhlIGZpbGUgY29udGVudHMubXNvZnR3YXJlQWdlbnShZG5hbWVmQ2xhdWRlcmFsbEFjdGlvbnNJbmNsdWRlZPUAAADIanVtYgAAAEBqdW1kY2JvcgARABCAAACqADibcRNjMnBhLmhhc2guZGF0YQAAAAAYYzJzaPUheiDJfZ/ltW0QN82yVaMAAACAY2JvcqVjYWxnZnNoYTI1NmNwYWRNAAAAAAAAAAAAAAAAAGRoYXNoWCCEcGMonPkwMx219AySN/vOy6QHjhn7YLfCRDdCbzojLGRuYW1lbmp1bWJmIG1hbmlmZXN0amV4Y2x1c2lvbnOBomVzdGFydBh9Zmxlbmd0aBkeBAAAAj5qdW1iAAAAJ2p1bWRjMmNsABEAEIAAAKoAOJtxA2MycGEuY2xhaW0udjIAAAACD2Nib3KlY2FsZ2ZzaGEyNTZpc2lnbmF0dXJleE1zZWxmI2p1bWJmPS9jMnBhL3VybjpjMnBhOjU0OTZkYTExLWVjYTMtNGViMS1iMTI1LThhYjFkMmU0ZmQzZC9jMnBhLnNpZ25hdHVyZWppbnN0YW5jZUlEeCx4bXA6aWlkOmNlMDM1NTVhLTgxNzktNGVkMi05ZWNkLWFjNWFlNDE3ZWFhNnJjcmVhdGVkX2Fzc2VydGlvbnODomN1cmx4LXNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuaW5ncmVkaWVudC52M2RoYXNoWCAG0Qh0hpKCWe+qAt62ugVd8c7sPKHewfkzauZEYJl/NKJjdXJseCpzZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmFjdGlvbnMudjJkaGFzaFggP9ZBiOiGN7PPhqacRo9E//tUxtvSyuX/JPM1H+yZZeGiY3VybHgpc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5oYXNoLmRhdGFkaGFzaFgggnfPgOaycduAPlFkIivT3ae/FKsd4Q8VzizaNQr047l0Y2xhaW1fZ2VuZXJhdG9yX2luZm+jZG5hbWVvQW50aHJvcGljIEZpbGVzZ3ZlcnNpb25lMS4wLjBrc3BlY1ZlcnNpb25lMi40LjAAABA4anVtYgAAAChqdW1kYzJjcwARABCAAACqADibcQNjMnBhLnNpZ25hdHVyZQAAABAIY2JvctKEWQISogEmGCFZAgowggIGMIIBjaADAgECAhRA5aAK7sI50L64g/oGQgU9Z1UTADAKBggqhkjOPQQDAzBJMRcwFQYDVQQKEw5BbnRocm9waWMsIFBCQzEuMCwGA1UEAxMlQW50aHJvcGljIENvbnRlbnQgQ3JlZGVudGlhbHMgUm9vdCBDQTAeFw0yNjA4MDcxODQzNTZaFw0yODA4MDYxOTQzNTZaMEQxFzAVBgNVBAoTDkFudGhyb3BpYywgUEJDMSkwJwYDVQQDEyBBbnRocm9waWMgQ2xhdWRlIENvbnRlbnQgU2lnbmluZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJh6CmvLUBgFFNU0vUKlOVtE6djd17L5SuwX0LemFisBM3dkd/3cyjxFA3Qo5S46fX0/ihY0VZ7mfb9KF703t5OjWDBWMA4GA1UdDwEB/wQEAwIHgDAVBgNVHSUEDjAMBgorBgEEAYPoXgIBMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAUzlHiBIFOZFsj+OPEz5o+nMHXXMIwCgYIKoZIzj0EAwMDZwAwZAIwMXMdFJ4BetLLVY7ORuE9noqbbAZOZn/aArXyTwFAZfKrPzxF2vPoJNf1+UCdg1XGAjBwX1zd9WGqYkqmL5SFqw1QySjr1zJfpJM9+1rdDwSPLMOPOjKuiXjoU/pUUeG9RwmhY3BhZFkNngAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPZYQD+N1rzGbo7ESmcTjPyA6VQBotfikBt7UZsQqmRGSFHg42fGlD/D4EX+2qROIuHG9Tmn/d+wFuXX0ymO4tGz/uM=</c2pa:manifest></metadata>
  <rect width="256" height="256" rx="56" fill="#2FA572"/>
  <rect x="96" y="40" width="64" height="116" rx="32" fill="#ffffff"/>
  <path d="M68 132c0 33 27 60 60 60s60-27 60-60" fill="none" stroke="#ffffff" stroke-width="14" stroke-linecap="round"/>
  <path d="M128 192v34M96 226h64" fill="none" stroke="#ffffff" stroke-width="14" stroke-linecap="round"/>
</svg>
SVGEOF

echo "== 4/5 安装识别组件（第一次要几分钟）=="
[ -d "$APP/venv" ] || python3 -m venv "$APP/venv"
"$APP/venv/bin/pip" install faster-whisper sounddevice numpy customtkinter opencc-python-reimplemented

echo "== 5/5 创建图标 =="
mkdir -p "$HOME/.local/share/applications"
ENTRY="$HOME/.local/share/applications/yuyin.desktop"
cat > "$ENTRY" << EOT
[Desktop Entry]
Type=Application
Name=语音
Comment=点一下说话，自动变成文字
Exec=$APP/venv/bin/python $APP/yuyin.py
Icon=$APP/yuyin.svg
Terminal=false
Categories=Utility;Accessibility;
EOT
chmod +x "$ENTRY"
if [ -d "$DESK" ]; then
  cp "$ENTRY" "$DESK/yuyin.desktop"
  chmod +x "$DESK/yuyin.desktop"
  gio set "$DESK/yuyin.desktop" metadata::trusted true 2>/dev/null || true
fi

echo ""
echo "✅ 安装完成！桌面上和开始菜单里都有「语音」图标，双击就能用。"
echo "程序和虚拟环境都在：$APP"
echo "想卸载：bash yuyin-install.sh uninstall，或直接删除「语音」文件夹和桌面图标。"
