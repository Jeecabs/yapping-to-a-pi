import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { nativeHostProblem, swiftToolchainProblem } from "../src/native-requirements.ts";

describe("native requirements", () => {
  it("reports unsupported hosts with actionable guidance", () => {
    assert.match(nativeHostProblem("darwin", "15.3.1") ?? "", /Upgrade macOS and Xcode, then reinstall/);
    assert.match(nativeHostProblem("linux") ?? "", /macOS 26 or newer is required/);
    assert.equal(nativeHostProblem("darwin", "26.0"), undefined);
    assert.equal(nativeHostProblem("darwin", "27.4"), undefined);
  });

  it("reports an outdated Swift toolchain", () => {
    assert.match(
      swiftToolchainProblem("Apple Swift version 6.1.2") ?? "",
      /Apple Swift 6\.2 or newer.*Upgrade Xcode/,
    );
    assert.equal(swiftToolchainProblem("Apple Swift version 6.2"), undefined);
    assert.equal(swiftToolchainProblem("Apple Swift version 7.0"), undefined);
  });
});
