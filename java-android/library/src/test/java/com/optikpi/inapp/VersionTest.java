package com.optikpi.inapp;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class VersionTest {
  @Test
  public void versionMatchesReadme() {
    assertEquals("0.1.0", Version.OPTIKPI_INAPP_VERSION);
  }
}