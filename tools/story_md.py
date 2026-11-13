"""
The story as it plays (godot/story/slice.json), written out for reading: docs/STORY.md. Every step in order: what
Karthik is told to do (its goal), where he goes, who says what (thoughts and actions in brackets as the game shows
them, with the line's feeling when it has one), the choices and their options, what he's handed, the messages, the
evidence. The plot, the characters and why are in docs/STORY_BIBLE.md; this is the game's own order and words.
    python3 tools/story_md.py [--ta]      (--ta: the Tamil, not the English)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "story", "slice.json")
OUT = os.path.join(HERE, "..", "docs", "STORY.md")
LANG = "ta" if "--ta" in sys.argv else "en"


def t(v):
    if isinstance(v, dict):
        return str(v.get(LANG, v.get("en", "")))
    return str(v or "")


def main():
    d = json.load(open(SRC, encoding="utf-8"))
    people = d.get("people", {})
    places = d.get("places", {})

    def who(k):
        return t(people.get(k, {})) or k.capitalize()

    out = ["# The Mist Village: the story as it plays (Part 1, \"The Wrong Accusation\")", "",
           "Written out from the game's own story file (`godot/story/slice.json`) by `tools/story_md.py`: regenerate it "
           "when the story changes. The plot, the characters and the decisions behind them are in "
           "[STORY_BIBLE.md](STORY_BIBLE.md). Lines in brackets are Karthik's thoughts or what happens, not spoken. "
           "*Italics after a line* are how it's acted (its feeling, from `story/emotions.json`).", ""]
    day = 1
    for i, s in enumerate(d["steps"]):
        do = s.get("do", "")
        if do == "sleep" or s.get("add_days"):
            day += int(s.get("add_days", 1))
        head = ""
        if do == "drive":
            head = "Drive: " + t(places.get(s.get("to"), s.get("to", "")))
        elif do == "home":                               # (walking about a room: home, the office, the station...)
            room = str(s.get("room", "home"))
            head = "At home" if room == "home" else "In the room: " + room.replace("_", " ")
        elif do == "talk":
            head = "Talk" + (" (" + ", ".join(who(k) for k in s.get("cast", {})) + ")" if s.get("cast") else "")
        elif do == "choose":
            head = "Choice"
        elif do == "meet":
            head = "Meet " + who(s.get("who", ""))
        elif do == "evidence":
            head = "Evidence " + str(s.get("tag", ""))
        elif do == "message":
            head = "Message from " + t(s.get("from", ""))
        elif do == "give":
            head = "Handed: " + str(s.get("item", {}).get("kind", "something"))
        else:
            head = do.replace("_", " ").capitalize() if do else "Step"
        out.append("### %d. %s" % (i, head))
        if s.get("when"):
            out.append("*(only if: %s)*" % s["when"])
        if s.get("goal"):
            out.append("**Goal:** " + t(s["goal"]))
        if s.get("prompt") and do != "choose":
            out.append("**Prompt:** " + t(s["prompt"]))
        for v in s.get("visits", []) or []:
            bits = [t(v.get("goal", ""))]
            if v.get("task"):
                bits.append("(%s%s)" % (v["task"], ": " + ", ".join(v.get("chores", [])) if v.get("chores") else ""))
            out.append("- " + " ".join(b for b in bits if b))
        for ln in s.get("lines", []) or []:
            if not isinstance(ln, dict):
                continue
            feel = ""
            if ln.get("emotion"):
                feel = " *(%s%s%s)*" % (ln["emotion"], ", " + ln.get("intensity", "") if ln.get("intensity") else "",
                                        ", " + ln["gesture"] if ln.get("gesture") else "")
            out.append("- **%s:** %s%s" % (who(ln.get("who", "")), t(ln), feel))
        if do == "choose":
            out.append("**%s**" % t(s.get("prompt", "")))
            for o in s.get("options", []):
                out.append("- %s  `→ %s`" % (t(o.get("text", "")), o.get("set", "")))
        if do == "message":
            out.append("> " + t(s.get("text", "")).replace("\n", "\n> "))
        if do == "give":
            it = s.get("item", {})
            body = t(it.get("body", ""))
            if body:
                out.append("> " + body.replace("\n", "\n> "))
        if do == "evidence":
            out.append("- " + t(s.get("label", "")))
            if s.get("memory"):
                out.append("  - " + t(s["memory"].get("title", "")) + ": " + t(s["memory"].get("body", "")).replace("\n", " "))
        out.append("")
    open(OUT, "w", encoding="utf-8").write("\n".join(out))
    print("STORY.md: %d steps, %d lines" % (len(d["steps"]), len(out)))


if __name__ == "__main__":
    main()
