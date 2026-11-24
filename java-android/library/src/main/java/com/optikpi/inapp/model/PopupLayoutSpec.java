package com.optikpi.inapp.model;

import static com.optikpi.inapp.model.PopupEnums.PopupLayout;
import static com.optikpi.inapp.model.PopupEnums.PopupPosition;
import static com.optikpi.inapp.model.PopupEnums.PopupSize;

import java.util.Arrays;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

public final class PopupLayoutSpec {
  public final PopupLayout layout;
  public final List<PopupSize> sizes;
  public final List<PopupPosition> positions;
  public final boolean hasText;
  public final int maxButtons;
  public final boolean autoDismiss;

  public PopupLayoutSpec(
      PopupLayout layout,
      List<PopupSize> sizes,
      List<PopupPosition> positions,
      boolean hasText,
      int maxButtons,
      boolean autoDismiss) {
    this.layout = layout;
    this.sizes = sizes;
    this.positions = positions;
    this.hasText = hasText;
    this.maxButtons = maxButtons;
    this.autoDismiss = autoDismiss;
  }

  public static final Map<PopupLayout, PopupLayoutSpec> ALL;

  static {
    Map<PopupLayout, PopupLayoutSpec> map = new EnumMap<>(PopupLayout.class);
    map.put(
        PopupLayout.modal,
        new PopupLayoutSpec(
            PopupLayout.modal,
            Arrays.asList(PopupSize.sm, PopupSize.md, PopupSize.lg, PopupSize.iab_300x250),
            null,
            true,
            2,
            false));
    map.put(
        PopupLayout.fullscreen,
        new PopupLayoutSpec(
            PopupLayout.fullscreen,
            Collections.singletonList(PopupSize.lg),
            null,
            true,
            2,
            false));
    map.put(
        PopupLayout.bottomSheet,
        new PopupLayoutSpec(
            PopupLayout.bottomSheet,
            Arrays.asList(PopupSize.sm, PopupSize.md, PopupSize.lg),
            null,
            true,
            2,
            false));
    map.put(
        PopupLayout.banner,
        new PopupLayoutSpec(
            PopupLayout.banner,
            Arrays.asList(PopupSize.md, PopupSize.iab_320x50),
            Arrays.asList(PopupPosition.top, PopupPosition.bottom),
            true,
            1,
            true));
    map.put(
        PopupLayout.toast,
        new PopupLayoutSpec(
            PopupLayout.toast,
            Arrays.asList(PopupSize.sm, PopupSize.md),
            Arrays.asList(PopupPosition.topRight, PopupPosition.bottomRight),
            true,
            1,
            true));
    map.put(
        PopupLayout.imageOnly,
        new PopupLayoutSpec(
            PopupLayout.imageOnly,
            Arrays.asList(PopupSize.md, PopupSize.lg, PopupSize.iab_300x250),
            null,
            false,
            0,
            false));
    ALL = Collections.unmodifiableMap(map);
  }
}