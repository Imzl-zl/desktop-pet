import { describe, it, expect, beforeEach } from "vitest";
import {
  savedSlug,
  saveSlug,
  clearSlug,
  getLibrary,
  addToLibrary,
  removeFromLibrary,
  libraryUrlForSlug,
  type LibPet,
} from "./catalog";

const mockStorage: Record<string, string> = {};

Object.defineProperty(globalThis, "localStorage", {
  value: {
    getItem(key: string) {
      return mockStorage[key] ?? null;
    },
    setItem(key: string, value: string) {
      mockStorage[key] = String(value);
    },
    removeItem(key: string) {
      delete mockStorage[key];
    },
  },
  writable: true,
});

beforeEach(() => {
  for (const key of Object.keys(mockStorage)) delete mockStorage[key];
});

const SAMPLE: LibPet = { slug: "cat", name: "Cat", url: "https://example.com/cat.png" };

const sampleLib = (): LibPet[] => [
  { slug: "dog", name: "Dog", url: "https://example.com/dog.png" },
  { slug: "cat", name: "Cat", url: "https://example.com/cat.png" },
];

describe("catalog persistence", () => {
  it("returns null when no pet is selected", () => {
    expect(savedSlug()).toBeNull();
  });

  it("saves and reads the selected slug", () => {
    saveSlug("cat");
    expect(savedSlug()).toBe("cat");
  });

  it("clears the selected slug", () => {
    saveSlug("cat");
    clearSlug();
    expect(savedSlug()).toBeNull();
  });
});

describe("library", () => {
  it("adds pets to the front of the library", () => {
    addToLibrary(SAMPLE);
    expect(getLibrary()[0]).toEqual(SAMPLE);
  });

  it("removes a pet by slug", () => {
    sampleLib().forEach(addToLibrary);
    removeFromLibrary("dog");
    expect(getLibrary().map((p) => p.slug)).toEqual(["cat"]);
  });

  it("resolves a slug to its library url", () => {
    sampleLib().forEach(addToLibrary);
    expect(libraryUrlForSlug("cat")).toBe("https://example.com/cat.png");
    expect(libraryUrlForSlug("missing")).toBeNull();
    expect(libraryUrlForSlug(null)).toBeNull();
  });
});
