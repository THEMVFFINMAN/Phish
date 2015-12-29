import mechanize
import cookielib
import re
import operator
from bs4 import BeautifulSoup
from sets import Set
from datetime import datetime

username = "xxxx"
password = "xxxx"
login = "https://xxxxxxx.com/admin/security"
campaigns = "https://xxxxxxx.com/admin/campaign/list"
templates = "https://xxxxxxx.com/admin/emailtemplate"

attacks = dict()
companies = dict()
templates = set()


class Attack:
    sent_emails = 0
    opened_emails = 0
    clicked_emails = 0


class Company:
    attacks = set()
    name = ""
    campaign_link = ""
    next_attack_date = datetime(3000, 12, 12)
    is_pending = False
    training_started = 0
    training_completed = 0
    clicked = 0
    opened = 0
    sent = 0

    def __init__(self, pname):
        self.attacks = set()
        name = pname


def setup():
    # Browser and Cookie Jar
    br = mechanize.Browser()
    cj = cookielib.LWPCookieJar()
    br.set_cookiejar(cj)

    # Browser Options
    br.set_handle_equiv(True)
    br.set_handle_redirect(True)
    br.set_handle_referer(True)
    br.set_handle_robots(False)

    # Debugging Messages
    # br.set_debug_http(True)
    # br.set_debug_redirects(True)
    # br.set_debug_responses(True)

    # User-Agent
    br.addheaders = [('User-agent', 'Mozilla/5.0 (X11; U; Linux i686; \
    en-US; rv:1.9.0.1) Gecko/2008071615 Fedora/3.0.1-1.fc9 Firefox/3.0.1')]

    # Log in
    br.open(login)
    br.select_form(nr=0)
    br.form["Username"] = username
    br.form["Password"] = password
    br.submit()

    print "[+] Successfully logged in"

    return br


def populate_templates(br):
    r = br.open("https://xxxxxxx.com/admin/emailtemplate")

    try:
        # This leaves room for approximately 400 templates
        for i in range(0, 20):

            # Select the records using the bar on the top right
            br.select_form(nr=0)
            br.form["SearchCriteria.Page"] = [str(i), ]
            br.submit()
            r = br.open("https://xxxxxxx.com/admin/emailtemplate")

            # Get the gridrows
            text = r.read().replace("\"/", "https://xxxxxxx.com/")
            soup = BeautifulSoup(text, "html.parser")
            table_values = soup.find_all("tr", {"class": "gridrow"})
            table_values = table_values + \
                soup.find_all("tr", {"class": "gridrow_alternate"})

            # Find and store the correct values
            for value in table_values:
                value = str(value)
                matches = re.findall(r"<td>.*</td><td></td>", value, re.M|re.I)
                if matches:
                    attack_template = matches[0][4:len(matches[0])-14]
                    templates.add(attack_template)
    except:
        print "[+] Gathered up templates"
        return


def initialize_attack_statistics():
    for template in templates:
        attacks[template] = Attack()

    print "[+] Attack statistics initialized"


def print_attack_data():
    for key in attacks:
        print "Attack: {}".format(key)
        print "Sent Emails: {}".format(attacks[key].sent_emails)
        print "Opened Emails: {}".format(attacks[key].opened_emails)
        print "Clicked Emails: {}".format(attacks[key].clicked_emails)


def print_companies():
    for company_name in companies:
        print "Company name: {0}".format(company_name)
        date = companies[company_name].next_attack_date

        if date.year == 3000:
            print "Next Attack: {0}\n".format("Needs new Campaign")
        else:
            print "Next Attack: {0}\n".format(
                companies[company_name].next_attack_date)

        print "Attacks:"
        for attack in companies[company_name].attacks:
            print attack

        print "\n"


def export_to_html():
    dirty_html = ""

    begin = """
<!DOCTYPE html>
<html>
<head>
<title>PhishThreat Dashboard</title>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.3/jquery.min.js">
</script>
<script src="sortable.js"></script>
<style>
select {
  background-color: #507FB3;
  color: #F0F9FC;
  font-size: 14px;
}
a {
    color: white;
}
</style>
</head>
<body style="background-color:#0151AB">
<center>
<h1 style="color:#ffb7b9;text-decoration: underline;">
Customer Campaigns
</h1>
</center>
<table border= "1" class="sortable" align="center" style="color:#F0F9FC;font-size:19px">
<tr style="font-weight:bold; font-size:24px; text-decoration:underline; color: #FFEFCC">
<td>Name</td>
<td>Next Attack</td>
<td>Used Templates</td>
<td>Available Templates</td>
</tr>
"""
    dirty_html += begin

    for company_name in companies:
        company = companies[company_name]
        if company.is_pending:
            dirty_html += '<tr>\n<td><a href="{0}">[PENDING] {1}</a></td>'.format(company.campaign_link, company_name)
        else:
            dirty_html += '<tr>\n<td><a href="{0}">{1}</a></td>'.format(company.campaign_link, company_name)

        if company.next_attack_date.year == 3000:
            dirty_html += "<td>{0}</td>".format("Needs New Campaign")
        else:
            dirty_html += "<td>{0}</td>".format(company.next_attack_date)

        dirty_html += "<td><select>"
        for attack in company.attacks:
            dirty_html += '<option value="{0}">{0}</option>'.format(attack)
        dirty_html += "</select></td>"

        new_attacks = sorted(templates - company.attacks)
        dirty_html += "<td><select>"
        for attack in new_attacks:
            dirty_html += '<option value="{0}">{0}</option>'.format(attack)
        dirty_html += "</select></td>"

    attack_table = """
</table><br>
<center><h1 style="color:#ffb7b9;text-decoration: underline;">Attack Statistics</h1></center>
<table border= "1" class="sortable" align="center" style="color:#F0F9FC;font-size:19px">
<tr style="font-weight:bold; font-size:22px; text-decoration:underline; color: #FFEFCC">
<td>Attack</td>
<td>Sent</td>
<td>Open</td>
<td>Click</td>
<td>Click/Sent</td>
<td>Open/Sent</td>
<td>Click/Open</td>
</tr>
"""
    dirty_html += attack_table

    # This and the other data tables are written like this for readability reasons only
    for key in attacks:
        attack = attacks[key]
        attack_statistics = ""
        if attack.sent_emails != 0:
            attack_statistics += "<tr>\n<td>{}</td>\n".format(key)
            attack_statistics += '<td align="right">{}</td>\n'.format(attack.sent_emails)
            attack_statistics += '<td align="right">{}</td>\n'.format(attack.opened_emails)
            attack_statistics += '<td align="right">{}</td>\n'.format(attack.clicked_emails)
            attack_statistics += '<td align="right">{:.1%}</td>\n'.format(float(attack.clicked_emails)/float(attack.sent_emails))
            attack_statistics += '<td align="right">{:.1%}</td>\n'.format(float(attack.opened_emails)/float(attack.sent_emails))
            attack_statistics += '<td align="right">{:.1%}</td>\n</tr>'.format(float(attack.clicked_emails)/float(attack.opened_emails))

            dirty_html += attack_statistics

    customer_stat_table = """
</table><br>
<center><h1 style="color:#ffb7b9;text-decoration: underline;">Customer Statistics</h1></center>
<table border= "1" class="sortable" align="center" style="color:#F0F9FC;font-size:19px">
<tr style="font-weight:bold; font-size:19px; text-decoration:underline; color: #FFEFCC">
<td>Name</td>
<td>Sent</td>
<td>Open</td>
<td>Click</td>
<td>Click/Sent</td>
<td>Open/Sent</td>
<td>Click/Open</td>
<td>Start/Click</td>
<td>Comp/Start</td>
<td>Comp/Click</td>
</tr>
"""
    dirty_html += customer_stat_table

    for company_name in companies:
        company = companies[company_name]
        customer_statistics = ""
        customer_statistics += "<tr>\n<td>{}</td>\n".format(company_name)
        customer_statistics += '<td align="right">{}</td>\n'.format(company.sent)
        customer_statistics += '<td align="right">{}</td>\n'.format(company.opened)
        customer_statistics += '<td align="right">{}</td>\n'.format(company.clicked)
        customer_statistics += '<td align="right">{:.1%}</td>\n'.format(float(company.clicked)/float(company.sent))
        customer_statistics += '<td align="right">{:.1%}</td>\n'.format(float(company.opened)/float(company.sent))
        customer_statistics += '<td align="right">{:.1%}</td>\n'.format(float(company.clicked)/float(company.opened))
        customer_statistics += '<td align="right">{:.1%}</td>\n'.format(float(company.training_started)/float(company.clicked))
        customer_statistics += '<td align="right">{:.1%}</td>\n'.format(float(company.training_completed)/float(company.training_started))
        customer_statistics += '<td align="right">{:.1%}</td>\n</tr>'.format(float(company.training_completed)/float(company.clicked))

        dirty_html += customer_statistics

    end = """
</table>
</body>
</html>
"""
    dirty_html += end

    soup = BeautifulSoup(dirty_html, "html.parser")
    pretty_html = soup.prettify()
    html_file = open("dashboard.html", "w")
    html_file.write(pretty_html)
    html_file.close()

    print "[+] Exported to HTML"


def get_campaigns(br):
    r = br.open(campaigns)

    # First check all active campaigns
    text = r.read().replace("\"/", "https://xxxxxxx.com/")
    matches = re.findall(r"(/admin/campaign/landing/([A-Z]|[0-9]|[a-z])*)", text, re.M|re.I)

    x = 0
    for match in matches:
        x = x + 1
        get_comp_camp_data(br, "https://xxxxxxx.com" + match[0], True, False)
        print "[+] Analyzing active campaign {0}".format(x)

    print "[+] Gathered active campaign data"

    # Check the pending campaigns
    br.open(campaigns)
    br.select_form(nr=0)
    br.form["SearchCriteria.Status"] = ["P", ]
    br.submit()

    r = br.open(campaigns)

    # Find each company's link
    text = r.read().replace("\"/", "https://xxxxxxx.com/")
    matches = re.findall(r"(/admin/campaign/landing/([A-Z]|[0-9]|[a-z])*)", text, re.M|re.I)

    x = 0
    for match in matches:
        x = x + 1
        get_comp_camp_data(br, "https://xxxxxxx.com" + match[0], False, True)
        print "[+] Analyzing pending campaign {0}".format(x)

    print "[+] Gathered pending campaign data"

    # Check the completed campaigns
    br.open(campaigns)
    br.select_form(nr=0)
    br.form["SearchCriteria.Status"] = ["C", ]
    br.submit()

    r = br.open(campaigns)

    # Find each company's link
    text = r.read().replace("\"/", "https://xxxxxxx.com/")
    matches = re.findall(r"(/admin/campaign/landing/([A-Z]|[0-9]|[a-z])*)", text, re.M|re.I)

    x = 0
    for match in matches:
        x = x + 1
        get_comp_camp_data(br, "https://xxxxxxx.com" + match[0], False, False)
        print "[+] Analyzing complete campaign {0}".format(x)

    print "[+] Gathered completed campaign data"


def get_comp_camp_data(br, url, is_active, is_pending):
    r = br.open(url)
    company_name = ""

    text = r.read()

    soup = BeautifulSoup(text, "html.parser")

    # Removes trial campaigns
    if "Assessment" in text or "Test" in text or "Show" in text:
        return

    data_values = soup.find_all('p')

    attack_name = ""

    for value in data_values:
        valid_date = False
        value = str(value)

        if "Customer" in value:
            old_company_name = company_name
            company_name = value[86:len(value)-12]

            if "Hacme" not in company_name and "value\"" not in company_name:
                if company_name not in companies:
                    new_company = Company(company_name)
                    companies[company_name] = new_company
            else:
                if not old_company_name == "":
                    company_name = old_company_name
        elif "Email Template" in value:
            attack_name = value[92:len(value)-12]
        elif "Sent Emails" in value:
            sent_emails = int(value[89:len(value)-12])
            attacks[attack_name].sent_emails += sent_emails
            companies[company_name].sent += sent_emails
        elif "Opened Emails" in value:
            opened_emails = int(value[91:len(value)-12])
            attacks[attack_name].opened_emails += opened_emails
            companies[company_name].opened += opened_emails
        elif "Clicked Emails" in value:
            clicked_emails = int(value[92:len(value)-12])
            attacks[attack_name].clicked_emails += clicked_emails
            companies[company_name].clicked += clicked_emails
        elif "Training Started" in value:
            training_started = re.search(r"[0-9]+(?= \(([0-9]*)(\.*)([0-9]*)%\))", value, re.M|re.I)
            companies[company_name].training_started += int(training_started.group())
        elif "Training Completed" in value:
            training_completed = re.search(r"[0-9]+(?= \(([0-9]*)(\.*)([0-9]*)%\))", value, re.M|re.I)
            companies[company_name].training_completed += int(training_completed.group())

        if (is_active or is_pending) and "Start Date/Time" in value:
            match = re.findall(r"[0-9]+\/[0-9]+\/[0-9]+ [0-9]+:[0-9]+ [A-Z]+", str(value), re.M|re.I)

            attack_date = match[0]
            attack_date = datetime.strptime(attack_date, "%m/%d/%Y %H:%M %p")

            valid_date = attack_date > datetime.now()
            closest_attack = attack_date < companies[company_name].next_attack_date

            if valid_date and closest_attack:
                companies[company_name].next_attack_date = attack_date

        if "Email Template" in value and "Hacme" not in company_name:
            attack_name = value[92:len(value)-12]
            companies[company_name].attacks.add(attack_name)

    if is_active or is_pending:
        companies[company_name].campaign_link = url

    if is_pending:
        companies[company_name].is_pending = True


def main():
    br = setup()
    populate_templates(br)
    initialize_attack_statistics()
    get_campaigns(br)
    # print_companies()
    # print_attack_data()
    export_to_html()

if __name__ == "__main__":
    main()
