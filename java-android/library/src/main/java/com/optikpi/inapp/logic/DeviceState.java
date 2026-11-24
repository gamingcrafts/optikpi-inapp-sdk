package com.optikpi.inapp.logic;

import android.content.Context;
import android.content.SharedPreferences;
import com.optikpi.inapp.InAppLog;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * Where the SDK keeps what belongs to this device: the ids it has shown and the events it still
 * owes the server. It lives in {@link Context#getNoBackupFilesDir()}, which Auto Backup and
 * device-to-device transfer leave out: restored onto another phone, a shown id would hide a
 * campaign that phone never showed, and queued events would be reported twice.
 *
 * <p>One file per key, replaced whole (written aside, then renamed). A key an earlier version kept
 * in SharedPreferences is moved here the first time it is read.
 */
public final class DeviceState {
  private final File dir;
  private final SharedPreferences legacy;

  public DeviceState(Context context) {
    Context app = context.getApplicationContext();
    File noBackup = app.getNoBackupFilesDir();
    if (noBackup != null && !noBackup.isDirectory() && !noBackup.mkdirs()) {
      noBackup = null;
    }
    dir = noBackup;
    legacy = app.getSharedPreferences("optikpi_inapp", Context.MODE_PRIVATE);
  }

  /** The value stored under {@code key}, or null. */
  public synchronized String read(String key) {
    if (dir == null) {
      return legacy.getString(key, null);
    }
    File file = new File(dir, key);
    if (file.isFile()) {
      try (FileInputStream in = new FileInputStream(file)) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int n;
        while ((n = in.read(buffer)) != -1) {
          out.write(buffer, 0, n);
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
      } catch (IOException e) {
        InAppLog.log("could not read " + key + ": " + e);
        return null;
      }
    }
    String old = legacy.getString(key, null);
    if (old != null) {
      write(key, old);
      if (file.isFile()) {
        legacy.edit().remove(key).apply();
      }
    }
    return old;
  }

  /** Replaces what is stored under {@code key}. */
  public synchronized void write(String key, String value) {
    if (dir == null) {
      legacy.edit().putString(key, value).apply();
      return;
    }
    File target = new File(dir, key);
    File aside = new File(dir, key + ".tmp");
    try {
      try (FileOutputStream out = new FileOutputStream(aside)) {
        out.write(value.getBytes(StandardCharsets.UTF_8));
        out.getFD().sync();
      }
      if (!aside.renameTo(target)) {
        throw new IOException("could not replace " + target);
      }
    } catch (IOException e) {
      InAppLog.log("could not save " + key + ": " + e);
      aside.delete();
    }
  }
}
