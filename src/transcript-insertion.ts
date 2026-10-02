import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

// Pi's editor collapses a paste over 1000 characters or 10 lines into a "[paste #n …]" marker.
const MAX_PASTE_CHARACTERS = 1_000;
const MAX_PASTE_LINES = 10;

export type TranscriptTarget = Pick<ExtensionContext, "mode"> & {
  ui: Pick<ExtensionContext["ui"], "getEditorText" | "pasteToEditor">;
};

export function insertTranscript(target: TranscriptTarget, transcript: string): void {
  const text = withSeparator(target.ui.getEditorText(), transcript);
  // RPC hosts replace the whole draft on each paste, so only the TUI editor receives chunks.
  const pastes = target.mode === "tui" ? splitIntoPastes(text) : [text];
  for (const paste of pastes) target.ui.pasteToEditor(paste);
}

export function withSeparator(editorText: string, transcript: string): string {
  // Pi does not expose the cursor, so assume dictation continues the end of the draft.
  return editorText && !/\s$/.test(editorText) ? ` ${transcript}` : transcript;
}

export function splitIntoPastes(text: string): string[] {
  const pastes: string[] = [];
  let current = "";
  for (const token of pasteTokens(text)) {
    if (current && !fitsInOnePaste(current + token)) {
      pastes.push(current);
      current = "";
    }
    current += token;
  }
  if (current) pastes.push(current);
  return pastes;
}

// Whitespace stays at the end of a chunk so the next chunk starts after a separator.
function pasteTokens(text: string): string[] {
  return (text.match(/\s+|\S+/gu) ?? []).flatMap((token) => fitsInOnePaste(token) ? [token] : Array.from(token));
}

function fitsInOnePaste(text: string): boolean {
  const normalized = text.replace(/\r\n?/g, "\n").replace(/\t/g, "    ");
  return normalized.length <= MAX_PASTE_CHARACTERS && normalized.split("\n").length <= MAX_PASTE_LINES;
}
