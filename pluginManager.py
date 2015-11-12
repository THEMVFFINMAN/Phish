import requests
import re

def get_java():
    r = requests.get("https://java.com/en/download/")
    match = re.search(r"Version [0-9]+ Update [0-9]+", r.text, re.M|re.I)
    java_version = [int(s) for s in match.group().split() if s.isdigit()]

    return "Java: 1.{}.0.{}".format(java_version[0], java_version[1])

def get_adobe():
    r = requests.get("http://www.adobe.com/support/downloads/product.jsp?platform=windows&product=10")
    matches = re.findall(r"Version [0-9]+\.[0-9]+\.[0-9]+", r.text, re.M|re.I)

    for match in matches:
        if "2015" in match or "2016" in match:
            continue
        else:
            return "Adobe Reader: {}".format(match[8:])

def get_flash():
    r = requests.get("https://www.adobe.com/support/flashplayer/debug_downloads.html")
    match = re.search(r"The latest versions are [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", r.text, re.M|re.I)
    
    return "Flash: {}".format(match.group()[24:])

def get_shockwave():
    r = requests.get("https://get.adobe.com/shockwave/")
    match = re.search(r"Version [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", r.text, re.M|re.I)
    
    return "Shockwave: {}".format(match.group()[8:])

def get_vlc():
    r = requests.get("http://www.videolan.org/index.html")
    match = re.search(r"latestVersion = \'[0-9]+\.[0-9]+\.[0-9]+", r.text, re.M|re.I)
    
    return "VLC: {}".format(match.group()[17:])

def get_quicktime():
    user_agent = {'User-Agent': 'Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.80 Safari/537.36'}
    r = requests.get("https://www.google.com/search?safe=active&es_sm=93&q=quicktime+latest+version&oq=quicktime+latest+version&gs_l=serp.3..35i39j0l2j0i20j0l3j0i20j0.5045.7337.0.7473.24.22.0.0.0.0.163.2639.4j18.22.0....0...1c.1.64.serp..2.22.2636.fyZRynnw3y0", headers=user_agent)
    match = re.search(r"QuickTime [0-9]+\.[0-9]+\.[0-9]+", r.text, re.M|re.I)

    return "QuickTime: {}".format(match.group()[10:])

def get_realplayer():
    r = requests.get("http://realplayer.en.downloadastro.com/old_versions/")
    match = re.findall(r"Program Version [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+", r.text, re.M|re.I)
    
    return "RealPlayer: {}".format(match[1][16:])

def main():

    print get_adobe()
    print get_flash()
    print get_java()
    print get_quicktime()
    print get_realplayer()
    print get_shockwave()
    print get_vlc()

    raw_input()
    

if __name__ == "__main__":
    main()
