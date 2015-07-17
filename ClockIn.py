# A simple script to track my hours, will probably expand to do monthly totals, etc. 

import re, datetime

fileName = "C:\Users\josh\ownCloud\JJ\Timecard.csv"
times = ""


reg = raw_input('9 AM to 6 PM with an hour lunch? [Y|N]')
if reg == "Y" or reg == "y":
    times = ",900,1200,1300,1800,800"
else: 
    checkIn = raw_input('Check in: ')
    lunchBegin = raw_input('Lunch begin: ')
    lunchEnd = raw_input('Lunch end: ')
    checkOut = raw_input('Check out: ')
    total = int(checkOut) - (int(lunchEnd) - int(lunchBegin)) - int(checkIn)
    times = ",{0},{1},{2},{3},{4}".format(checkIn,lunchBegin,lunchEnd,checkOut,str(total))

def main(fileName):
    with open(fileName, "r") as punchCard:
        text = punchCard.read()
        updateTimeCard = re.sub(',,,,,0', times, text, 1)
        print "[+] Successfully found and replace date"
    with open(fileName, "w") as punchCard:
        punchCard.write(updateTimeCard)
        print "[+] Successfully wrote date"



def removeWeekend(fileName):
    text = ""
    with open(fileName, "r") as weekendRemover:
        for line in weekendRemover:
            split = line.split("/")
            split[2] = split[2][:4]
            split = map(int, split)
            if datetime.datetime(split[2],split[0],split[1]).weekday() != 5 and datetime.datetime(split[2],split[0],split[1]).weekday() != 6:
                text = text + line
    with open(fileName, "w") as weekendRemover:
        weekendRemover.write(text)

main(fileName)
