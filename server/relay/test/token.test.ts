import { describe, expect, it } from "vitest";
import { tokenAllows } from "../src/token";

describe("the app's passphrase", () => {
  it("is not asked on the Mac, where no passphrase is set", () => {
    expect(tokenAllows(undefined, null)).toBe(true);
    expect(tokenAllows("", "anything")).toBe(true);
  });

  it("lets only the same passphrase through", () => {
    expect(tokenAllows("romy-secret", "romy-secret")).toBe(true);
    expect(tokenAllows("romy-secret", "romy-secreT")).toBe(false);
    expect(tokenAllows("romy-secret", "romy-secret-and-more")).toBe(false);
    expect(tokenAllows("romy-secret", "romy")).toBe(false);
    expect(tokenAllows("romy-secret", null)).toBe(false);
  });
});
