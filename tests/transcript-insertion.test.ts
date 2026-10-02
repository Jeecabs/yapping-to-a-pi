import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Editor, type EditorTheme, type TUI } from "@earendil-works/pi-tui";

import { insertTranscript, splitIntoPastes, withSeparator, type TranscriptTarget } from "../src/transcript-insertion.ts";

const LONG_TRANSCRIPT = "the quick brown fox jumps over the lazy dog ".repeat(60).trim();

function piEditorTarget(mode: TranscriptTarget["mode"] = "tui") {
  const tui = { requestRender() {}, terminal: { rows: 40, columns: 100 } } as unknown as TUI;
  const plain = (text: string) => text;
  const theme = {
    borderColor: plain,
    selectList: { selectedPrefix: plain, selectedText: plain, description: plain, scrollInfo: plain, noMatch: plain },
  } as unknown as EditorTheme;
  const editor = new Editor(tui, theme);
  const pastes: string[] = [];
  const target: TranscriptTarget = {
    mode,
    ui: {
      getEditorText: () => editor.getExpandedText(),
      // Mirrors Pi's interactive pasteToEditor, which sends a bracketed paste through the editor.
      pasteToEditor: (text) => {
        pastes.push(text);
        editor.handleInput(`\x1b[200~${text}\x1b[201~`);
      },
    },
  };
  return { editor, pastes, target };
}

describe("transcript insertion", () => {
  it("keeps long dictation editable instead of collapsing it into a paste marker", () => {
    const { editor, pastes, target } = piEditorTarget();

    insertTranscript(target, LONG_TRANSCRIPT);

    assert.ok(LONG_TRANSCRIPT.length > 2_000);
    assert.ok(pastes.length > 1);
    assert.equal(editor.getText(), LONG_TRANSCRIPT);
    assert.doesNotMatch(editor.getText(), /\[paste #/);
  });

  it("separates consecutive dictations from the draft", () => {
    const { editor, target } = piEditorTarget();

    insertTranscript(target, "Hello world.");
    insertTranscript(target, "How are you?");

    assert.equal(editor.getText(), "Hello world. How are you?");
  });

  it("sends RPC hosts one paste because they replace the draft on each paste", () => {
    const pastes: string[] = [];
    insertTranscript(
      { mode: "rpc", ui: { getEditorText: () => "", pasteToEditor: (text) => pastes.push(text) } },
      LONG_TRANSCRIPT,
    );

    assert.deepEqual(pastes, [LONG_TRANSCRIPT]);
  });

  it("adds a separator only after non-whitespace draft text", () => {
    assert.equal(withSeparator("", "Hello."), "Hello.");
    assert.equal(withSeparator("Fix this", "Hello."), " Hello.");
    assert.equal(withSeparator("Fix this ", "Hello."), "Hello.");
    assert.equal(withSeparator("Fix this\n", "Hello."), "Hello.");
  });

  it("splits within Pi's paste limits without losing text", () => {
    const unbroken = "x".repeat(2_500);
    const lines = Array.from({ length: 25 }, (_, index) => `line ${index}`).join("\n");

    for (const text of [LONG_TRANSCRIPT, unbroken, lines, "😀".repeat(700)]) {
      const pastes = splitIntoPastes(text);
      assert.equal(pastes.join(""), text);
      for (const paste of pastes) {
        assert.ok(paste.length <= 1_000);
        assert.ok(paste.split("\n").length <= 10);
      }
    }
  });

  it("leaves short transcripts as one paste", () => {
    assert.deepEqual(splitIntoPastes("Hello world."), ["Hello world."]);
    assert.deepEqual(splitIntoPastes(""), []);
  });
});
