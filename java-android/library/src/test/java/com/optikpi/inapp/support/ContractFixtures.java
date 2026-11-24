package com.optikpi.inapp.support;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.json.JSONArray;
import org.json.JSONObject;

public final class ContractFixtures {
  public static final Path ROOT =
      Path.of(System.getProperty("user.dir")).getParent().getParent().resolve("contract/fixtures");

  private ContractFixtures() {}

  public static JSONObject readObject(String relative) throws Exception {
    byte[] bytes = Files.readAllBytes(ROOT.resolve(relative));
    String text = new String(bytes, StandardCharsets.UTF_8);
    return new JSONObject(text);
  }

  public static void expectMatches(Object actual, Object expected, String at) throws Exception {
    if (expected == JSONObject.NULL || expected == null) {
      if (actual == JSONObject.NULL) {
        return;
      }
      if (actual == null) {
        return;
      }
      throw new AssertionError(at + " expected null");
    }
    if (expected instanceof JSONObject exp) {
      if (!(actual instanceof JSONObject act)) {
        throw new AssertionError(at + " should be an object");
      }
      JSONArray keys = exp.names();
      if (keys != null) {
        for (int i = 0; i < keys.length(); i++) {
          String key = keys.getString(i);
          expectMatches(act.opt(key), exp.get(key), at + "." + key);
        }
      }
    } else if (expected instanceof org.json.JSONArray exp) {
      if (!(actual instanceof org.json.JSONArray act)) {
        throw new AssertionError(at + " should be an array");
      }
      if (exp.length() != act.length()) {
        throw new AssertionError(at + " length");
      }
      for (int i = 0; i < exp.length(); i++) {
        expectMatches(act.get(i), exp.get(i), at + "[" + i + "]");
      }
    } else if (expected instanceof Number n) {
      if (!(actual instanceof Number a)) {
        throw new AssertionError(at);
      }
      if (n.doubleValue() != a.doubleValue()) {
        throw new AssertionError(at + " expected " + n + " got " + actual);
      }
    } else if (!expected.equals(actual)) {
      throw new AssertionError(at + " expected " + expected + " got " + actual);
    }
  }
}