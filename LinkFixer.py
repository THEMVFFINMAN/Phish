# -*- coding: cp1252 -*-
import re

fileName = "ebay.html"
url = "Malicious URL"

fileR = open(fileName, "r")
match = re.sub(r'(?<=<a href=)(\s*)?"[^"]*', "\"Malicious Link", fileR.read())
match = re.sub('Â', '', match)
fileR.close()

fileW = open(fileName, "w")
fileW.write(match)
fileW.close()
