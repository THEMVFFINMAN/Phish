from os import listdir, remove
from os.path import isfile, join, exists
from subprocess import Popen, PIPE, check_output, call
import string
import subprocess
import Queue
import time
import sqlite3 as lite
import sys

path_to_watch = "C:/Users/JJ/Desktop/hashcat"
db_filename = "password_files.db"
table_name = "files_db"
ocl_hash_dir = "C:\Users\JJ\Downloads\cudaHashcat-1.37\cudaHashcat-1.37\\"
ocl_file = "cudaHashcat64.exe"
rock_you = "passwordFiles\\rockyou.txt"

sleep = 10
queue = Queue.Queue()
cracking = False

def setup_database():
    remove(db_filename)
    db_is_new = not exists(db_filename)
    conn = lite.connect(db_filename)
    c = conn.cursor()

    c.execute('''CREATE TABLE IF NOT EXISTS {}
            (file TEXT UNIQUE, type TEXT, status TEXT)'''.format(table_name))

    print "[+] Connected to Table {} Successfully".format(table_name)

    return c, conn


def get_files():
    fonly_files = [f for f in listdir(path_to_watch) if isfile(join(path_to_watch,f))]

    for i in range(len(fonly_files)):
        fonly_files[i] = fonly_files[i].split(".")

    return fonly_files


def insert(c):
    only_files = get_files()

    for file in only_files:
        try:
            if file[1] == "ntlm" or file[1] == "netntlm":
                c.execute("INSERT OR IGNORE INTO {} VALUES('{}','{}','{}')".format(table_name, file[0], file[1], "new"))
        except:
            continue

        
def print_database(c):        
    c.execute('SELECT * FROM {}'.format(table_name))
    result = c.fetchall()

    for row in result:
        print "[+] File: {:20s} Ext: {:10s} Status: {}".format(row[0], row[1], row[2])


def update_value(c, change, original):
    c.execute('UPDATE {} SET status="{}" WHERE status="{}"'.format(table_name, change, original))


def queue_files(c):
    c.execute('SELECT * FROM {} where status = "new"'.format(table_name))
    result = c.fetchall()

    if result:
        for row in result:
            queue.put((row[0],row[1]))

        print "[+] Added File: {:20s} Ext: {:10s} Status: {}".format(row[0], row[1], row[2])

        update_value(c, "queued", "new")

def wait():
    print "[+] Sleeping for {} seconds".format(sleep)
    time.sleep(sleep)


def cracker_jack():
    top = queue.get()
    print "[+] Starting crack on {}.{}".format(top[0], top[1])
    
    if top[1] == "ntlm":
        ntlm(top)

def ntlm(ntlm_file):
    ntlm_file = str(ntlm_file[0] + "." + ntlm_file[1])
    
    print "[+] Brute Forcing first 6"
    call("{}{} -a3 {} -i ?a?a?a?a?a?a -m 1000".format(ocl_hash_dir, ocl_file, ntlm_file))
    
    print "[+] RockYou + Best64"
    command = "{}{} -a0 {} -r {}rules\\best64.rule {} -m 1000".format(ocl_hash_dir, ocl_file, ntlm_file, ocl_hash_dir, rock_you)
    call(command, shell=False);
    
    print "[+] RockYou + PasswordsPro"
    command = "{}{} -a0 {} -r {}rules\\InsidePro-PasswordsPro.rule {} -m 1000".format(ocl_hash_dir, ocl_file, ntlm_file, ocl_hash_dir, rock_you)
    call(command, shell=False);

    print "[+] RockYou + rockyou-30000"
    command = "{}{} -a0 {} -r {}rules\\rockyou-30000.rule {} -m 1000".format(ocl_hash_dir, ocl_file, ntlm_file, ocl_hash_dir, rock_you)
    call(command, shell=False);

    print "[+] RockYou + leetspeak"
    command = "{}{} -a0 {} -r {}rules\\leetspeak.rule {} -m 1000".format(ocl_hash_dir, ocl_file, ntlm_file, ocl_hash_dir, rock_you)
    call(command, shell=False);

    print "[+] RockYou + d3ad0ne"
    command = "{}{} -a0 {} -r {}rules\\d3ad0ne.rule {} -m 1000".format(ocl_hash_dir, ocl_file, ntlm_file, ocl_hash_dir, rock_you)
    call(command, shell=False);
    
    combine_output(ntlm_file)


def combine_output(ntlm_file):
    list_ntlm_split = []
    list_passwords_split = []
    
    with open(ntlm_file) as f:
        for line in f:
            line_split = line.split(':')
            list_ntlm_split.append(((line_split[0]), (line_split[3]).lower()))

    with open("cudaHashcat.pot") as f:
        for line in f:
            line_split = line.split(':')
            list_passwords_split.append((line_split[1].replace("\n", ""), line_split[0]))

    D = {v:[k, False] for k, v in list_passwords_split}
    for value, key in list_ntlm_split:
        if key in D:
            D[key][1] = value
            
    output_list = (tuple([key]+value) for key, value in D.iteritems())

    #print output_list
    #output_file = open(ntlm_file.split(".")[0], 'w')

    #remove("cudaHashcat.pot")

    for item in output_list:
        print "User: {} Password: {}".format(item[2], item[1])
        #output_file.write("{}:{}".format(item[1], item[0]))
        
    #TODO: Find some sort of standard for outputting these things and stipol
    #TODO: Add pipal to password statistics
    

def main():
    print "Using Path: {}".format(path_to_watch)
    c, conn = setup_database()
    insert(c)
    
    try:
        while(1):
            insert(c)
            queue_files(c)

            if not queue.empty():
                cracker_jack()
            else:
                conn.commit()
                conn.close()
                exit()
                
                wait()
                
    except (KeyboardInterrupt, SystemExit):
        print "[+] Exit detected, saving and closing database"
        conn.commit()
        conn.close()
            

if __name__ == "__main__":
    main()
