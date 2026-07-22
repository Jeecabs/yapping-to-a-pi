import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { HelperProtocolError, parseDoctorMessage, parseHelperMessage } from "../src/protocol.ts";

describe("parseHelperMessage", () => {
  it("parses state and transcript messages", () => {
    assert.deepEqual(
      parseHelperMessage(
        '{"type":"state","state":"listening","locale":"en-AU","inputDevice":"MacBook Pro Microphone"}',
      ),
      {
        type: "state",
        state: "listening",
        locale: "en-AU",
        inputDevice: "MacBook Pro Microphone",
      },
    );
    assert.deepEqual(parseHelperMessage('{"type":"partial","text":"hello"}'), {
      type: "partial",
      text: "hello",
    });
    assert.deepEqual(parseHelperMessage('{"type":"final","text":""}'), {
      type: "final",
      text: "",
    });
  });

  it("rejects malformed and unknown messages", () => {
    assert.throws(() => parseHelperMessage("nope"), HelperProtocolError);
    assert.throws(() => parseHelperMessage("[]"), HelperProtocolError);
    assert.throws(() => parseHelperMessage('{"type":"state","state":"magic","locale":"en-AU"}'), HelperProtocolError);
    assert.throws(() => parseHelperMessage('{"type":"final","text":4}'), HelperProtocolError);
  });
});

describe("parseDoctorMessage", () => {
  it("validates diagnostics fields", () => {
    assert.deepEqual(
      parseDoctorMessage(
        '{"type":"doctor","locale":"en-AU","engine":"speech-transcriber","supported":true,"installed":true,"microphone":"authorized","inputDevice":"MacBook Pro Microphone","osVersion":"Version 26.6"}',
      ),
      {
        type: "doctor",
        locale: "en-AU",
        engine: "speech-transcriber",
        supported: true,
        installed: true,
        microphone: "authorized",
        inputDevice: "MacBook Pro Microphone",
        osVersion: "Version 26.6",
      },
    );
  });
});
