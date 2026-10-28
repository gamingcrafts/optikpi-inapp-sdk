/* The starter templates from app_next `app/shared/popup/mockTemplates.ts` on dev, as JSON so
   they go through the same parser as server data. One change: the web templates use the
   app_next asset `/images/device-preview/3f7e1981c210.jpg`, which an app can't load, so those
   two use a gradient placeholder instead. */

const String _cardsPlaceholder = 'gradient:#0B6E4F,#101828';

const Map<String, dynamic> _darkTheme = {
  'background': '#101828',
  'text': '#FFFFFF',
  'primary': '#F79009',
  'overlayOpacity': 0.7,
  'radius': 16,
};

const Map<String, dynamic> _lightTheme = {
  'background': '#FFFFFF',
  'text': '#101828',
  'primary': '#7F56D9',
  'overlayOpacity': 0.5,
  'radius': 16,
};

const Map<String, dynamic> _close = {
  'show': true,
  'position': 'topRight',
  'tapOutsideToClose': true,
};

class MockPopupTemplate {
  const MockPopupTemplate(this.id, this.name, this.content);

  final String id;
  final String name;
  final Map<String, dynamic> content;
}

const List<MockPopupTemplate> mockPopupTemplates = [
  MockPopupTemplate('welcome-bonus', 'Welcome bonus', {
    'version': 1,
    'layout': 'modal',
    'size': 'md',
    'image': {'url': _cardsPlaceholder, 'alt': 'Playing cards'},
    'title': 'Welcome, {{first_name}}!',
    'body': 'Make your first deposit today and get a 100% bonus up to €200 plus 50 free spins.',
    'buttons': [
      {
        'label': 'Deposit now',
        'style': 'primary',
        'action': {'type': 'deeplink', 'value': 'app://cashier'},
      },
      {
        'label': 'Maybe later',
        'style': 'secondary',
        'action': {'type': 'dismiss'},
      },
    ],
    'close': _close,
    'theme': _darkTheme,
  }),
  MockPopupTemplate('deposit-reminder', 'Deposit reminder', {
    'version': 1,
    'layout': 'bottomSheet',
    'size': 'md',
    'image': {'url': 'gradient:#7F56D9,#F04438', 'alt': ''},
    'title': 'Your bonus is still waiting',
    'body': '{{first_name}}, your 50 free spins unlock with a €10 deposit. Offer ends tonight.',
    'buttons': [
      {
        'label': 'Claim free spins',
        'style': 'primary',
        'action': {'type': 'deeplink', 'value': 'app://cashier'},
      },
    ],
    'close': _close,
    'theme': _lightTheme,
  }),
  MockPopupTemplate('free-spins-expiring', 'Free spins expiring', {
    'version': 1,
    'layout': 'toast',
    'size': 'md',
    'position': 'topRight',
    'image': {'url': 'gradient:#F79009,#F04438', 'alt': ''},
    'title': '20 free spins expire in 2 hours',
    'body': 'Use them on Book of Dead before midnight.',
    'buttons': [
      {
        'label': 'Play now',
        'style': 'primary',
        'action': {'type': 'deeplink', 'value': 'app://game/book-of-dead'},
      },
    ],
    'close': _close,
    'theme': _lightTheme,
    'autoDismissSec': 8,
  }),
  MockPopupTemplate('big-win', 'Big win celebration', {
    'version': 1,
    'layout': 'fullscreen',
    'size': 'lg',
    'image': {'url': 'gradient:#F79009,#7F56D9', 'alt': ''},
    'title': 'Big win, {{first_name}}! 🎉',
    'body':
        'You just won €1,250 on Gates of Olympus. Keep the streak going with 10 bonus spins on us.',
    'buttons': [
      {
        'label': 'Collect spins',
        'style': 'primary',
        'action': {'type': 'deeplink', 'value': 'app://bonuses'},
      },
      {
        'label': 'Close',
        'style': 'secondary',
        'action': {'type': 'dismiss'},
      },
    ],
    'close': _close,
    'theme': _darkTheme,
  }),
  MockPopupTemplate('bet-boost', 'Bet-slip boost', {
    'version': 1,
    'layout': 'banner',
    'size': 'md',
    'position': 'top',
    'image': {'url': 'gradient:#12B76A,#0BA5EC', 'alt': ''},
    'title': 'Odds boost: Real Madrid to win',
    'body': '2.10 → 2.60 for the next 30 minutes',
    'buttons': [
      {
        'label': 'Bet now',
        'style': 'primary',
        'action': {'type': 'deeplink', 'value': 'app://sports/event/88231'},
      },
    ],
    'close': _close,
    'theme': {
      'background': '#101828',
      'text': '#FFFFFF',
      'primary': '#12B76A',
      'overlayOpacity': 0.7,
      'radius': 16,
    },
    'autoDismissSec': 10,
  }),
  MockPopupTemplate('maintenance', 'Maintenance notice', {
    'version': 1,
    'layout': 'modal',
    'size': 'sm',
    'title': 'Scheduled maintenance',
    'body':
        'Live casino will be unavailable on Sunday from 02:00 to 04:00 UTC. Slots and sports are not affected.',
    'buttons': [
      {
        'label': 'Got it',
        'style': 'primary',
        'action': {'type': 'dismiss'},
      },
    ],
    'close': {'show': false, 'position': 'topRight', 'tapOutsideToClose': true},
    'theme': _lightTheme,
  }),
  MockPopupTemplate('vip-invite', 'VIP invite', {
    'version': 1,
    'layout': 'modal',
    'size': 'lg',
    'image': {'url': 'gradient:#101828,#B54708', 'alt': ''},
    'title': 'You are invited to VIP Gold',
    'body':
        '{{first_name}}, enjoy a personal account manager, faster withdrawals and weekly cashback of 10%.',
    'buttons': [
      {
        'label': 'Join VIP',
        'style': 'primary',
        'action': {'type': 'deeplink', 'value': 'app://vip'},
      },
      {
        'label': 'Learn more',
        'style': 'secondary',
        'action': {'type': 'url', 'value': 'https://example.com/vip'},
      },
    ],
    'close': _close,
    'theme': {
      'background': '#101828',
      'text': '#FFFFFF',
      'primary': '#FDB022',
      'overlayOpacity': 0.7,
      'radius': 16,
    },
  }),
  MockPopupTemplate('image-promo', 'Image-only promo', {
    'version': 1,
    'layout': 'imageOnly',
    'size': 'iab_300x250',
    'image': {
      'url': _cardsPlaceholder,
      'alt': 'Weekend poker tournament',
      'tapAction': {'type': 'deeplink', 'value': 'app://poker'},
    },
    'buttons': <Object>[],
    'close': _close,
    'theme': _lightTheme,
  }),
];
