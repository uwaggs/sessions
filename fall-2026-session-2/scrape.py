import asyncio
import hashlib
import json
import re
import time
from concurrent.futures import ThreadPoolExecutor
from io import StringIO
from pathlib import Path
from urllib.parse import urlparse

import lxml.html
import pandas as pd
from curl_cffi import requests

# ==========================================
# Downloading pages (with a cache)
# ==========================================
# Sports-reference sites ban you for an hour if you make more than ~20
# requests a minute, so every page we download is saved in cache/.
# If a page is already in the cache we never ask the website again.

HERE = Path(__file__).parent
CACHE_DIR = HERE / "cache"
SNAPSHOT_DIR = HERE / "snapshots"
COOKIE_FILE = CACHE_DIR / "cookies.json"
CACHE_DIR.mkdir(exist_ok=True)


def page_filename(url):
    """Turn a URL into a safe file name, e.g. hockey-reference.com_a1b2c3d4.html"""
    domain = urlparse(url).netloc.replace("www.", "")
    url_hash = hashlib.md5(url.encode()).hexdigest()[:10]
    return f"{domain}_{url_hash}.html"


def fetch_page(url):
    """Return the HTML for a page: cache -> website -> saved snapshot."""
    filename = page_filename(url)

    # 1. Already downloaded it before? Use that.
    for folder in [CACHE_DIR, SNAPSHOT_DIR]:
        if (folder / filename).exists():
            return (folder / filename).read_text()

    # 2. Download it from the website.
    html = download(url)
    (CACHE_DIR / filename).write_text(html)
    return html


def download(url):
    domain = urlparse(url).netloc
    cookies, user_agent = load_cookies(domain)
    headers = {"User-Agent": user_agent} if user_agent else {}

    response = requests.get(url, impersonate="chrome", cookies=cookies, headers=headers, timeout=30)

    # fbref and pro-football-reference sit behind a Cloudflare "Just a moment..."
    # check. A real Chrome window passes it, then we reuse its cookies.
    if response.status_code == 403 and "Just a moment" in response.text:
        cookies, user_agent = pass_cloudflare_check(url)
        response = requests.get(url, impersonate="chrome", cookies=cookies,
                                headers={"User-Agent": user_agent}, timeout=30)

    if response.status_code == 429:
        raise RuntimeError("Rate limited by the site (too many requests). Wait a bit, or use a cached team.")
    if response.status_code != 200:
        raise RuntimeError(f"Couldn't load the page (HTTP {response.status_code}). Check the link?")

    time.sleep(1)  # be polite
    return response.text


# ==========================================
# Getting past Cloudflare (you can ignore this part)
# ==========================================

def load_cookies(domain):
    if not COOKIE_FILE.exists():
        return {}, None
    saved = json.loads(COOKIE_FILE.read_text()).get(domain, {})
    return saved.get("cookies", {}), saved.get("user_agent")


def save_cookies(domain, cookies, user_agent):
    saved = json.loads(COOKIE_FILE.read_text()) if COOKIE_FILE.exists() else {}
    saved[domain] = {"cookies": cookies, "user_agent": user_agent}
    COOKIE_FILE.write_text(json.dumps(saved, indent=2))


def pass_cloudflare_check(url):
    """Open a real (off-screen) Chrome window, let it pass the check, keep its cookies."""
    # nodriver needs its own event loop, so run it in a separate thread.
    with ThreadPoolExecutor(max_workers=1) as pool:
        cookies, user_agent = pool.submit(asyncio.run, _browser_visit(url)).result()
    save_cookies(urlparse(url).netloc, cookies, user_agent)
    return cookies, user_agent


async def _browser_visit(url):
    import nodriver as uc

    browser = await uc.start(headless=False, browser_args=["--window-position=-3000,-3000", "--window-size=800,600"])
    try:
        page = await browser.get(url)
        for _ in range(20):
            await asyncio.sleep(1.5)
            if "Just a moment" not in (await page.get_content())[:3000]:
                break
        else:
            raise RuntimeError("Couldn't get past Cloudflare. Is Google Chrome installed?")
        user_agent = await page.evaluate("navigator.userAgent")
        domain = urlparse(url).netloc.replace("www.", "")
        cookies = {c.name: c.value for c in await browser.cookies.get_all() if domain in c.domain}
    finally:
        browser.stop()
    return cookies, user_agent


# ==========================================
# Turning a page into tables
# ==========================================

def get_tables(html):
    """Return every table on the page as {table_id: DataFrame}."""
    # Sports-reference hides some tables inside HTML comments <!-- -->. Un-hide them.
    html = html.replace("<!--", "").replace("-->", "")

    tables = {}
    for table in lxml.html.fromstring(html).xpath("//table[@id]"):
        try:
            table_html = lxml.html.tostring(table, encoding="unicode")
            df = pd.read_html(StringIO(table_html), flavor="lxml", extract_links="body")[0]
        except (ValueError, ImportError):
            continue  # not a normal data table; skip it
        tables[table.get("id")] = clean_table(df)
    return tables


def clean_table(df):
    # Some tables have two header rows, e.g. "Rushing / Yds" and "Receiving / Yds".
    # Keep the bottom name, and add the top name when the bottom one repeats.
    if isinstance(df.columns, pd.MultiIndex):
        names = []
        for top, bottom in df.columns:
            if bottom in names and not str(top).startswith("Unnamed"):
                names.append(f"{top} {bottom}")
            else:
                names.append(bottom)
        df.columns = names
    df.columns = make_unique([str(c) for c in df.columns])

    # extract_links gives (text, link) pairs. Keep the text, but save the
    # link to each player's page in a "link" column.
    links = None
    for col in df.columns:
        if df[col].map(lambda cell: isinstance(cell, tuple) and bool(cell[1]) and "/players/" in cell[1]).any():
            links = df[col].map(lambda cell: cell[1] if isinstance(cell, tuple) else None)
            break
    df = df.apply(lambda col: col.map(lambda cell: cell[0] if isinstance(cell, tuple) else cell))
    if links is not None:
        df["link"] = links

    # Drop repeated header rows that sports-reference sprinkles in the middle.
    first = df.columns[0]
    df = df[df[first].astype(str) != first]

    # Remove award markers from names, e.g. "Vladimir Guerrero Jr.*" -> "Vladimir Guerrero Jr."
    if "Player" in df.columns:
        df["Player"] = df["Player"].astype(str).str.rstrip("#*+ ")

    # Turn number-looking columns into actual numbers.
    for col in df.columns:
        as_numbers = pd.to_numeric(df[col].astype(str).str.replace(",", "").str.rstrip("%"), errors="coerce")
        if as_numbers.notna().sum() >= 0.8 * df[col].notna().sum() and as_numbers.notna().any():
            df[col] = as_numbers
    return df.reset_index(drop=True)


def make_unique(names):
    seen = {}
    result = []
    for name in names:
        if name in seen:
            seen[name] += 1
            result.append(f"{name}_{seen[name]}")
        else:
            seen[name] = 0
            result.append(name)
    return result


def get_page_title(html):
    match = re.search(r"<title>(.*?)</title>", html)
    return match.group(1).split("|")[0].strip() if match else ""


def get_team_record(html):
    """Find e.g. 'Record: 45-26-11' in the page header. Returns '' if not found."""
    match = re.search(r"<strong>Record:</strong>\s*([^<]+)", html)
    return match.group(1).split(",")[0].strip() if match else ""
