import urllib.request
import urllib.parse
import json

NEWS_API_KEY = "a46c74aa3af14d13bdb56789d2c56bfb"
city = "Mumbai"
query_text = f"{city} flood OR heavy rain OR strike OR protest OR heatwave OR disaster"
query = urllib.parse.urlencode({
    "q": query_text,
    "sortBy": "publishedAt",
    "pageSize": 5,
    "language": "en",
    "apiKey": NEWS_API_KEY,
})
url = f"https://newsapi.org/v2/everything?{query}"
try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        payload = response.read().decode("utf-8")
        print(json.dumps(json.loads(payload), indent=2)[:1000])
except Exception as e:
    print("Error:", e)
