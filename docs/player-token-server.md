# Player tokens: what your server does

A player token tells OptiKPI which player an app is acting for. Your login server signs it, your app
passes it to the SDK, and OptiKPI verifies it. The in-app API key ships inside your app, so it only
identifies your workspace: the token is what stops one player reading another player's pop-ups.

**Never paste your private key into an online tool**, including JWT debuggers. Treat it like a
database password: on your server only, never in your app, never in a repo, never in a log.

## 1. Create a key

In OptiKPI, go to **Settings → Security → In-app SDK** and choose **Generate key**. You need to be a
workspace admin. The key pair is made in your browser, and only the public key reaches OptiKPI.

You see the private key and its key ID (`kid`) once. Copy or download both and put them in your
server's secret store. If you lose the private key, generate a new one.

A workspace can have two active keys, so you can rotate: generate a new key, deploy it, wait for
tokens signed with the old key to expire, then revoke the old one. Revoking takes effect on the next
request.

## 2. Create the token where the player logs in

Create it on your server, in your login response and in every session refresh, and return it as
`optikpiPlayerToken`. A restored session needs a new token too, so return one from whatever call your
app makes when it reopens with a saved session. Only return a token after you have verified that
session.

Header:

| Field | Value |
|---|---|
| `alg` | `ES256`. Nothing else is accepted. |
| `typ` | `JWT` |
| `kid` | The key ID from step 1 |

Payload:

| Field | Type | Value |
|---|---|---|
| `sub` | string | The player ID, exactly as you send it to OptiKPI. A number is refused, so convert it. |
| `wid` | string | Your OptiKPI workspace ID |
| `exp` | integer | Expiry, in whole seconds since 1970. No more than 90 days ahead. We recommend 24 hours. |

A fractional `exp` is refused, and `time.time() + 3600` and `Date.now() / 1000 + 3600` both give one.
Round down, as the examples do. Clocks may differ by up to 60 seconds.

### Node

Uses [`jose`](https://www.npmjs.com/package/jose).

```js
import { importPKCS8, SignJWT } from 'jose'

const privateKey = await importPKCS8(process.env.OPTIKPI_INAPP_PRIVATE_KEY.replace(/\\n/g, '\n'), 'ES256')

export const optikpiPlayerToken = (playerId) =>
  new SignJWT({ wid: process.env.OPTIKPI_WORKSPACE_ID })
    .setProtectedHeader({ alg: 'ES256', typ: 'JWT', kid: process.env.OPTIKPI_INAPP_KID })
    .setSubject(String(playerId))
    .setExpirationTime(Math.floor(Date.now() / 1000) + 24 * 60 * 60)
    .sign(privateKey)
```

### Python

Uses [`PyJWT`](https://pypi.org/project/PyJWT/) with its `crypto` extra: `pip install "pyjwt[crypto]"`.

```python
import os
import time

import jwt

PRIVATE_KEY = os.environ["OPTIKPI_INAPP_PRIVATE_KEY"].replace("\\n", "\n")


def optikpi_player_token(player_id):
    return jwt.encode(
        {
            "sub": str(player_id),
            "wid": os.environ["OPTIKPI_WORKSPACE_ID"],
            "exp": int(time.time()) + 24 * 60 * 60,
        },
        PRIVATE_KEY,
        algorithm="ES256",
        headers={"kid": os.environ["OPTIKPI_INAPP_KID"]},
    )
```

## 3. Store the private key in an environment variable

The key is a multi-line PEM, and many `.env` files and deploy tools can't hold line breaks. Put it on
one line with `\n` in place of each line break:

```bash
awk 'NF { printf "%s\\n", $0 }' optikpi-inapp-KID.pem
```

```bash
OPTIKPI_INAPP_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGH...\n-----END PRIVATE KEY-----\n"
```

Keep the double quotes. Both examples turn `\n` back into line breaks, and they work with a real
multi-line value too.

## 4. Refresh

Pass each new token to the SDK. In Flutter:

```dart
await OptikpiInApp.init(apiKey: apiKey, playerToken: token, baseUrl: baseUrl);  // login, restored session
OptikpiInApp.setPlayerToken(newToken);                                          // session refresh
```

When OptiKPI refuses a token, the SDK stops fetching and keeps its events until it gets a new one.
So keep the token alive for as long as your session, or refresh it when your app returns to the
foreground. Players see nothing when a token expires: pop-ups just stop until the next one.

## 5. Check it, then require it

To check a token, call the fetch API from your own machine:

```bash
curl -i "https://{dev|qa|app}.optikpi.com/apigw/v1/inapp/popups" \
  -H "Authorization: Bearer $API_KEY" -H "X-Player-Token: $TOKEN"
```

`200` means it is valid, and `403` means it was refused. A token that is sent is always verified. To
see why, compare it with the tables above.

While **Require player token** is off, requests with no token still work, so older app versions keep
running. Turn it on in **Settings → Security** once every live version of your app sends tokens:
requests without one are then refused.
