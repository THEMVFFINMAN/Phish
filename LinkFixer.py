import re

fileName = "local html source code"
url = "Malicious URL"

fileR = open(fileName, "r")
match = re.sub(r'(?<=<a href=")[^"]*', "Malicious Link", File.read())
fileR.close()

fileW = open(fileName, "w")
fileW.write(match)
fileW.close()
