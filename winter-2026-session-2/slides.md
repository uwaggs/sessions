---
theme:
  name: terminal-dark
  override:
    default:
      colors:
        background: "141415"
        foreground: "cdcdcd"
      font_size: 20
---



# Web Scraping 102

Step 1: Learn BS4

Step 2: Forget everything you learned in Part 1

Step 3: This presentation

*(Just kidding. Kind of.)*


<!-- end_slide -->

# What is Web Scraping?

Automated extraction of data from websites (typically via "unorthodox" methods)

**Traditional approach:**
- Download HTML → Parse with BeautifulSoup/regex → Extract data

(We'll talk about why this might not be the best approach)

<!-- end_slide -->

# Legal Disclaimer

**Is web scraping legal?**

**Short answer:** It's complicated.

**General principles:**
- <span style="color: green">**Publicly accessible data** is generally fair game (but check ToS)</span>
- <span style="color: green">**Personal use, research, education** typically okay</span>
- <span style="color: red">**Commercial use** may violate Terms of Service</span>
- <span style="color: red">**Bypassing paywalls/auth, copyright infringement, etc...** = legal trouble</span>

**Important:** Read the website's Terms of Service and respect `robots.txt`


*I am not a lawyer. This is not legal advice. Do your own research.*



<!-- end_slide -->

# What This Talk Is NOT About

- <span style="color: red">Bypassing anti-bot protection (Cloudflare, reCAPTCHA, etc.)</span>
- <span style="color: red">Reverse engineering obfuscated JavaScript (or PHP)</span>
- <span style="color: red">Browser fingerprinting evasion</span>
- <span style="color: red">Headless browser detection bypass</span>
- <span style="color: red">Advanced techniques for hostile sites</span>

**If a site doesn't want to be scraped, this talk won't help you fight it.**

<!-- end_slide -->

# The Problem with HTML Parsing

```python
from bs4 import BeautifulSoup
import requests

response = requests.get('https://example.com/products')
soup = BeautifulSoup(response.text, 'html.parser')

# Parse the HTML structure
products = soup.find_all('div', class_='product-card')
```

**A list of Problems:**
- Figuring out how to parse can be a pain
- HTML structure changes with every redesign
- <span style="color: red">Dynamic loading stops us entirely</span>


**HTML parsing can work, but shouldn't be your first move.**


<!-- end_slide -->

## The Scenario

You see a beautiful page full of data in your browser.


<!-- pause -->

```python
soup = BeautifulSoup(response.text, 'html.parser')
products = soup.find_all('div', class_='product')
print(len(products))  # 0 🗿
```

<!-- pause -->

```python
print(response.text)
```

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Products</title>
    <script src="/bundle.js"></script>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

<!-- pause -->

**The data is loaded by JavaScript AFTER the page loads!**

<!-- end_slide -->

## The Scenario (cont)

<!-- pause -->


You saw the data in your browser. It's real. It exists.


<!-- pause -->

Your browser **requested** it from somewhere...


<!-- pause -->



<!-- end_slide -->

# Monitoring Network Requests

Most browsers have some networking monitoring tool. This typically includes lot's of info, including:
- Request headers (auth tokens, cookies, user-agent)
- Response headers (rate limits, content-type, cache-control, API version, CORS)
- Request payload (POST data, form submissions)
- Response payload (JSON, XML, HTML, etc...)
- Query parameters (pagination, filters, search)
- WebSocket messages (real-time data)


<!-- pause -->

# Useful Features

- You can block certain requests.
- You can look at local storage to see cached cookies.
- You can replay requests from the browser.
- It may be worth exporting all requests as an HAR, for faster parsing (since most browsers make it tricky to do more complex searches).


<!-- end_slide -->

# What You'll Typically Find

```http
GET /api/products?page=1&limit=20 HTTP/1.1
Host: <domain>

Response: 200 OK
{
  "data": [
    {"id": 1, "name": "Product 1", "price": 15},
    {"id": 2, "name": "Product 2", "price": 20}
  ],
  "total": 100,
  "page": 1
}
```

<!-- pause -->


<span style="color: green">**Clean, structured JSON!**</span>


<!-- pause -->

*This is what the site devs actually use. Why not you?*

<!-- end_slide -->

## Demo 1


<!-- pause -->

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// #   "beautifulsoup4",
/// # ]
/// # ///
import requests
from bs4 import BeautifulSoup

response = requests.get('http://localhost:4321/demo/demo-1')
soup = BeautifulSoup(response.text, 'html.parser')

matches = soup.find_all('tr')
print(matches)
```


<!-- end_slide -->

## Demo 1 (cont)

<!-- pause -->

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///
import requests

response = requests.get('http://localhost:4321/api/t1-results')
data = response.json()
first_match = data['data'][0]
print(first_match)
```

<!-- pause -->

For more complex examples, <span style="color: red">BS4 can be significantly more lines of code</span>.

If things break, this is <span style="color: red">more lines of code to fix.</span>



<!-- end_slide -->

## Demo 2: Query Parameters 

<!-- pause -->

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///
import requests

response = requests.get('http://localhost:4321/api/matches?winner=all&limit=1000')
data = response.json()
print(f"Total matches: {data['total']}")
```

<!-- end_slide -->

## Demo 2: Query Parameters (cont)

<!-- pause -->

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///
import requests

response = requests.get('http://localhost:4321/api/matches?winner=red&limit=1000')
data = response.json()
print(f"Red side wins: {data['total']}")
```

<!-- end_slide -->



# What about Authentication?

Suppose the data you want is behind a login page, and that you have valid credentials to log in.

<!-- pause -->

Is it time to use a headless browser like Selenium/Puppeteer?

<!-- pause -->

<span style="color: yellow">**Maybe not?**</span>

<!-- pause -->

We can try to just replicate the login flow with pure HTTP requests.

<span style="color: grey">*(Even more complex schemes like OAuth2 PKCE can be reverse-engineered from network monitoring!)*</span>

<!-- end_slide -->

# What about Authentication (cont)

<!-- pause -->

**Step 1:** Open network monitor and log in manually

<!-- pause -->

**Step 2:** Find the login request (usually POST to `/login`, `/auth`, `/api/authenticate`)

<!-- pause -->

**Step 3:** Check the request payload:
```json
{
  "username": "user@example.com",
  "password": "yourpassword"
}
```

<!-- pause -->

**Step 4:** Replicate:
```python
session = requests.Session()
login_data = {
    "username": "user@example.com",
    "password": "yourpassword"
}
response = session.post('https://example.com/api/login', json=login_data)
```

<!-- end_slide -->

# Post Authentication

Depending on the site's authentication scheme, you'll need to pass credentials with each request. The following are three common patterns:

## Session Cookies
```python
# Already handled by requests.Session()!
protected_data = session.get('https://example.com/api/protected')
```

## Bearer Tokens
```python
token = response.json()['access_token']
headers = {'Authorization': f'Bearer {token}'}
data = requests.get('https://example.com/api/protected', headers=headers)
```

## API Keys (similar to Bearer Tokens)
```python
headers = {'X-API-Key': 'your-api-key-here'}
data = requests.get('https://example.com/api/protected', headers=headers)
```

<!-- end_slide -->

## Demo 3: Session Cookies (Using Session Object)

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///

import requests

session = requests.Session()

session.post('http://localhost:4321/api/session/login',
             json={'username': 'demo', 'password': 'demo123'})

# Subsequent requests automatically include cookies
vods_response = session.get('http://localhost:4321/api/premium/team/geng')
data = vods_response.json()
print(data['available_vods'])
```

<!-- end_slide -->

## Demo 3 (cont): Session Cookies (Manual Extraction)

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///

import requests

login_response = requests.post('http://localhost:4321/api/session/login',
                               json={'username': 'demo', 'password': 'demo123'})
session_cookie = login_response.cookies.get('session_id')

vods_response = requests.get('http://localhost:4321/api/premium/team/geng',
                             cookies={'session_id': session_cookie})
data = vods_response.json()
print(data['available_vods'])
```

<!-- end_slide -->

## Demo 4: Bearer Token Authentication

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///

import requests

login_response = requests.post('http://localhost:4321/api/auth/login',
                               json={'username': 'demo', 'password': 'demo123'})
token = login_response.json()['access_token']

player_response = requests.get('http://localhost:4321/api/premium/player/chovy',
                               headers={'Authorization': f'Bearer {token}'})
data = player_response.json()
print(data['smurf_account_matches'])
```

<!-- end_slide -->

# Finding Hidden APIs

Sometimes APIs aren't visible in XHR/Fetch requests.

You need to be **resourceful** and look for **information leakage**.

<!-- end_slide -->

## Technique 1: Response Headers

Check response headers on the HTML document request:

```http
x-powered-by: Some Company <https://company.com>
link: <https://company.ca/wp-json/>; rel="https://company.w.org/"
```

**The `link` header reveals an undocumented API endpoint!**

Other useful headers: `x-api-version`, `x-powered-by`

**Common in:** Server-side rendered (SSR) applications

<!-- end_slide -->

## Demo 5: Response Headers


```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///

import requests
import re

response = requests.get('http://localhost:4321/demo/headers', headers={'X-Team-Id': 'cloud9'})
link_header = response.headers.get('Link')
api_url = re.search(r'<(.+?)>', link_header).group(1)
print(api_url)

roster_response = requests.get(api_url)
roster_data = roster_response.json()
coach = next(member['player'] for member in roster_data['data'] if member['position'] == 'Coach')
print(f"Cloud9 Coach is: {coach}")
```

<!-- end_slide -->


## Demo 5: Response Headers (cont)


```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "requests",
/// # ]
/// # ///

import requests
import re

response = requests.get('http://localhost:4321/demo/headers', headers={'X-Team-Id': 't1'})
link_header = response.headers.get('Link')
api_url = re.search(r'<(.+?)>', link_header).group(1)
print(api_url)

roster_response = requests.get(api_url)
roster_data = roster_response.json()
coach = next(member['player'] for member in roster_data['data'] if member['position'] == 'Coach')
print(f"T1 Coach is: {coach}")
```

<!-- end_slide -->



## Technique 2: URL Pattern Inference

Found `/api/2025/basketball`? Try:
- `/api/2025/football`
- `/api/2024/basketball`
- `/api/2026/basketball`

Found `/api/v1/users`? Try:
- `/api/v2/users`
- `/api/v1/products`
- `/api/v1/orders`

**Look for patterns and extrapolate!**

<!-- end_slide -->

## Technique 3: Parameter Testing

Found `?page=1`? Try:
- `?limit=9999` (might bypass pagination limits)
- `?page=all`
- `?offset=0&limit=1000`

Found `?sport=basketball`? Try:
- `?sport=football`
- `?sport=all`
- Enumerate all possible values

**Test the boundaries!**


<!-- end_slide -->

## Technique 4: Documentation Endpoints

Try common documentation URLs:
- `/api/docs`
- `/swagger`
- `/swagger.json`
- `/openapi.json`
- `/graphql` (with introspection query)
- `/api-docs`


<!-- end_slide -->

## Technique 5: Error Messages

Verbose error messages can leak API structure:

```json
{
  "error": "Endpoint /api/v3/users not found",
  "suggestion": "Did you mean /api/v4/users?"
}
```

**Pay attention to 404 responses!**

<!-- end_slide -->

# Some Things to Consider

## Rate Limiting
- APIs often limit requests (e.g., 100/minute)
- Add delays: `time.sleep(1)`
- Check response headers for rate limit info: `X-RateLimit-Remaining`

## CSRF Tokens
- Some sites require a token from the page before POST requests
- Extract from HTML or initial API call, include in subsequent requests

## User-Agent Requirements
- Some APIs block requests without proper User-Agent headers
- Copy from browser: `headers = {'User-Agent': 'Mozilla/5.0...'}`

<!-- end_slide -->

# One More Thing: WebSockets & Real-Time Data

Not all data comes through traditional HTTP requests.

**Real-time data** (live scores, chat messages, stock prices) often uses **WebSockets**.


<!-- end_slide -->

## Demo 6: WebSockets

```python +exec:uv
/// # /// script
/// # requires-python = ">=3.11"
/// # dependencies = [
/// #   "websocket-client",
/// # ]
/// # ///

import json
from websocket import create_connection

WS_URL = "ws://localhost:4321/ws/live-chat"
ws = create_connection(WS_URL)
t1_count = 0

try:
    while True:
        message = ws.recv()
        data = json.loads(message)

        if data.get('type') == 'complete':
            break

        if data.get('team') == 'T1':
            t1_count += 1

except KeyboardInterrupt:
    pass
finally:
    ws.close()
    print(f"T1 mentions: {t1_count}")
```

<!-- end_slide -->

# Scrape Responsibly

**With great power comes great responsibility.**

## Best Practices:

**Respect Rate Limits**
- Add delays between requests (`time.sleep()`)
- Don't hammer servers with rapid-fire requests
- Check for and honor `X-RateLimit-*` headers

**Cache Aggressively**
- Don't re-request data you already have
- Save responses locally when appropriate

**Honour robots.txt**
- Respect crawl policies
- Don't scrape what you're explicitly told not to

**Be a Good Citizen**
- Stop immediately if you receive a cease & desist


<span style="color: red">**Remember: Someone is paying for the bandwidth and server resources you're using.**</span>


<!-- end_slide -->

# Questions?


<!-- end_slide -->

I'll be around after if you want to talk about...

### More Scraping

- <span style="color: yellow">Bypassing bot detection</span>
- <span style="color: yellow">Reverse engineering authentication schemes</span>
- <span style="color: green">Agentic scraping</span>
- <span style="color: green">Scraping at scale</span>

(I only said I wouldn't cover these in the talk.)

### Other Things
- Systems Engineering
- Performance optimization & profiling
- Mathematical optimization
- League of Legends Analytics

