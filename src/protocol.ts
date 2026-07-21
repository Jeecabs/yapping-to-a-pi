export const HELPER_STATES = [
  "preparing",
  "installing-model",
  "requesting-permission",
  "listening",
  "finalizing",
] as const;

export type HelperState = (typeof HELPER_STATES)[number];

export type HelperMessage =
  | { type: "state"; state: HelperState; locale: string }
  | { type: "partial"; text: string }
  | { type: "final"; text: string }
  | { type: "error"; code: string; message: string };

export interface DoctorMessage {
  type: "doctor";
  locale: string;
  engine: "speech-transcriber";
  supported: boolean;
  installed: boolean;
  microphone: "authorized" | "denied" | "not-determined" | "restricted" | "unknown";
  osVersion: string;
}

export class HelperProtocolError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "HelperProtocolError";
  }
}

export function parseHelperMessage(line: string): HelperMessage {
  const value = parseJsonObject(line);
  const type = readString(value, "type");

  if (type === "state") {
    const state = readString(value, "state");
    if (!isHelperState(state)) throw new HelperProtocolError(`Unknown helper state: ${state}`);
    return { type, state, locale: readString(value, "locale") };
  }

  if (type === "partial" || type === "final") {
    return { type, text: readString(value, "text", { allowEmpty: true }) };
  }

  if (type === "error") {
    return {
      type,
      code: readString(value, "code"),
      message: readString(value, "message"),
    };
  }

  throw new HelperProtocolError(`Unknown helper message type: ${type}`);
}

export function parseDoctorMessage(line: string): DoctorMessage {
  const value = parseJsonObject(line);
  if (readString(value, "type") !== "doctor") {
    throw new HelperProtocolError("Expected a doctor message");
  }

  const microphone = readString(value, "microphone");
  if (!isMicrophoneStatus(microphone)) {
    throw new HelperProtocolError(`Unknown microphone status: ${microphone}`);
  }

  const engine = readString(value, "engine");
  if (engine !== "speech-transcriber") {
    throw new HelperProtocolError(`Unknown helper engine: ${engine}`);
  }

  return {
    type: "doctor",
    locale: readString(value, "locale"),
    engine,
    supported: readBoolean(value, "supported"),
    installed: readBoolean(value, "installed"),
    microphone,
    osVersion: readString(value, "osVersion"),
  };
}

function parseJsonObject(line: string): Record<string, unknown> {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    throw new HelperProtocolError("Helper emitted invalid JSON");
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HelperProtocolError("Helper message must be a JSON object");
  }

  return value as Record<string, unknown>;
}

function readString(
  value: Record<string, unknown>,
  key: string,
  options: { allowEmpty?: boolean } = {},
): string {
  const field = value[key];
  if (typeof field !== "string" || (!options.allowEmpty && field.trim().length === 0)) {
    throw new HelperProtocolError(`Helper message field '${key}' must be a string`);
  }
  return field;
}

function readBoolean(value: Record<string, unknown>, key: string): boolean {
  const field = value[key];
  if (typeof field !== "boolean") {
    throw new HelperProtocolError(`Helper message field '${key}' must be a boolean`);
  }
  return field;
}

function isHelperState(value: string): value is HelperState {
  return (HELPER_STATES as readonly string[]).includes(value);
}

function isMicrophoneStatus(value: string): value is DoctorMessage["microphone"] {
  return ["authorized", "denied", "not-determined", "restricted", "unknown"].includes(value);
}
