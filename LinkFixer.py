import re

fileName = "amazon.html"
url = "Malicious URL"

fileR = open(fileName, "r")
match = re.sub(r'(?<=<a href=)(\s*)?"[^"]*', "\"Malicious Link", fileR.read())
fileR.close()

fileW = open(fileName, "w")
fileW.write(match)
fileW.close()
