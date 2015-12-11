import mechanize
import cookielib
import re
from bs4 import BeautifulSoup
from sets import Set

username = "XXXX"
password = "XXXX"
login = "https://xxxxxxx.com/admin/security"
campaigns = "https://xxxxxxx.com/admin/campaign/list"
templates = "https://xxxxxxx.com/admin/emailtemplate"

companies = dict()
templates = set()

class Company:
    attacks = set()
    name = ""
    next_attack_date = ""
    
    def __init__(self, pname):
        self.attacks = set()
        name = pname

def setup():
    #Browser and Cookie Jar
    br = mechanize.Browser()
    cj = cookielib.LWPCookieJar()
    br.set_cookiejar(cj)

    #Browser Options
    br.set_handle_equiv(True)
    br.set_handle_redirect(True)
    br.set_handle_referer(True)
    br.set_handle_robots(False)

    #Debugging Messages
    #br.set_debug_http(True)
    #br.set_debug_redirects(True)
    #br.set_debug_responses(True)

    #User-Agent
    br.addheaders = [('User-agent', 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.1) Gecko/2008071615 Fedora/3.0.1-1.fc9 Firefox/3.0.1')]

    #Log in
    br.open(login)
    br.select_form(nr=0)
    br.form["Username"] = username
    br.form["Password"] = password
    br.submit()

    return br

def populate_templates(br):
    r = br.open("https://xxxxxxx.com/admin/emailtemplate")

    try:
        #This leaves room for approximately 400 templates
        for i in range(0, 20):
            
            #Select the records using the bar on the top right
            br.select_form(nr=0)
            br.form["SearchCriteria.Page"] = [str(i),]
            br.submit()
            r = br.open("https://xxxxxxx.com/admin/emailtemplate")

            #Get the gridrows
            text = r.read().replace("\"/", "https://xxxxxxx.com/")
            soup = BeautifulSoup(text, "html.parser")
            table_values = soup.find_all("tr", {"class":"gridrow"})
            table_values = table_values + soup.find_all("tr", {"class":"gridrow_alternate"})

            #Find and store the correct values
            for value in table_values:
                value = str(value)
                matches = re.findall(r"<td>.*</td><td></td>", value, re.M|re.I)
                if matches:
                    attack_template = matches[0][4:len(matches[0])-14]
                    templates.add(attack_template)
    except:
        return

def print_companies():
    for company_name in companies:
        print "Company name: {0}\n".format(company_name)
        print "Attacks:"
        for attack in companies[company_name].attacks:
            print attack

        print "\n"

def get_campaigns(br):
    r = br.open(campaigns)

    #First check all active campaigns
    text = r.read().replace("\"/", "https://xxxxxxx.com/")
    matches = re.findall(r"(/admin/campaign/landing/([A-Z]|[0-9]|[a-z])*)", text, re.M|re.I)
    
    for match in matches:
        get_comp_camp_data(br, "https://xxxxxxx.com" + match[0])
    
    #Check the completed campaigns
    br.open(campaigns)
    br.select_form(nr=0)
    br.form["SearchCriteria.Status"] = ["C",]
    br.submit()
    
    r = br.open(campaigns)

    #Find each company's link
    text = r.read().replace("\"/", "https://xxxxxxx.com/")
    matches = re.findall(r"(/admin/campaign/landing/([A-Z]|[0-9]|[a-z])*)", text, re.M|re.I)
    
    for match in matches:
        get_comp_camp_data(br, "https://xxxxxxx.com" + match[0])

    print_companies()

def get_comp_camp_data(br, url):
    r = br.open(url)
    company_name = ""

    text = r.read()

    soup = BeautifulSoup(text, "html.parser")

    # Removes trial campaigns
    if "Assessment" in text or "Test" in text or "Show" in text:
        return
    
    data_values = soup.find_all('p')

    for value in data_values:
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

        if "Email Template" in value and "Hacme" not in company_name:
            attack_name = value[92:len(value)-12]
            companies[company_name].attacks.add(attack_name)    

def main():
    br = setup()
    #populate_templates(br)
    get_campaigns(br)
    print_companies()

if __name__ == "__main__":
    main()
