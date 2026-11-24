package com.optikpi.inapp.render;

import static com.optikpi.inapp.model.PopupEnums.PopupLayout;

import com.optikpi.inapp.model.PopupContent;

public final class PopupBlocksPage {
  private PopupBlocksPage() {}

  public static boolean blocksPage(PopupLayout layout) {
    return layout != PopupLayout.banner && layout != PopupLayout.toast;
  }

  public static boolean blocksPage(PopupContent content) {
    return blocksPage(content.layout);
  }
}