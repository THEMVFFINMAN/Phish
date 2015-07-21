# -*- coding: utf-8 -*-

import re, argparse, os

def validateFile(fileName):
    if not os.path.isfile(fileName):
        print '[-] ' + fileName + ' does not exist.'
        exit(0)
    if not os.access(fileName, os.R_OK):
        print '[-] ' + fileName + ' access denied.'
        exit(0)

def main():
    
    parser = argparse.ArgumentParser(description="An html email cleaner")
    parser.add_argument('-F', type=str, help="A file")
    args = parser.parse_args()
    fileName = args.F
    validateFile(fileName)

    url = "\"{LinkUrl}"

    fileR = open(fileName, "r")
    print "[+] Opened file: {0}".format(fileName)
    match = re.sub(r'(?<=<a href=)(\s*)?"[^"]*', url, fileR.read())
    print "[+] Replaced all URLs"
    match = re.sub('Â|\xAE|\xA9|\xC2', '', match)
    match = re.sub('•', '-', match)
    match = re.sub('“', '"', match)
    print "[+] Removed unneeded characters"
    fileR.close()

    fileW = open(fileName, "w")
    fileW.write(match)
    fileW.close()
    print "[+] Wrote file successfully"

if __name__ == "__main__":
    main()
