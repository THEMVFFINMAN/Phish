# -*- coding: utf-8 -*-

import re

fileName = "24hourfitness.html"
url = "Malicious URL"

fileR = open(fileName, "r")
match = re.sub(r'(?<=<a href=)(\s*)?"[^"]*', "\"Malicious Link", fileR.read())
match = re.sub('Â|\xAE|\xA9', '', match)

fileR.close()

fileW = open(fileName, "w")
fileW.write(match)
fileW.close()
